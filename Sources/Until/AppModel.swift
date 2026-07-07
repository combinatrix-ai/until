import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var state = AppState()
  @Published var config: AppConfig
  @Published private(set) var calendars: [CalendarSummary] = []
  @Published private(set) var isRefreshing = false
  @Published private(set) var isSigningIn = false
  @Published private(set) var signInError: String?
  @Published private(set) var isSendingTestNotification = false
  @Published private(set) var testNotificationError: String?
  @Published private(set) var notificationAuthorizationState: NotificationAuthorizationState = .unknown
  @Published private(set) var expandedEventKey: String?
  @Published private(set) var noteResults: [String: MeetingNoteResult] = [:]
  @Published private(set) var noteErrors: [String: NoteIssue] = [:]
  @Published private(set) var creatingNoteKey: String?
  @Published private(set) var conferenceErrors: [String: String] = [:]
  @Published private(set) var addingConferenceKey: String?
  @Published private(set) var creatingTemplateEmail: String?
  @Published private(set) var templateErrors: [String: String] = [:]
  @Published var externalSharePrompt: ExternalSharePrompt?
  @Published private(set) var launchAtLoginEnabled = false
  @Published private(set) var launchAtLoginError: String?

  /// Launch-at-login via `SMAppService` only works from a real .app bundle. In
  /// bare `swift run` dev mode the row is shown disabled — same bundle check
  /// `EventNotifier` uses to pick its notification backend.
  let launchAtLoginAvailable = Bundle.main.bundleURL.pathExtension == "app"

  private let runtimeOptions: AppRuntimeOptions
  private let store = ConfigStore()
  private let notifier = EventNotifier()
  private var accounts: [GoogleAuth] = []
  private var rawEvents: [CalendarEvent] = []
  private var refreshTimer: Timer?
  private var clockTimer: Timer?
  private var wakeObserver: NSObjectProtocol?

  init(options: AppRuntimeOptions = .fromProcess()) {
    runtimeOptions = options
    config = options.demoMode ? DemoCalendarData.config() : store.load()
    observeWake()
    refreshLaunchAtLoginState()
    applyDefaultLaunchAtLoginIfNeeded()
    if runtimeOptions.demoMode {
      notificationAuthorizationState = .unavailable
      loadDemoData(now: Date())
      startTimers()
      return
    }
    accounts = KeychainStore.loadTokens().map { GoogleAuth(config: config, token: $0) }
    updateAuthState()
    startTimers()
    Task {
      await refreshNotificationAuthorizationState()
      await refresh()
    }
  }

  deinit {
    if let wakeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
    }
  }

  func saveConfig(_ next: AppConfig) {
    config = normalized(next)
    if runtimeOptions.demoMode {
      loadDemoData(now: Date())
      startTimers()
      return
    }
    persistConfig()
    accounts.forEach { $0.configure(config) }
    startTimers()
    Task {
      await refreshCalendars()
      await refresh()
    }
  }

  func login() async {
    guard !runtimeOptions.demoMode else {
      signInError = loc("Google sign-in is disabled in demo mode.")
      return
    }
    isSigningIn = true
    signInError = nil
    if accounts.isEmpty {
      state.lastError = nil
    }
    defer { isSigningIn = false }
    do {
      let auth = GoogleAuth(config: config)
      try await auth.login()
      let isNewAccount = !accounts.contains { $0.email.caseInsensitiveCompare(auth.email) == .orderedSame }
      accounts.removeAll { $0.email.caseInsensitiveCompare(auth.email) == .orderedSame }
      accounts.append(auth)
      updateAuthState()
      await refreshCalendars()
      if isNewAccount {
        selectAccountCalendars(forNewAccountEmail: auth.email)
      }
      await refresh()
    } catch {
      signInError = error.localizedDescription
      if accounts.isEmpty {
        state.lastError = error.localizedDescription
      }
    }
  }

  func reauthorize(email: String) async {
    guard !runtimeOptions.demoMode else {
      signInError = loc("Google sign-in is disabled in demo mode.")
      return
    }
    let expectedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !expectedEmail.isEmpty else { return }

    isSigningIn = true
    signInError = nil
    defer { isSigningIn = false }
    do {
      let auth = GoogleAuth(config: config)
      try await auth.login(loginHint: expectedEmail, expectedEmail: expectedEmail)
      accounts.removeAll { $0.email.caseInsensitiveCompare(expectedEmail) == .orderedSame }
      accounts.append(auth)
      updateAuthState()
      await refreshCalendars()
      await refresh()
    } catch {
      signInError = error.localizedDescription
    }
  }

  func logout(email: String? = nil) async {
    guard !runtimeOptions.demoMode else {
      loadDemoData(now: Date())
      return
    }
    do {
      if let email {
        let removed = accounts.first(where: { $0.email.caseInsensitiveCompare(email) == .orderedSame })
        accounts.removeAll { $0.email.caseInsensitiveCompare(email) == .orderedSame }
        removeAccountConfiguration(email: email)
        try await removed?.revokeAndLogout()
      } else {
        let removed = accounts
        try KeychainStore.remove()
        accounts.removeAll()
        removeAllAccountConfiguration()
        for account in removed {
          try? await account.revokeAndLogout()
        }
      }
      rawEvents = []
      calendars = []
      signInError = nil
      state.lastError = nil
      reapplyFilter()
      updateAuthState()
    } catch {
      state.lastError = error.localizedDescription
    }
  }

  func refresh() async {
    if runtimeOptions.demoMode {
      isRefreshing = true
      loadDemoData(now: Date())
      isRefreshing = false
      return
    }
    guard !accounts.isEmpty else {
      reapplyFilter()
      return
    }
    isRefreshing = true
    defer { isRefreshing = false }

    let now = Date()
    let results = await fetchAllAccounts(
      selectedIds: config.selectedCalendarIds,
      lookaheadHours: config.lookaheadHours,
      now: now
    )
    applyFetchResults(results, now: now)
    reapplyFilter()
  }

  /// Fetches each account's calendars and events concurrently, tolerating
  /// per-account failure: one account throwing must not discard events from
  /// healthy accounts. Each task returns either the account's events (list
  /// once + fetch) or an error message tagged with the account email. The
  /// calendar list is fetched once per account here (updating the published
  /// `calendars`), replacing the old duplicate round-trip via `fetchEvents` +
  /// `refreshCalendars`.
  private func fetchAllAccounts(
    selectedIds: [String],
    lookaheadHours: Int,
    now: Date
  ) async -> [AccountFetchResult] {
    let accounts = self.accounts
    return await withTaskGroup(of: AccountFetchResult.self) { group -> [AccountFetchResult] in
      for account in accounts {
        group.addTask {
          let client = CalendarClient(auth: account)
          let email = await account.email
          do {
            let calendars = try await client.listCalendars(selectedIds: selectedIds)
            let events = try await client.fetchEvents(
              calendars: calendars.filter(\.selected),
              lookaheadHours: lookaheadHours,
              now: now
            )
            return AccountFetchResult(email: email, calendars: calendars, events: events, error: nil)
          } catch {
            return AccountFetchResult(
              email: email,
              calendars: nil,
              events: nil,
              error: error.localizedDescription
            )
          }
        }
      }
      var collected: [AccountFetchResult] = []
      for await result in group {
        collected.append(result)
      }
      return collected
    }
  }

  /// Aggregates per-account results, publishing the merged events/calendars
  /// only when at least one account succeeded — so a transient outage on
  /// every account leaves previously cached events (`rawEvents`) untouched
  /// instead of wiping the panel.
  private func applyFetchResults(_ results: [AccountFetchResult], now: Date) {
    var fetchedEvents: [CalendarEvent] = []
    var fetchedCalendars: [CalendarSummary] = []
    var errors: [String] = []
    var anySucceeded = false
    for result in results {
      if let error = result.error {
        errors.append("\(result.email): \(error)")
      } else {
        anySucceeded = true
        fetchedEvents.append(contentsOf: result.events ?? [])
        fetchedCalendars.append(contentsOf: result.calendars ?? [])
      }
    }

    if anySucceeded {
      rawEvents = fetchedEvents.sorted { $0.startDate < $1.startDate }
      calendars = fetchedCalendars.sorted { $0.name < $1.name }
      state.lastSync = now
    }
    state.lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
  }

  func refreshCalendars() async {
    if runtimeOptions.demoMode {
      calendars = DemoCalendarData.calendars(selectedIds: config.selectedCalendarIds)
      return
    }
    guard !accounts.isEmpty else {
      calendars = []
      return
    }
    let selectedIds = config.selectedCalendarIds
    let accounts = self.accounts
    do {
      let next = try await withThrowingTaskGroup(
        of: [CalendarSummary].self
      ) { group -> [CalendarSummary] in
        for account in accounts {
          group.addTask {
            let client = CalendarClient(auth: account)
            return try await client.listCalendars(selectedIds: selectedIds)
          }
        }
        var collected: [CalendarSummary] = []
        for try await summaries in group {
          collected.append(contentsOf: summaries)
        }
        return collected
      }
      calendars = next.sorted { $0.name < $1.name }
    } catch {
      state.lastError = error.localizedDescription
    }
  }

  func setCalendar(_ id: String, selected: Bool) {
    var ids = Set(config.selectedCalendarIds)
    if ids.isEmpty {
      ids = Set(calendars.map(\.id))
    }
    if selected {
      ids.insert(id)
    } else {
      ids.remove(id)
    }
    var next = config
    next.selectedCalendarIds = Array(ids).sorted()
    saveConfig(next)
  }

  /// When a brand-new account is added, all of its calendars should end up
  /// selected.
  private func selectAccountCalendars(forNewAccountEmail email: String) {
    guard let next = Self.selectedCalendarIds(
      config.selectedCalendarIds,
      addingCalendarsFrom: calendars,
      forAccountEmail: email
    ) else { return }
    var nextConfig = config
    nextConfig.selectedCalendarIds = next
    saveConfig(nextConfig)
  }

  /// Pure helper: returns the new sorted selection with all of the given
  /// account's calendar ids added, or nil if there's nothing to change.
  /// Selection is left unchanged when it's already "all" (empty array), when
  /// there are no matching calendars, or when they're all already selected.
  static func selectedCalendarIds(
    _ selectedCalendarIds: [String],
    addingCalendarsFrom calendars: [CalendarSummary],
    forAccountEmail email: String
  ) -> [String]? {
    guard !selectedCalendarIds.isEmpty else { return nil }
    let accountCalendarIds = calendars
      .filter { $0.accountEmail.caseInsensitiveCompare(email) == .orderedSame }
      .map(\.id)
    guard !accountCalendarIds.isEmpty else { return nil }
    var ids = Set(selectedCalendarIds)
    let sizeBefore = ids.count
    ids.formUnion(accountCalendarIds)
    guard ids.count != sizeBefore else { return nil }
    return Array(ids).sorted()
  }

  func open(_ event: CalendarEvent) {
    guard let url = EventLinks.eventURL(for: event) else { return }
    NSWorkspace.shared.open(url)
  }

  // MARK: - Launch at login

  /// Reads the live `SMAppService.mainApp` status. This is system state, not
  /// persisted config. When not running as an app bundle the toggle is inert.
  func refreshLaunchAtLoginState() {
    guard launchAtLoginAvailable else {
      launchAtLoginEnabled = false
      return
    }
    launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
  }

  /// Registers launch-at-login the first time a real .app build starts, then
  /// records the fact so the user's later choice is never overridden. Runs at
  /// init and is a no-op in demo mode, when the bundle can't register, or once
  /// the default has already been applied.
  private func applyDefaultLaunchAtLoginIfNeeded() {
    guard !runtimeOptions.demoMode, launchAtLoginAvailable else { return }
    guard AppModel.shouldApplyDefaultLaunchAtLogin(
      alreadyApplied: config.didApplyDefaultLaunchAtLogin
    ) else { return }
    // Register only if not already enabled; a registration failure still marks
    // the default applied (we try exactly once) and surfaces via launchAtLoginError.
    if !launchAtLoginEnabled {
      setLaunchAtLogin(true)
    }
    config.didApplyDefaultLaunchAtLogin = true
    persistConfig()
  }

  /// Pure decision: apply the launch-at-login default only when it has never
  /// been applied before. Availability/demo gating lives at the call site.
  nonisolated static func shouldApplyDefaultLaunchAtLogin(alreadyApplied: Bool) -> Bool {
    !alreadyApplied
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    guard launchAtLoginAvailable else { return }
    launchAtLoginError = nil
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      launchAtLoginError = error.localizedDescription
    }
    refreshLaunchAtLoginState()
  }

  // MARK: - Join next meeting

  /// Opens the next joinable meeting: the current/next event if it has a
  /// conference URL, otherwise the first upcoming timed event that does.
  /// Returns false when nothing is joinable so callers can fall back.
  @discardableResult
  func joinNextMeeting() -> Bool {
    let candidate = state.next.flatMap { $0.conferenceUrl.isEmpty ? nil : $0 }
      ?? state.events.first { !$0.allDay && !$0.conferenceUrl.isEmpty }
    guard let event = candidate else { return false }
    join(event)
    return true
  }

  /// Expansion is keyed per day so a multi-day all-day event repeated across
  /// sections expands only on the row that was tapped.
  func expansionKey(for event: CalendarEvent, on day: Date) -> String {
    "\(day.timeIntervalSinceReferenceDate)::\(event.actionKey)"
  }

  func toggleExpanded(_ event: CalendarEvent, on day: Date) {
    let key = expansionKey(for: event, on: day)
    expandedEventKey = expandedEventKey == key ? nil : key
  }

  func collapseEventDetails() {
    expandedEventKey = nil
  }

  func isExpanded(_ event: CalendarEvent, on day: Date) -> Bool {
    expandedEventKey == expansionKey(for: event, on: day)
  }

  func join(_ event: CalendarEvent) {
    guard let url = EventLinks.conferenceURL(for: event) else { return }
    NSWorkspace.shared.open(url)
  }

  func noteURL(for event: CalendarEvent) -> String {
    noteResults[event.actionKey]?.webViewLink ?? event.notesUrl
  }

  func isCreatingNote(for event: CalendarEvent) -> Bool {
    creatingNoteKey == event.actionKey
  }

  func noteError(for event: CalendarEvent) -> NoteIssue? {
    noteErrors[event.actionKey]
  }

  /// Returns true when the event's account is known to lack the Drive scope
  /// required to create notes (i.e. the user unchecked it at consent time).
  /// Unknown grant sets (existing users) return false — no warning.
  func lacksDriveScope(for accountEmail: String) -> Bool {
    guard let account = accounts.first(
      where: { $0.email.caseInsensitiveCompare(accountEmail) == .orderedSame }
    ) else { return false }
    return !account.hasScope(driveFileScope)
  }

  func isAddingConference(for event: CalendarEvent) -> Bool {
    addingConferenceKey == event.actionKey
  }

  func conferenceError(for event: CalendarEvent) -> String? {
    conferenceErrors[event.actionKey]
  }

  func addConference(for event: CalendarEvent) {
    let key = event.actionKey
    if runtimeOptions.demoMode {
      rawEvents = rawEvents.map { current in
        guard current.actionKey == key else { return current }
        var next = current
        next.hangoutLink = "https://meet.google.com/demo-until-app"
        next.conferenceUrl = "https://meet.google.com/demo-until-app"
        return next
      }
      reapplyFilter()
      return
    }
    addingConferenceKey = key
    conferenceErrors[key] = nil
    Task {
      defer { addingConferenceKey = nil }
      do {
        guard let account = accounts.first(where: { $0.email == event.account.email }) else {
          throw AppError.message(loc("Google account is not connected: %@", event.account.email))
        }
        let client = MeetingNotesClient(auth: account)
        _ = try await client.addConference(for: event)
        await refresh()
      } catch {
        conferenceErrors[key] = error.localizedDescription
      }
    }
  }

  func meetingNotesFolder(for accountEmail: String) -> DriveFolderRef? {
    config.meetingNotesFoldersByAccount[accountEmail]
  }

  /// Opens the app-managed notes folder in Google Drive (authuser-attached), if
  /// one has been created/stored for the account.
  func openNotesFolder(for accountEmail: String) {
    guard let folder = config.meetingNotesFoldersByAccount[accountEmail], !folder.id.isEmpty else { return }
    let raw = "https://drive.google.com/drive/folders/\(folder.id)"
    guard let url = EventLinks.authenticatedURL(from: raw, accountEmail: accountEmail) else { return }
    NSWorkspace.shared.open(url)
  }

  func meetingNotesTemplateDocId(for accountEmail: String) -> String? {
    config.meetingNotesTemplateDocsByAccount[accountEmail]?.nilIfEmpty
  }

  func isCreatingTemplate(for accountEmail: String) -> Bool {
    creatingTemplateEmail?.caseInsensitiveCompare(accountEmail) == .orderedSame
  }

  func templateError(for accountEmail: String) -> String? {
    templateErrors[accountEmail]
  }

  /// Creates an app-managed template Google Doc for the account, stores its id,
  /// and opens it in the browser for editing.
  func createTemplateDoc(for accountEmail: String) {
    guard !runtimeOptions.demoMode else {
      var next = config
      next.meetingNotesTemplateDocsByAccount[accountEmail] = "demo-template-\(accountEmail)"
      saveConfig(next)
      return
    }
    creatingTemplateEmail = accountEmail
    templateErrors[accountEmail] = nil
    Task {
      defer { creatingTemplateEmail = nil }
      do {
        let client = try meetingNotesClient(for: accountEmail)
        let result = try await client.createTemplateDoc(
          folder: config.meetingNotesFoldersByAccount[accountEmail],
          folderName: config.meetingNotesFolderNamesByAccount[accountEmail]
        )
        var next = config
        next.meetingNotesTemplateDocsByAccount[accountEmail] = result.id
        if let folder = result.resolvedFolder {
          next.meetingNotesFoldersByAccount[accountEmail] = folder
        }
        saveConfig(next)
        openNote(url: result.webViewLink, accountEmail: accountEmail)
      } catch {
        templateErrors[accountEmail] = error.localizedDescription
      }
    }
  }

  /// Opens the account's app-created template doc for editing (authuser-attached).
  func editTemplateDoc(for accountEmail: String) {
    guard let id = meetingNotesTemplateDocId(for: accountEmail) else { return }
    let raw = "https://docs.google.com/document/d/\(id)/edit"
    openNote(url: raw, accountEmail: accountEmail)
  }

  /// Forgets the stored template doc id (does not delete the doc itself).
  func removeTemplateDoc(for accountEmail: String) {
    var next = config
    next.meetingNotesTemplateDocsByAccount.removeValue(forKey: accountEmail)
    templateErrors[accountEmail] = nil
    saveConfig(next)
  }

  func createOrOpenNote(for event: CalendarEvent) {
    let notesUrl = noteURL(for: event)
    if !notesUrl.isEmpty {
      openNote(url: notesUrl, accountEmail: event.account.email)
      return
    }

    let external = externalAttendees(for: event)
    if !external.isEmpty {
      externalSharePrompt = ExternalSharePrompt(event: event, externalAttendees: external)
      return
    }

    Task {
      await createNote(for: event, shareExternalAttendees: true)
    }
  }

  func resolveExternalShare(shareExternalAttendees: Bool) {
    guard let prompt = externalSharePrompt else { return }
    externalSharePrompt = nil
    Task {
      await createNote(for: prompt.event, shareExternalAttendees: shareExternalAttendees)
    }
  }

  func cancelExternalSharePrompt() {
    externalSharePrompt = nil
  }

  func sendTestNotification() async {
    isSendingTestNotification = true
    testNotificationError = nil
    state.lastError = nil
    defer {
      isSendingTestNotification = false
    }
    do {
      try await notifier.sendTestNotification()
    } catch {
      testNotificationError = error.localizedDescription
    }
    await refreshNotificationAuthorizationState()
  }

  func refreshNotificationAuthorizationState() async {
    notificationAuthorizationState = await notifier.authorizationState()
  }

  func openNotificationSettings() {
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "ai.combinatrix.until"
    let urls = [
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleIdentifier)",
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    ]
    for value in urls {
      guard let url = URL(string: value), NSWorkspace.shared.open(url) else { continue }
      return
    }
  }

  func filterPreview(for rule: Rule) -> FilterPreviewResult {
    let now = Date()
    let refreshed = refreshedRawEvents(now: now)
    let matched = refreshed.reduce(0) { count, event in
      count + (RuleEngine.evaluate(rule, event: event, now: now) ? 1 : 0)
    }
    let sample = refreshed.prefix(25).map { event in
      FilterPreviewSample(
        id: "\(event.account.email)-\(event.calendar.id)-\(event.id)-\(event.startISO)",
        title: event.title,
        startDate: event.startDate,
        passed: RuleEngine.evaluate(rule, event: event, now: now)
      )
    }
    return FilterPreviewResult(matched: matched, total: refreshed.count, sample: sample)
  }

  private func reapplyFilter() {
    let now = Date()
    let refreshed = refreshedRawEvents(now: now)
    let passed = RuleEngine.apply(config.filterRules, to: refreshed, now: now)
      .filter { $0.endDate > now }
    let timed = passed.filter { !$0.allDay }.sorted(by: compareEvents)
    let allDay = passed.filter(\.allDay).sorted { $0.startDate < $1.startDate }
    state.events = timed
    state.allDayEvents = allDay
    state.next = pickMenubarEvent(timed: timed, allDay: allDay, now: now)
    state.filterError = nil
    let notificationEvents = config.notifyVideoOnly ? timed.filter { !$0.conferenceUrl.isEmpty } : timed
    guard !runtimeOptions.demoMode else { return }
    Task {
      await notifier.sync(
        events: notificationEvents,
        leadMinutes: config.notifyLeadMinutes,
        enabled: config.notifyEnabled
      )
    }
  }

  /// Events grouped into day sections for display. Multi-day all-day events are
  /// repeated on each day they cover, clamped to the lookahead window.
  var daySections: [DaySection] {
    Self.groupByDay(
      timed: state.events,
      allDay: state.allDayEvents,
      now: Date(),
      lookaheadHours: config.lookaheadHours
    )
  }

  static func groupByDay(
    timed: [CalendarEvent],
    allDay: [CalendarEvent],
    now: Date,
    lookaheadHours: Int
  ) -> [DaySection] {
    let calendar = Calendar.current
    let windowStart = calendar.startOfDay(for: now)
    let windowEndDay = calendar.startOfDay(
      for: now.addingTimeInterval(TimeInterval(max(0, lookaheadHours) * 3600))
    )

    // All-day events span [startDate, endDate) where endDate is exclusive
    // (Google's `end.date` is the day after the last day). Repeat each event on
    // every covered day within the visible window.
    var allDayByDay: [Date: [CalendarEvent]] = [:]
    for event in allDay {
      var day = max(calendar.startOfDay(for: event.startDate), windowStart)
      while day < event.endDate && day <= windowEndDay {
        allDayByDay[day, default: []].append(event)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = next
      }
    }

    var timedByDay: [Date: [CalendarEvent]] = [:]
    for event in timed {
      timedByDay[calendar.startOfDay(for: event.startDate), default: []].append(event)
    }

    let days = Set(allDayByDay.keys).union(timedByDay.keys).sorted()
    return days.map { day in
      let events = (allDayByDay[day] ?? []) + (timedByDay[day] ?? [])
      return DaySection(day: day, rows: events.map { DayEvent(day: day, event: $0) })
    }
  }

  private func refreshedRawEvents(now: Date) -> [CalendarEvent] {
    rawEvents.map { event in
      var event = event
      event.startMinutesFromNow = Int((event.startDate.timeIntervalSince(now) / 60).rounded())
      return event
    }
  }

  private func pickMenubarEvent(
    timed events: [CalendarEvent],
    allDay allDayEvents: [CalendarEvent],
    now: Date
  ) -> CalendarEvent? {
    if let current = events.first(where: { $0.startDate <= now && $0.endDate > now }) {
      return current
    }
    if config.menubarShowsNextAlways {
      // Always surface the next upcoming timed event, regardless of lead time.
      if let upcoming = events.first(where: { $0.startDate.timeIntervalSince(now) >= 0 }) {
        return upcoming
      }
    } else {
      let lead = TimeInterval(max(0, config.menubarLeadMinutes) * 60)
      if let upcoming = events.first(where: { event in
        let startsIn = event.startDate.timeIntervalSince(now)
        return startsIn >= 0 && startsIn <= lead
      }) {
        return upcoming
      }
    }
    return allDayEvents.first { event in
      event.startDate <= now && event.endDate > now
    }
  }

  private func compareEvents(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
    if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
    let accepted = sortRank(lhs.selfResponse == "accepted", rhs.selfResponse == "accepted")
    if let accepted { return accepted }
    let busy = sortRank(lhs.transparency == "busy", rhs.transparency == "busy")
    if let busy { return busy }
    let primary = sortRank(lhs.calendar.primary, rhs.calendar.primary)
    if let primary { return primary }
    if lhs.durationMinutes != rhs.durationMinutes { return lhs.durationMinutes < rhs.durationMinutes }
    return lhs.title < rhs.title
  }

  private func sortRank(_ lhs: Bool, _ rhs: Bool) -> Bool? {
    lhs == rhs ? nil : lhs && !rhs
  }

  /// Refresh calendar data when the machine wakes — timers can be delayed or
  /// coalesced across sleep, so an explicit refresh keeps the menubar current.
  private func observeWake() {
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in await self?.refresh() }
    }
  }

  private func startTimers() {
    refreshTimer?.invalidate()
    clockTimer?.invalidate()
    refreshTimer = Timer.scheduledTimer(
      withTimeInterval: TimeInterval(max(30, config.pollIntervalSeconds)),
      repeats: true
    ) { [weak self] _ in
      Task { @MainActor in await self?.refresh() }
    }
    clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.reapplyFilter() }
    }
  }

  private func loadDemoData(now: Date) {
    calendars = DemoCalendarData.calendars(selectedIds: config.selectedCalendarIds)
    rawEvents = DemoCalendarData.events(now: now, selectedIds: config.selectedCalendarIds)
    state.auth = DemoCalendarData.accountState()
    state.lastSync = now
    state.lastError = nil
    signInError = nil
    reapplyFilter()
  }

  private func updateAuthState() {
    let accountStates = accounts
      .filter(\.isAuthenticated)
      .map { AccountState(email: $0.email, authenticated: true) }
      .sorted { $0.email < $1.email }
    state.auth = AuthState(
      authenticated: !accountStates.isEmpty,
      email: accountStates.first?.email ?? "",
      accounts: accountStates
    )
  }

  private func createNote(for event: CalendarEvent, shareExternalAttendees: Bool) async {
    let key = event.actionKey
    creatingNoteKey = key
    noteErrors[key] = nil
    state.lastError = nil
    defer { creatingNoteKey = nil }

    do {
      if runtimeOptions.demoMode {
        noteResults[key] = DemoCalendarData.noteResult(for: event)
        return
      }
      guard let account = accounts.first(
        where: { $0.email.caseInsensitiveCompare(event.account.email) == .orderedSame }
      ) else {
        throw AppError.message("Google account is not connected: \(event.account.email)")
      }
      // Fail fast when Drive access is known-not-granted, surfacing a
      // reauthorize prompt instead of an opaque 403 from the API.
      guard account.hasScope(driveFileScope) else {
        noteErrors[key] = NoteIssue.missingDriveScope(email: event.account.email)
        return
      }
      let client = MeetingNotesClient(auth: account)
      // The stored value is now an app-created doc id; tolerate a legacy URL by
      // extracting the id from it.
      let templateDocRaw = config.meetingNotesTemplateDocsByAccount[event.account.email] ?? ""
      let options = NoteCreationOptions(
        folder: config.meetingNotesFoldersByAccount[event.account.email],
        folderName: config.meetingNotesFolderNamesByAccount[event.account.email],
        titleTemplate: config.meetingNotesTitleTemplatesByAccount[event.account.email],
        templateDocId: GoogleDocLinks.documentId(from: templateDocRaw) ?? templateDocRaw.nilIfEmpty,
        shareExternalAttendees: shareExternalAttendees
      )
      let result = try await client.createNote(for: event, options: options)
      noteResults[key] = result
      // Persist a (re)resolved app-managed folder so settings can show it and
      // future runs skip the lookup.
      if let folder = result.resolvedFolder {
        var next = config
        next.meetingNotesFoldersByAccount[event.account.email] = folder
        saveConfig(next)
      }
      // Surface a non-fatal template fallback as a per-event note error.
      if let templateError = result.templateError {
        noteErrors[key] = NoteIssue(message: templateError, kind: .retry)
      }
      await refresh()
      openNote(url: result.webViewLink, accountEmail: event.account.email)
    } catch {
      let message = error.localizedDescription
      // A post-grant revocation surfaces as an insufficient-scope 403; convert
      // it to the same friendly reauthorize prompt as the known-not-granted case.
      if isInsufficientScopeError(message) {
        noteErrors[key] = NoteIssue.missingDriveScope(email: event.account.email)
      } else {
        noteErrors[key] = NoteIssue(message: message, kind: .retry)
      }
    }
  }

  private func openNote(url rawValue: String, accountEmail: String) {
    guard let url = EventLinks.authenticatedURL(from: rawValue, accountEmail: accountEmail) else { return }
    NSWorkspace.shared.open(url)
  }

  private func meetingNotesClient(for accountEmail: String) throws -> MeetingNotesClient {
    guard let account = accounts.first(where: { $0.email.caseInsensitiveCompare(accountEmail) == .orderedSame }) else {
      throw AppError.message(loc("Google account is not connected: %@", accountEmail))
    }
    return MeetingNotesClient(auth: account)
  }

  private func removeAccountConfiguration(email: String) {
    let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalizedEmail.isEmpty else { return }

    var next = config
    next.selectedCalendarIds.removeAll { id in
      let normalizedId = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return normalizedId == normalizedEmail || normalizedId.hasPrefix("\(normalizedEmail)::")
    }
    next.meetingNotesFoldersByAccount.removeValue(forCaseInsensitiveKey: email)
    next.meetingNotesFolderNamesByAccount.removeValue(forCaseInsensitiveKey: email)
    next.meetingNotesTitleTemplatesByAccount.removeValue(forCaseInsensitiveKey: email)
    next.meetingNotesTemplateDocsByAccount.removeValue(forCaseInsensitiveKey: email)
    templateErrors.removeValue(forCaseInsensitiveKey: email)
    config = next
    persistConfig()
  }

  private func removeAllAccountConfiguration() {
    var next = config
    next.selectedCalendarIds = []
    next.meetingNotesFoldersByAccount = [:]
    next.meetingNotesFolderNamesByAccount = [:]
    next.meetingNotesTitleTemplatesByAccount = [:]
    next.meetingNotesTemplateDocsByAccount = [:]
    templateErrors = [:]
    config = next
    persistConfig()
  }

  /// Persists the current config, surfacing (rather than swallowing) failures so
  /// the user learns their settings weren't saved.
  private func persistConfig() {
    do {
      try store.save(config)
    } catch {
      state.lastError = loc("Failed to save settings: %@", error.localizedDescription)
    }
  }

  private func externalAttendees(for event: CalendarEvent) -> [String] {
    let ownerDomain = event.account.email.emailDomain
    let emails = Set(event.attendees.compactMap { attendee -> String? in
      guard !attendee.resource else { return nil }
      let email = attendee.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard !email.isEmpty, email.emailDomain != ownerDomain else { return nil }
      return email
    })
    return emails.sorted()
  }

  private func normalized(_ config: AppConfig) -> AppConfig {
    var next = config
    next.lookaheadHours = max(1, min(24 * 14, next.lookaheadHours))
    next.pollIntervalSeconds = max(30, min(3600, next.pollIntervalSeconds))
    next.maxTitleLength = max(10, min(120, next.maxTitleLength))
    next.menubarLeadMinutes = max(0, min(720, next.menubarLeadMinutes))
    next.notifyLeadMinutes = max(0, min(120, next.notifyLeadMinutes))
    next.meetingNotesTemplateDocsByAccount = trimmedNonEmpty(next.meetingNotesTemplateDocsByAccount)
    next.meetingNotesFolderNamesByAccount = trimmedNonEmpty(next.meetingNotesFolderNamesByAccount)
    next.meetingNotesTitleTemplatesByAccount = trimmedNonEmpty(next.meetingNotesTitleTemplatesByAccount)
    if next.oauthClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      next.oauthClientId = AppConfig.bundledGoogleClientId
    }
    if next.oauthClientSecret.isEmpty && !self.config.oauthClientSecret.isEmpty {
      next.oauthClientSecret = self.config.oauthClientSecret
    }
    return next
  }

  /// Trims each value and drops entries that become empty.
  private func trimmedNonEmpty(_ dict: [String: String]) -> [String: String] {
    dict.reduce(into: [:]) { result, pair in
      let trimmed = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { result[pair.key] = trimmed }
    }
  }
}

