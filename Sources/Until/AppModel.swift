import AppKit
import Combine
import Foundation

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
  @Published private(set) var noteErrors: [String: String] = [:]
  @Published private(set) var creatingNoteKey: String?
  @Published private(set) var conferenceErrors: [String: String] = [:]
  @Published private(set) var addingConferenceKey: String?
  @Published var externalSharePrompt: ExternalSharePrompt?

  private let store = ConfigStore()
  private let notifier = EventNotifier()
  private var accounts: [GoogleAuth] = []
  private var rawEvents: [CalendarEvent] = []
  private var refreshTimer: Timer?
  private var clockTimer: Timer?

  init() {
    config = store.load()
    accounts = KeychainStore.loadTokens().map { GoogleAuth(config: config, token: $0) }
    updateAuthState()
    startTimers()
    Task {
      await refreshNotificationAuthorizationState()
      await refresh()
    }
  }

  func saveConfig(_ next: AppConfig) {
    config = normalized(next)
    try? store.save(config)
    accounts.forEach { $0.configure(config) }
    startTimers()
    Task {
      await refreshCalendars()
      await refresh()
    }
  }

  func login() async {
    isSigningIn = true
    signInError = nil
    if accounts.isEmpty {
      state.lastError = nil
    }
    defer { isSigningIn = false }
    do {
      let auth = GoogleAuth(config: config)
      try await auth.login()
      accounts.removeAll { $0.email.caseInsensitiveCompare(auth.email) == .orderedSame }
      accounts.append(auth)
      updateAuthState()
      await refreshCalendars()
      await refresh()
    } catch {
      signInError = error.localizedDescription
      if accounts.isEmpty {
        state.lastError = error.localizedDescription
      }
    }
  }

  func reauthorize(email: String) async {
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
    guard !accounts.isEmpty else {
      reapplyFilter()
      return
    }
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      let now = Date()
      var fetched: [CalendarEvent] = []
      for account in accounts {
        let client = CalendarClient(auth: account)
        fetched.append(contentsOf: try await client.fetchEvents(
          selectedIds: config.selectedCalendarIds,
          lookaheadHours: config.lookaheadHours,
          now: now
        ))
      }
      rawEvents = fetched.sorted { $0.startDate < $1.startDate }
      state.lastSync = now
      state.lastError = nil
      reapplyFilter()
      await refreshCalendars()
    } catch {
      state.lastError = error.localizedDescription
    }
  }

  func refreshCalendars() async {
    guard !accounts.isEmpty else {
      calendars = []
      return
    }
    do {
      var next: [CalendarSummary] = []
      for account in accounts {
        let client = CalendarClient(auth: account)
        next.append(contentsOf: try await client.listCalendars(selectedIds: config.selectedCalendarIds))
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

  func open(_ event: CalendarEvent) {
    guard let url = EventLinks.eventURL(for: event) else { return }
    NSWorkspace.shared.open(url)
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

  func noteError(for event: CalendarEvent) -> String? {
    noteErrors[event.actionKey]
  }

  func isAddingConference(for event: CalendarEvent) -> Bool {
    addingConferenceKey == event.actionKey
  }

  func conferenceError(for event: CalendarEvent) -> String? {
    conferenceErrors[event.actionKey]
  }

  func addConference(for event: CalendarEvent) {
    let key = event.actionKey
    addingConferenceKey = key
    conferenceErrors[key] = nil
    Task {
      defer { addingConferenceKey = nil }
      do {
        guard let account = accounts.first(where: { $0.email == event.account.email }) else {
          throw AppError.message("Google account is not connected: \(event.account.email)")
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

  func setMeetingNotesFolder(_ folder: DriveFolderRef, for accountEmail: String) {
    var next = config
    next.meetingNotesFoldersByAccount[accountEmail] = folder
    saveConfig(next)
  }

  func driveRoots(for accountEmail: String) async throws -> [DriveFolderRef] {
    try await meetingNotesClient(for: accountEmail).listDriveRoots()
  }

  func driveFolders(for accountEmail: String, in parent: DriveFolderRef) async throws -> [DriveFolderRef] {
    try await meetingNotesClient(for: accountEmail).listDriveFolders(in: parent)
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
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app.until"
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
    let lead = TimeInterval(max(0, config.menubarLeadMinutes) * 60)
    if let upcoming = events.first(where: { event in
      let startsIn = event.startDate.timeIntervalSince(now)
      return startsIn >= 0 && startsIn <= lead
    }) {
      return upcoming
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
      guard let account = accounts.first(
        where: { $0.email.caseInsensitiveCompare(event.account.email) == .orderedSame }
      ) else {
        throw AppError.message("Google account is not connected: \(event.account.email)")
      }
      let client = MeetingNotesClient(auth: account)
      let templateDocUrl = config.meetingNotesTemplateDocsByAccount[event.account.email] ?? ""
      let result = try await client.createNote(
        for: event,
        folder: config.meetingNotesFoldersByAccount[event.account.email],
        titleTemplate: config.meetingNotesTitleTemplatesByAccount[event.account.email],
        templateDocId: GoogleDocLinks.documentId(from: templateDocUrl) ?? templateDocUrl.nilIfEmpty,
        shareExternalAttendees: shareExternalAttendees
      )
      noteResults[key] = result
      await refresh()
      openNote(url: result.webViewLink, accountEmail: event.account.email)
    } catch {
      noteErrors[key] = error.localizedDescription
    }
  }

  private func openNote(url rawValue: String, accountEmail: String) {
    guard let url = EventLinks.authenticatedURL(from: rawValue, accountEmail: accountEmail) else { return }
    NSWorkspace.shared.open(url)
  }

  private func meetingNotesClient(for accountEmail: String) throws -> MeetingNotesClient {
    guard let account = accounts.first(where: { $0.email.caseInsensitiveCompare(accountEmail) == .orderedSame }) else {
      throw AppError.message("Google account is not connected: \(accountEmail)")
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
    next.meetingNotesTitleTemplatesByAccount.removeValue(forCaseInsensitiveKey: email)
    next.meetingNotesTemplateDocsByAccount.removeValue(forCaseInsensitiveKey: email)
    config = next
    try? store.save(config)
  }

  private func removeAllAccountConfiguration() {
    var next = config
    next.selectedCalendarIds = []
    next.meetingNotesFoldersByAccount = [:]
    next.meetingNotesTitleTemplatesByAccount = [:]
    next.meetingNotesTemplateDocsByAccount = [:]
    config = next
    try? store.save(config)
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
