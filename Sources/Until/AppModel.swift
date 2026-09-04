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

  enum FreeDayHeroDecision: Equatable {
    case notFree
    case free(next: CalendarEvent?)
  }

#if SPARKLE
  /// Sparkle updater. Lives on the model so the Settings "Check for Updates"
  /// button can drive it (the status item no longer has a menu). `startingUpdater`
  /// fires on init, so creating it here also kicks off scheduled background checks.
  let updater = UpdaterController()
#endif

  private let runtimeOptions: AppRuntimeOptions
  private let store = ConfigStore()
  private let notifier = EventNotifier()
  private var accounts: [GoogleAuth] = []
  private var rawEvents: [CalendarEvent] = []
  private var refreshTimer: Timer?
  private var clockTimer: Timer?
  private var wakeObserver: NSObjectProtocol?
  private var signInTask: Task<Void, Never>?
  /// Distinguishes an in-flight fetch from a snapshot whose shaping inputs
  /// have since changed. Older results may still refresh the cache, but they
  /// must never restore coverage metadata for the newer inputs.
  private var calendarRefreshGeneration = 0
  /// The hand-authored demo day from `--demo-json`, when one was given. It
  /// replaces the built-in scenario's calendars, events, and accounts.
  private let demoFixture: DemoFixture?

  init(options: AppRuntimeOptions = .fromProcess()) {
    runtimeOptions = options
    demoFixture = AppModel.loadDemoFixture(path: options.demoFixturePath)
    let demoConfig = DemoCalendarData.config(scenario: options.demoScenario)
    config = options.demoMode
      ? (demoFixture?.appConfig(base: demoConfig) ?? demoConfig)
      : store.load()
    observeWake()
    refreshLaunchAtLoginState()
    applyDefaultLaunchAtLoginIfNeeded()
    if runtimeOptions.demoMode {
      // The notification scenario needs the real authorization state so the
      // system prompt is raised and the reminder can actually be delivered.
      if !runtimeOptions.allowsNotifications {
        notificationAuthorizationState = .unavailable
      }
      loadDemoData(now: Date())
      startTimers()
      if runtimeOptions.allowsNotifications {
        Task { await refreshNotificationAuthorizationState() }
      }
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

  /// Invalidates the calendar snapshot before a shaping input changes or a
  /// calendar-list refresh fails. The next complete event refresh is the only
  /// path that can publish a new non-nil coverage end.
  private func invalidateCalendarCoverage() {
    calendarRefreshGeneration += 1
    state.calendarCoverageEnd = nil
  }

  func saveConfig(_ next: AppConfig) {
    guard RuleValidator.validate(next.filterRules) == nil else { return }
    invalidateCalendarCoverage()
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

  /// Hides `event` from the menubar countdown only — the popover list,
  /// filters, and notifications are unaffected (see `pickMenubarEvent`, which
  /// is the only place `skippedMenubarEvents` is consulted). Bypasses
  /// `saveConfig` (which restarts timers and refetches accounts/calendars)
  /// in favor of the lightweight mutate-then-`reapplyFilter` pattern used by
  /// `removeAccountConfiguration`, so the menubar updates immediately without
  /// the heavier refresh work.
  func skipInMenubar(_ event: CalendarEvent) {
    var next = config
    next.skippedMenubarEvents[event.actionKey] = event.endDate
    config = AppModel.purgingExpiredSkips(next)
    if !runtimeOptions.demoMode {
      persistConfig()
    }
    reapplyFilter()
  }

  /// Restores `event` to menubar consideration.
  func unskipInMenubar(_ event: CalendarEvent) {
    var next = config
    next.skippedMenubarEvents.removeValue(forKey: event.actionKey)
    config = AppModel.purgingExpiredSkips(next)
    if !runtimeOptions.demoMode {
      persistConfig()
    }
    reapplyFilter()
  }

  func isSkippedInMenubar(_ event: CalendarEvent) -> Bool {
    config.skippedMenubarEvents[event.actionKey] != nil
  }

  /// Drops skip entries whose recorded event end date has already passed, so
  /// config.json doesn't accumulate stale keys for events that are long over.
  static func purgingExpiredSkips(_ config: AppConfig, now: Date = Date()) -> AppConfig {
    var next = config
    next.skippedMenubarEvents = next.skippedMenubarEvents.filter { $0.value > now }
    return next
  }

  /// Starts (or restarts) the sign-in flow for a new account. Cancels any
  /// in-flight sign-in first so only one OAuth loopback server runs at a
  /// time.
  func startLogin() {
    signInTask?.cancel()
    signInTask = Task { [weak self] in
      await self?.login()
    }
  }

  /// Starts (or restarts) the reauthorization flow for an existing account.
  /// Cancels any in-flight sign-in first so only one OAuth loopback server
  /// runs at a time.
  func startReauthorize(email: String) {
    signInTask?.cancel()
    signInTask = Task { [weak self] in
      await self?.reauthorize(email: email)
    }
  }

  /// Cancels an in-flight sign-in/reauthorization started via `startLogin()`
  /// or `startReauthorize(email:)`.
  func cancelSignIn() {
    signInTask?.cancel()
  }

  private func login() async {
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
      invalidateCalendarCoverage()
      updateAuthState()
      await refreshCalendars()
      if isNewAccount {
        selectAccountCalendars(forNewAccountEmail: auth.email)
      }
      await refresh()
    } catch {
      if error is CancellationError || Task.isCancelled { return }
      signInError = error.localizedDescription
      if accounts.isEmpty {
        state.lastError = error.localizedDescription
      }
    }
  }

  private func reauthorize(email: String) async {
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
      invalidateCalendarCoverage()
      updateAuthState()
      await refreshCalendars()
      await refresh()
    } catch {
      if error is CancellationError || Task.isCancelled { return }
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
        invalidateCalendarCoverage()
        removeAccountConfiguration(email: email)
        try await removed?.revokeAndLogout()
      } else {
        let removed = accounts
        try KeychainStore.remove()
        accounts.removeAll()
        invalidateCalendarCoverage()
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

    let fetchStart = Date()
    let lookaheadHours = config.lookaheadHours
    calendarRefreshGeneration += 1
    let refreshGeneration = calendarRefreshGeneration
    let results = await fetchAllAccounts(
      selectedIds: config.selectedCalendarIds,
      lookaheadHours: lookaheadHours,
      now: fetchStart
    )
    applyFetchResults(
      results,
      fetchStart: fetchStart,
      lookaheadHours: lookaheadHours,
      generation: refreshGeneration
    )
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
  /// instead of wiping the panel. A result from a superseded refresh
  /// generation is discarded wholesale: publishing any part of it (events,
  /// sync time, error) could pair an older, shorter snapshot with newer
  /// coverage metadata and let the free-day hero overclaim.
  func applyFetchResults(
    _ results: [AccountFetchResult],
    fetchStart: Date,
    lookaheadHours: Int,
    generation: Int
  ) {
    guard generation == calendarRefreshGeneration else { return }
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
      state.lastSync = fetchStart
    }
    if errors.isEmpty && anySucceeded {
      state.calendarCoverageEnd = fetchStart.addingTimeInterval(
        TimeInterval(lookaheadHours) * 3600
      )
    } else {
      state.calendarCoverageEnd = nil
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
      invalidateCalendarCoverage()
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
      invalidateCalendarCoverage()
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

  // MARK: - Join menubar meeting

  @discardableResult
  /// Join the meeting currently shown in the menubar (`state.next`). Returns
  /// false when there's nothing shown or it has no conference URL — the caller
  /// signals that (a status-item shake) rather than silently opening some other
  /// meeting the user can't see.
  func joinMenubarMeeting() -> Bool {
    guard let event = state.next, EventLinks.conferenceURL(for: event) != nil else { return false }
    join(event)
    return true
  }

  /// Expansion uses `DayEvent.id`, the same identity SwiftUI renders, so a
  /// multi-day event expands only on the row that was tapped.
  func toggleExpanded(_ dayEvent: DayEvent) {
    let key = dayEvent.id
    expandedEventKey = expandedEventKey == key ? nil : key
  }

  func collapseEventDetails() {
    expandedEventKey = nil
  }

  func isExpanded(_ dayEvent: DayEvent) -> Bool {
    expandedEventKey == dayEvent.id
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
      count + (RuleEngine.evaluate(rule, event: event) ? 1 : 0)
    }
    let sample = refreshed.prefix(25).map { event in
      FilterPreviewSample(
        id: "\(event.account.email)-\(event.calendar.id)-\(event.id)-\(event.startISO)",
        title: event.title,
        startDate: event.startDate,
        passed: RuleEngine.evaluate(rule, event: event)
      )
    }
    return FilterPreviewResult(matched: matched, total: refreshed.count, sample: sample)
  }

  private func reapplyFilter() {
    let now = Date()
    let refreshed = refreshedRawEvents(now: now)
    let today = Calendar.current.startOfDay(for: now)
    let passed = RuleEngine.apply(config.filterRules, to: refreshed)
      // Keep today's completed rows for the rail. The menubar picker ignores
      // ended events, while the popover needs them above the now-line so the
      // current moment has context when it opens.
      .filter { $0.endDate > today }
    let timed = passed.filter { !$0.allDay }.sorted(by: compareEvents)
    let allDay = passed.filter(\.allDay).sorted { $0.startDate < $1.startDate }
    state.events = timed
    state.allDayEvents = allDay
    state.next = AppModel.pickMenubarEvent(config: config, timed: timed, allDay: allDay, now: now)
    let activeEvents = timed.filter { $0.endDate > now }
    let notificationEvents = config.notifyVideoOnly
      ? activeEvents.filter { !$0.conferenceUrl.isEmpty }
      : activeEvents
    guard runtimeOptions.allowsNotifications else { return }
    Task {
      await notifier.sync(
        events: notificationEvents,
        leadMinutes: config.notifyLeadMinutes,
        enabled: config.notifyEnabled
      )
    }
  }

  /// The event shown in the menubar countdown — literally `state.next`
  /// (see `reapplyFilter`/`pickMenubarEvent`). The popover uses this same
  /// selection as its inline hero input.
  var menubarEvent: CalendarEvent? {
    state.next
  }

  /// Events grouped into day sections for display. Multi-day all-day events are
  /// repeated on each day they cover, clamped to the lookahead window.
  func daySections(now: Date) -> [DaySection] {
    Self.groupByDay(
      timed: state.events,
      allDay: state.allDayEvents,
      now: now,
      lookaheadHours: config.lookaheadHours
    )
  }

  func timelinePresentation(now: Date) -> TimelinePresentation {
    Self.timelinePresentation(
      menubarEvent: menubarEvent,
      config: config,
      timed: state.events,
      now: now,
      coverageEnd: state.calendarCoverageEnd
    )
  }

  func timelineSections(
    presentation: TimelinePresentation,
    now: Date
  ) -> [(section: DaySection, items: [PopoverListItem])] {
    Self.timelineSections(
      daySections(now: now),
      presentation: presentation,
      now: now,
      coverageEnd: state.calendarCoverageEnd
    )
  }

  private func refreshedRawEvents(now: Date) -> [CalendarEvent] {
    rawEvents.map { event in
      var event = event
      event.startMinutesFromNow = Int((event.startDate.timeIntervalSince(now) / 60).rounded())
      return event
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

  /// Reads `--demo-json`, exiting on any problem. A fixture exists to pin one
  /// exact frame, so a typo must stop the run loudly rather than fall back to
  /// the built-in day and hand back a subtly different picture.
  private static func loadDemoFixture(path: String?) -> DemoFixture? {
    guard let path else { return nil }
    do {
      return try DemoFixture.load(path: path)
    } catch {
      FileHandle.standardError.write(Data("until: --demo-json: \(error)\n".utf8))
      exit(1)
    }
  }

  private func loadDemoData(now: Date) {
    if let demoFixture {
      calendars = demoFixture.calendarSummaries(selectedIds: config.selectedCalendarIds)
      do {
        rawEvents = try demoFixture.calendarEvents(now: now, selectedIds: config.selectedCalendarIds)
      } catch {
        FileHandle.standardError.write(Data("until: --demo-json: \(error)\n".utf8))
        exit(1)
      }
      state.auth = AuthState(
        authenticated: true,
        accounts: demoFixture.accountEmails().map { AccountState(email: $0) }
      )
    } else {
      calendars = DemoCalendarData.calendars(selectedIds: config.selectedCalendarIds)
      rawEvents = DemoCalendarData.events(
        now: now,
        selectedIds: config.selectedCalendarIds,
        scenario: runtimeOptions.demoScenario
      )
      state.auth = DemoCalendarData.accountState()
    }
    state.lastSync = now
    state.lastError = nil
    state.calendarCoverageEnd = now.addingTimeInterval(
      TimeInterval(max(0, config.lookaheadHours)) * 3600
    )
    signInError = nil
    reapplyFilter()
  }

  private func updateAuthState() {
    let accountStates = accounts
      .filter(\.isAuthenticated)
      .map { AccountState(email: $0.email) }
      .sorted { $0.email < $1.email }
    state.auth = AuthState(
      authenticated: !accountStates.isEmpty,
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
      presentNoteShareFailureAlert(for: result.failedShareEmails)
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

  private func presentNoteShareFailureAlert(for failedEmails: [String]) {
    guard !failedEmails.isEmpty else { return }
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = loc("Edit access could not be granted")
    alert.informativeText = "\(loc("The note was created, but edit access could not be granted to:"))\n" +
      failedEmails.joined(separator: "\n")
    alert.addButton(withTitle: loc("OK"))
    alert.runModal()
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

  /// Attendees on the account's own domain, excluding the user — the people
  /// who receive edit access automatically when meeting notes are created.
  /// Listed in the notes-creation confirmation so that grant is never silent.
  func sameDomainAttendees(for event: CalendarEvent) -> [String] {
    let ownerEmail = event.account.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let ownerDomain = event.account.email.emailDomain
    let emails = Set(event.attendees.compactMap { attendee -> String? in
      guard !attendee.resource, !attendee.selfUser else { return nil }
      let email = attendee.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard !email.isEmpty, email != ownerEmail, email.emailDomain == ownerDomain else { return nil }
      return email
    })
    return emails.sorted()
  }

  private func normalized(_ config: AppConfig) -> AppConfig {
    var next = config
    next.lookaheadHours = max(1, min(24 * 14, next.lookaheadHours))
    next.pollIntervalSeconds = max(30, min(3600, next.pollIntervalSeconds))
    next.maxTitleLength = max(10, min(120, next.maxTitleLength))
    next.menubarLeadMinutes = AppConfig.snappedMenubarLead(next.menubarLeadMinutes)
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
    // Also purge here so a config load/save cycle (e.g. opening Settings)
    // cleans up stale skip entries even if the user hasn't skipped/unskipped
    // anything recently; `skipInMenubar`/`unskipInMenubar` purge on every
    // mutation for the common case.
    next = AppModel.purgingExpiredSkips(next)
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
struct AccountFetchResult {
  var email: String
  var calendars: [CalendarSummary]?
  var events: [CalendarEvent]?
  var error: String?
}

private extension Dictionary where Key == String {
  mutating func removeValue(forCaseInsensitiveKey key: String) {
    guard let match = keys.first(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) else {
      return
    }
    removeValue(forKey: match)
  }
}