/// A per-event note-creation problem plus the recovery action its overlay
/// should offer. Most failures are transient and offer `.retry`; a missing
/// Drive grant offers `.reauthorize` so the user can re-consent instead.
struct NoteIssue: Equatable {
  enum Kind: Equatable {
    case retry
    case reauthorize(email: String)
  }

  var message: String
  var kind: Kind

  /// The friendly, reauthorize-kind issue shown when Drive access is missing.
  static func missingDriveScope(email: String) -> NoteIssue {
    let key = "Google Drive permission isn't granted. Creating notes docs requires Drive access — " +
      "reauthorize and check the Google Drive checkbox."
    return NoteIssue(message: loc(key), kind: .reauthorize(email: email))
  }
}

/// Per-account outcome of a refresh cycle. `error` is nil on success; on failure
/// `calendars`/`events` are nil and the account is skipped without discarding
/// other accounts' data.
private struct AccountFetchResult {
  var email: String
  var calendars: [CalendarSummary]?
  var events: [CalendarEvent]?
  var error: String?
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }

  var emailDomain: String? {
    split(separator: "@").last.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
  }
}

private extension Dictionary where Key == String {
  mutating func removeValue(forCaseInsensitiveKey key: String) {
    guard let match = keys.first(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) else {
      return
    }
    removeValue(forKey: match)
  }
}
