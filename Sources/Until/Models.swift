import Foundation

struct Attendee: Hashable {
  var email: String
  var name: String
  var responseStatus: String
  var selfUser: Bool
  var resource: Bool
}

/// Where an event or calendar comes from. Google events carry the richer
/// Google-only actions (Meet links, notes docs); Mac calendars are read
/// through EventKit and never leave the machine.
enum EventSource: String, Hashable, Codable {
  case google
  case eventKit
}

struct CalendarRef: Hashable {
  var id: String
  var googleId: String
  var primary: Bool
  var backgroundColor: String
  var source: EventSource = .google
}

/// A non-meeting link found on an event (a spec doc, a design file, a pull
/// request) so the card can surface what the meeting is about.
struct EventLink: Hashable {
  var title: String
  var url: String
}

struct AccountRef: Hashable {
  var email: String
}

struct CalendarEvent: Identifiable, Hashable {
  var id: String
  var title: String
  var description: String
  var location: String
  var startISO: String
  var allDay: Bool
  var status: String
  var startMinutesFromNow: Int
  var durationMinutes: Int
  var calendar: CalendarRef
  var account: AccountRef
  var attendees: [Attendee]
  var organizer: String
  var selfResponse: String
  var isRecurring: Bool
  var conferenceUrl: String
  var notesUrl: String
  var colorId: String
  var transparency: String
  var htmlLink: String
  var links: [EventLink]

  // Parsed once at construction from the source ISO strings. These were previously
  // computed properties that reparsed the ISO strings on every access; they are
  // read O(n log n) times per UI tick (sort comparators, filters, day grouping),
  // so caching avoids repeated `ISO8601DateFormatter` work.
  var startDate: Date
  var endDate: Date

  var actionKey: String { "\(account.email)::\(calendar.googleId)::\(id)" }

  var source: EventSource { calendar.source }

  /// Designated init taking the ISO strings; dates are parsed exactly once here.
  /// Returns nil if either bound fails to parse, so callers can drop the event
  /// instead of substituting a bogus date (which would render as "happening now").
  init?(
    id: String,
    title: String,
    description: String,
    location: String,
    startISO: String,
    endISO: String,
    allDay: Bool,
    status: String,
    startMinutesFromNow: Int,
    durationMinutes: Int,
    calendar: CalendarRef,
    account: AccountRef,
    attendees: [Attendee],
    organizer: String,
    selfResponse: String,
    isRecurring: Bool,
    conferenceUrl: String,
    notesUrl: String,
    colorId: String,
    transparency: String,
    htmlLink: String,
    links: [EventLink] = []
  ) {
    guard let start = ISO8601DateFormatter.shared.date(fromAnyInternetDate: startISO),
          let end = ISO8601DateFormatter.shared.date(fromAnyInternetDate: endISO) else {
      return nil
    }
    self.id = id
    self.title = title
    self.description = description
    self.location = location
    self.startISO = startISO
    self.allDay = allDay
    self.status = status
    self.startMinutesFromNow = startMinutesFromNow
    self.durationMinutes = durationMinutes
    self.calendar = calendar
    self.account = account
    self.attendees = attendees
    self.organizer = organizer
    self.selfResponse = selfResponse
    self.isRecurring = isRecurring
    self.conferenceUrl = conferenceUrl
    self.notesUrl = notesUrl
    self.colorId = colorId
    self.transparency = transparency
    self.htmlLink = htmlLink
    self.links = links
    self.startDate = start
    self.endDate = end
  }

}

/// The uniform event-action sections shared by the row ellipsis menu and the
/// row/card context menu. Applicability depends only on event attachments and
/// the menubar visibility toggle; past and future events use the same shape.
struct EventActionSet: Equatable {
  enum Item: Hashable {
    case joinVideoCall
    case copyMeetingLink
    case openMeetingNotes
    case addGoogleMeet
    case createNotes
    case copyDetails
    case openInCalendar
    case skipInMenubar
    case showInMenubar
  }

  var attached: [Item]
  var addable: [Item]
  var common: [Item]

  static func make(event: CalendarEvent, noteURL: String?, isSkipped: Bool) -> EventActionSet {
    let hasConference = !event.conferenceUrl.isEmpty
    let hasNotes = !(noteURL ?? "").isEmpty

    var attached: [Item] = []
    if hasConference {
      attached += [.joinVideoCall, .copyMeetingLink]
    }
    if hasNotes {
      attached.append(.openMeetingNotes)
    }

    // Adding a Meet link or a notes doc writes to the Google event, so Mac
    // calendar events only get the attached and common actions.
    var addable: [Item] = []
    if event.source == .google {
      if !hasConference && !event.allDay {
        addable.append(.addGoogleMeet)
      }
      if !hasNotes {
        addable.append(.createNotes)
      }
    }

    return EventActionSet(
      attached: attached,
      addable: addable,
      common: [.copyDetails, .openInCalendar, isSkipped ? .showInMenubar : .skipInMenubar]
    )
  }
}

/// One event as it appears on a specific day. A multi-day all-day event yields
/// one `DayEvent` per covered day, each with a distinct `id` so SwiftUI treats
/// the repeated rows as separate identities (independent expansion, etc.).
struct DayEvent: Identifiable, Hashable {
  var day: Date
  var event: CalendarEvent
  var id: String { "\(day.timeIntervalSinceReferenceDate)::\(event.actionKey)" }
}

/// A single calendar day's worth of events for the grouped list.
/// `rows` is ordered all-day first, then timed events by start time.
struct DaySection: Identifiable, Hashable {
  var day: Date
  var rows: [DayEvent]
  var id: Date { day }
}

/// A free-time divider inserted between two consecutive timed rows in the
/// popover list (see `AppModel.insertingFreeGaps`). `until` is the next
/// event's start time; `from` preserves the preceding event's exact end time.
struct FreeGap: Identifiable, Hashable {
  var afterActionKey: String
  var from: Date
  var until: Date
  var durationMinutes: Int
  var id: String { "gap::\(afterActionKey)::\(until.timeIntervalSinceReferenceDate)" }

  init(afterActionKey: String, from: Date, until: Date, durationMinutes: Int) {
    self.afterActionKey = afterActionKey
    self.from = from
    self.until = until
    self.durationMinutes = durationMinutes
  }
}

/// One row rendered in the popover's event list: either a calendar event, a
/// `FreeGap` divider, or a marker for a future day with no fetched events.
/// Keeps the row-decision logic pure and independent of the SwiftUI list itself.
enum PopoverListItem: Identifiable, Hashable {
  case event(DayEvent)
  case gap(FreeGap)
  case freeDay(Date)
  case freeDayHero(Date)
  case nowLine(Date)

  var id: String {
    switch self {
    case .event(let dayEvent): return "event::\(dayEvent.id)"
    case .gap(let gap): return gap.id
    case .freeDay(let day): return "free-day::\(day.timeIntervalSinceReferenceDate)"
    case .freeDayHero(let day): return "free-day-hero::\(day.timeIntervalSinceReferenceDate)"
    case .nowLine: return "now-line"
    }
  }
}

/// The presentation decisions shared by the rail and its condensed pinned
/// strip. `heroEvent` is always the event selected for the menubar countdown;
/// a free-day message is an in-timeline fallback only when that selection has
/// no timed event to render.
struct TimelinePresentation: Equatable {
  var heroEvent: CalendarEvent?
  var nowEmphasisEvent: CalendarEvent?
  var nextEvent: CalendarEvent?
  var freeDayNextEvent: CalendarEvent?
  var showsFreeDayHero: Bool
}

struct MeetingNoteResult: Hashable {
  var webViewLink: String
  /// When set, the notes folder was (re)resolved to an app-managed folder — the
  /// stored one was missing or inaccessible. Callers persist this into config.
  var resolvedFolder: DriveFolderRef?
  /// When set, the configured template couldn't be copied and the built-in
  /// template was used for this note; surfaced to the user as a per-event note.
  var templateError: String?
  /// Attendee addresses for which the post-creation Drive writer grant failed.
  /// Note creation itself still succeeds, so callers surface this separately.
  var failedShareEmails: [String] = []
}

/// Result of creating an app-managed template Google Doc under `drive.file`.
struct TemplateDocResult: Hashable {
  var id: String
  var webViewLink: String
  /// Set when the notes folder had to be (re)created while resolving where to
  /// put the template; callers persist it into config.
  var resolvedFolder: DriveFolderRef?
}

struct DriveFolderRef: Identifiable, Codable, Hashable {
  var id: String
  var name: String
}

struct ExternalSharePrompt: Identifiable, Hashable {
  var event: CalendarEvent
  var externalAttendees: [String]

  var id: String { event.actionKey }
}

struct CalendarSummary: Identifiable, Hashable {
  var id: String
  var googleId: String
  var name: String
  var primary: Bool
  var backgroundColor: String
  var selected: Bool
  var accountEmail: String
  var source: EventSource = .google
  /// The macOS account a Mac calendar belongs to ("iCloud", an email, …).
  var sourceTitle: String = ""
  /// A Mac calendar whose account is also connected directly to Google, so
  /// its events would otherwise appear twice. Off by default.
  var duplicatesGoogleAccount: Bool = false
}

struct AccountState: Identifiable, Hashable {
  var id: String { email }
  var email: String
}

struct AuthState: Hashable {
  var authenticated: Bool
  var accounts: [AccountState]
}

struct AppState: Hashable {
  var auth = AuthState(authenticated: false, accounts: [])
  var events: [CalendarEvent] = []
  var allDayEvents: [CalendarEvent] = []
  var next: CalendarEvent?
  var lastSync: Date?
  var lastError: String?
  /// The `timeMax` of the latest complete calendar snapshot. `nil` means the
  /// app cannot claim that the fetched events cover any particular horizon.
  var calendarCoverageEnd: Date?
}

enum NotificationAuthorizationState: Hashable {
  case unavailable
  case notDetermined
  case denied
  case authorized
  case provisional
  case unknown

  var label: String {
    switch self {
    case .unavailable: return loc("Unavailable")
    case .notDetermined: return loc("Not Determined")
    case .denied: return loc("Denied")
    case .authorized: return loc("Authorized")
    case .provisional: return loc("Provisional")
    case .unknown: return loc("Unknown")
    }
  }
}

struct FilterPreviewResult: Hashable {
  var matched: Int
  var total: Int
  var sample: [FilterPreviewSample]
}

struct FilterPreviewSample: Identifiable, Hashable {
  var id: String
  var title: String
  var startDate: Date
  var passed: Bool
}

enum RuleValue: Codable, Hashable {
  case null
  case string(String)
  case number(Double)
  case bool(Bool)
  case strings([String])
  case numbers([Double])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String].self) {
      self = .strings(value)
    } else if let value = try? container.decode([Double].self) {
      self = .numbers(value)
    } else {
      self = .null
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .string(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .strings(let value):
      try container.encode(value)
    case .numbers(let value):
      try container.encode(value)
    }
  }

  var string: String {
    if case .string(let value) = self { return value }
    return ""
  }

  var number: Double {
    switch self {
    case .number(let value): return value
    case .string(let value): return Double(value) ?? 0
    default: return 0
    }
  }

  var stringArray: [String] {
    switch self {
    case .strings(let value): return value
    case .string(let value): return [value]
    case .numbers(let value): return value.map { String(formatNumber($0)) }
    case .number(let value): return [String(formatNumber(value))]
    default: return []
    }
  }

  var numberArray: [Double] {
    switch self {
    case .numbers(let value): return value
    case .number(let value): return [value]
    case .strings(let value): return value.compactMap(Double.init)
    case .string(let value): return Double(value).map { [$0] } ?? []
    default: return []
    }
  }
}

private func formatNumber(_ value: Double) -> String {
  value.rounded() == value ? String(Int(value)) : String(value)
}

struct Rule: Identifiable, Codable, Hashable {
  enum Kind: String, Codable { case group, cond }
  enum GroupOp: String, Codable, CaseIterable {
    case and
    case any = "or"
  }

  var id = UUID()
  var kind: Kind
  var groupOperator: GroupOp?
  var negate: Bool?
  var children: [Rule]?
  var field: String?
  var operatorId: String?
  var value: RuleValue?

  enum CodingKeys: String, CodingKey {
    case id, kind, groupOperator = "op", negate, children, field, value
    case operatorId = "operator"
  }

  init(
    id: UUID = UUID(),
    kind: Kind,
    groupOperator: GroupOp? = nil,
    negate: Bool? = nil,
    children: [Rule]? = nil,
    field: String? = nil,
    operatorId: String? = nil,
    value: RuleValue? = nil
  ) {
    self.id = id
    self.kind = kind
    self.groupOperator = groupOperator
    self.negate = negate
    self.children = children
    self.field = field
    self.operatorId = operatorId
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    kind = try container.decode(Kind.self, forKey: .kind)
    groupOperator = try container.decodeIfPresent(GroupOp.self, forKey: .groupOperator)
    negate = try container.decodeIfPresent(Bool.self, forKey: .negate)
    children = try container.decodeIfPresent([Rule].self, forKey: .children)
    field = try container.decodeIfPresent(String.self, forKey: .field)
    operatorId = try container.decodeIfPresent(String.self, forKey: .operatorId)
    value = try container.decodeIfPresent(RuleValue.self, forKey: .value)
  }

  static func group(_ groupOperator: GroupOp, _ children: [Rule], negate: Bool = false) -> Rule {
    Rule(
      kind: .group,
      groupOperator: groupOperator,
      negate: negate,
      children: children,
      field: nil,
      operatorId: nil,
      value: nil
    )
  }

  static func condition(
    _ field: String,
    _ operatorId: String,
    _ value: RuleValue = .null,
    negate: Bool = false
  ) -> Rule {
    Rule(
      kind: .cond,
      groupOperator: nil,
      negate: negate,
      children: nil,
      field: field,
      operatorId: operatorId,
      value: value
    )
  }
}

struct AppConfig: Codable, Hashable {
  var oauthClientId: String
  var oauthClientSecret: String
  var filterRules: Rule
  var selectedCalendarIds: [String]
  var lookaheadHours: Int
  var pollIntervalSeconds: Int
  var maxTitleLength: Int
  var menubarLeadMinutes: Int
  var menubarShowsNextAlways: Bool
  var menubarPrefersImminentNext: Bool
  var notifyEnabled: Bool
  var notifyVideoOnly: Bool
  var notifyLeadMinutes: Int
  var hotkeyEnabled: Bool
  var hotkeyPreset: String
  var meetingNotesFoldersByAccount: [String: DriveFolderRef]
  var meetingNotesFolderNamesByAccount: [String: String]
  var meetingNotesTitleTemplatesByAccount: [String: String]
  var meetingNotesTemplateDocsByAccount: [String: String]
  /// Set once the launch-at-login default has been applied so it never
  /// overrides the user's later choice. Absent in legacy configs (decodes false).
  var didApplyDefaultLaunchAtLogin: Bool
  /// Events hidden from the menubar countdown only (popover list, filters, and
  /// notifications are unaffected), keyed by `CalendarEvent.actionKey`. The
  /// value is the event's `endDate`, kept only so expired entries can be
  /// purged automatically instead of accumulating forever.
  var skippedMenubarEvents: [String: Date]
  /// Read events from the Calendar app through EventKit (iCloud, Exchange,
  /// Google, CalDAV — whatever macOS already syncs). No sign-in needed.
  var macCalendarsEnabled: Bool
  /// Explicit on/off choices for Mac calendars, keyed by `CalendarSummary.id`.
  /// Calendars without a choice follow the default (on, unless the account is
  /// also connected directly through Google).
  var macCalendarSelections: [String: Bool]
  /// A second global shortcut that joins the current or next meeting.
  var joinHotkeyEnabled: Bool
  var joinHotkeyPreset: String
  /// Open Zoom and Teams links in their desktop apps when installed.
  var openMeetingsInApps: Bool
  /// "off", "floating", or "fullScreen": an on-screen alert as a meeting starts.
  var startAlertStyle: String
  var startAlertLeadMinutes: Int
  var startAlertVideoOnly: Bool
  /// Show the event title next to the countdown. Off keeps only the time,
  /// which is handy while presenting.
  var menubarShowsTitle: Bool

  // Google OAuth client credentials, injected at build/package time rather than
  // committed to source. Packaged builds read them from Info.plist (written by
  // scripts/package-app.sh from the GOOGLE_OAUTH_CLIENT_ID / GOOGLE_OAUTH_CLIENT_SECRET
  // env vars); the bare `swift run` dev path falls back to the process environment.
  // For installed/desktop apps Google does not treat the secret as confidential
  // (it ships in the client), but its token endpoint still requires it with PKCE.
  static let bundledGoogleClientId = buildSecret(
    plistKey: "GoogleOAuthClientID", envKey: "GOOGLE_OAUTH_CLIENT_ID")
  static let bundledGoogleClientSecret = buildSecret(
    plistKey: "GoogleOAuthClientSecret", envKey: "GOOGLE_OAUTH_CLIENT_SECRET")

  private static func buildSecret(plistKey: String, envKey: String) -> String {
    if let value = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return ProcessInfo.processInfo.environment[envKey]?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  /// Build-time credentials win over persisted values so rotating .env takes
  /// effect without clearing config.
  private static func decodedCredentials(
    from container: KeyedDecodingContainer<CodingKeys>,
    defaults: AppConfig
  ) throws -> (clientId: String, clientSecret: String) {
    let oauth = try container.nestedContainer(keyedBy: OAuthKeys.self, forKey: .oauth)
    let storedClientId = try oauth.decodeIfPresent(String.self, forKey: .clientId)
    let storedClientSecret = try oauth.decodeIfPresent(String.self, forKey: .clientSecret)
    return (
      resolvedCredential(buildTime: defaults.oauthClientId, stored: storedClientId),
      resolvedCredential(buildTime: defaults.oauthClientSecret, stored: storedClientSecret)
    )
  }

  private static func resolvedCredential(buildTime: String, stored: String?) -> String {
    if !buildTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return buildTime }
    let stored = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return stored.isEmpty ? buildTime : stored
  }

  /// Default note title pattern. Supports `{date}` and `{title}` tokens.
  static let defaultNoteTitleTemplate = "Meeting notes - {date} - {title}"

  /// The menu-picker presets for `menubarLeadMinutes` (see `SettingsView`'s
  /// "Show upcoming event" picker). Kept here so both the config-loading path
  /// (`init(from:)`) and `AppModel.normalized()` snap legacy/arbitrary values
  /// onto the same set.
  static let menubarLeadPresetsMinutes = [60, 180, 360, 720, 1440]

  /// Snaps an arbitrary minute value to the nearest entry in
  /// `menubarLeadPresetsMinutes`; ties prefer the larger preset.
  static func snappedMenubarLead(_ minutes: Int) -> Int {
    menubarLeadPresetsMinutes.reduce(menubarLeadPresetsMinutes[0]) { best, preset in
      let bestDiff = abs(minutes - best)
      let presetDiff = abs(minutes - preset)
      if presetDiff < bestDiff || (presetDiff == bestDiff && preset > best) {
        return preset
      }
      return best
    }
  }

  static let `default` = AppConfig(
    oauthClientId: bundledGoogleClientId,
    oauthClientSecret: bundledGoogleClientSecret,
    filterRules: defaultFilterRules,
    selectedCalendarIds: [],
    lookaheadHours: 24,
    pollIntervalSeconds: 120,
    maxTitleLength: 40,
    menubarLeadMinutes: 720,
    menubarShowsNextAlways: true,
    menubarPrefersImminentNext: true,
    notifyEnabled: true,
    notifyVideoOnly: false,
    notifyLeadMinutes: 5,
    hotkeyEnabled: false,
    hotkeyPreset: "ctrl-opt-u",
    meetingNotesFoldersByAccount: [:],
    meetingNotesFolderNamesByAccount: [:],
    meetingNotesTitleTemplatesByAccount: [:],
    meetingNotesTemplateDocsByAccount: [:],
    didApplyDefaultLaunchAtLogin: false,
    skippedMenubarEvents: [:],
    macCalendarsEnabled: false,
    macCalendarSelections: [:],
    joinHotkeyEnabled: false,
    joinHotkeyPreset: "ctrl-opt-j",
    openMeetingsInApps: false,
    startAlertStyle: StartAlertStyle.off.rawValue,
    startAlertLeadMinutes: 1,
    startAlertVideoOnly: true,
    menubarShowsTitle: true
  )

  enum CodingKeys: String, CodingKey {
    case oauth, filterRules, selectedCalendarIds
    case lookaheadHours, pollIntervalSeconds, maxTitleLength, menubarLeadMinutes
    case menubarShowsNextAlways
    case menubarPrefersImminentNext
    case notifyEnabled, notifyVideoOnly, notifyLeadMinutes
    case hotkeyEnabled, hotkeyPreset
    case meetingNotesFoldersByAccount
    case meetingNotesFolderNamesByAccount
    case meetingNotesTitleTemplatesByAccount
    case meetingNotesTemplateDocsByAccount
    case didApplyDefaultLaunchAtLogin
    case skippedMenubarEvents
    case macCalendarsEnabled, macCalendarSelections
    case joinHotkeyEnabled, joinHotkeyPreset
    case openMeetingsInApps
    case startAlertStyle, startAlertLeadMinutes, startAlertVideoOnly
    case menubarShowsTitle
  }

  enum OAuthKeys: String, CodingKey {
    case clientId, clientSecret
  }

  init(
    oauthClientId: String,
    oauthClientSecret: String,
    filterRules: Rule,
    selectedCalendarIds: [String],
    lookaheadHours: Int,
    pollIntervalSeconds: Int,
    maxTitleLength: Int,
    menubarLeadMinutes: Int,
    menubarShowsNextAlways: Bool = true,
    menubarPrefersImminentNext: Bool = true,
    notifyEnabled: Bool,
    notifyVideoOnly: Bool,
    notifyLeadMinutes: Int,
    hotkeyEnabled: Bool = false,
    hotkeyPreset: String = "ctrl-opt-u",
    meetingNotesFoldersByAccount: [String: DriveFolderRef],
    meetingNotesFolderNamesByAccount: [String: String] = [:],
    meetingNotesTitleTemplatesByAccount: [String: String],
    meetingNotesTemplateDocsByAccount: [String: String],
    didApplyDefaultLaunchAtLogin: Bool = false,
    skippedMenubarEvents: [String: Date] = [:],
    macCalendarsEnabled: Bool = false,
    macCalendarSelections: [String: Bool] = [:],
    joinHotkeyEnabled: Bool = false,
    joinHotkeyPreset: String = "ctrl-opt-j",
    openMeetingsInApps: Bool = false,
    startAlertStyle: String = StartAlertStyle.off.rawValue,
    startAlertLeadMinutes: Int = 1,
    startAlertVideoOnly: Bool = true,
    menubarShowsTitle: Bool = true
  ) {
    self.oauthClientId = oauthClientId
    self.oauthClientSecret = oauthClientSecret
    self.filterRules = filterRules
    self.selectedCalendarIds = selectedCalendarIds
    self.lookaheadHours = lookaheadHours
    self.pollIntervalSeconds = pollIntervalSeconds
    self.maxTitleLength = maxTitleLength
    self.menubarLeadMinutes = menubarLeadMinutes
    self.menubarShowsNextAlways = menubarShowsNextAlways
    self.menubarPrefersImminentNext = menubarPrefersImminentNext
    self.notifyEnabled = notifyEnabled
    self.notifyVideoOnly = notifyVideoOnly
    self.notifyLeadMinutes = notifyLeadMinutes
    self.hotkeyEnabled = hotkeyEnabled
    self.hotkeyPreset = hotkeyPreset
    self.meetingNotesFoldersByAccount = meetingNotesFoldersByAccount
    self.meetingNotesFolderNamesByAccount = meetingNotesFolderNamesByAccount
    self.meetingNotesTitleTemplatesByAccount = meetingNotesTitleTemplatesByAccount
    self.meetingNotesTemplateDocsByAccount = meetingNotesTemplateDocsByAccount
    self.didApplyDefaultLaunchAtLogin = didApplyDefaultLaunchAtLogin
    self.skippedMenubarEvents = skippedMenubarEvents
    self.macCalendarsEnabled = macCalendarsEnabled
    self.macCalendarSelections = macCalendarSelections
    self.joinHotkeyEnabled = joinHotkeyEnabled
    self.joinHotkeyPreset = joinHotkeyPreset
    self.openMeetingsInApps = openMeetingsInApps
    self.startAlertStyle = startAlertStyle
    self.startAlertLeadMinutes = startAlertLeadMinutes
    self.startAlertVideoOnly = startAlertVideoOnly
    self.menubarShowsTitle = menubarShowsTitle
  }

  init(from decoder: Decoder) throws {
    let defaults = AppConfig.default
    let container = try decoder.container(keyedBy: CodingKeys.self)
    (oauthClientId, oauthClientSecret) = try Self.decodedCredentials(from: container, defaults: defaults)
    filterRules = try container.decode(.filterRules, or: \.filterRules)
    selectedCalendarIds = try container.decode(.selectedCalendarIds, or: \.selectedCalendarIds)
    lookaheadHours = try container.decode(.lookaheadHours, or: \.lookaheadHours)
    pollIntervalSeconds = try container.decode(.pollIntervalSeconds, or: \.pollIntervalSeconds)
    maxTitleLength = try container.decode(.maxTitleLength, or: \.maxTitleLength)
    menubarLeadMinutes = AppConfig.snappedMenubarLead(
      try container.decode(.menubarLeadMinutes, or: \.menubarLeadMinutes)
    )
    menubarShowsNextAlways = try container.decode(.menubarShowsNextAlways, or: \.menubarShowsNextAlways)
    menubarPrefersImminentNext = try container.decode(.menubarPrefersImminentNext, or: \.menubarPrefersImminentNext)
    notifyEnabled = try container.decode(.notifyEnabled, or: \.notifyEnabled)
    notifyVideoOnly = try container.decode(.notifyVideoOnly, or: \.notifyVideoOnly)
    notifyLeadMinutes = try container.decode(.notifyLeadMinutes, or: \.notifyLeadMinutes)
    hotkeyEnabled = try container.decode(.hotkeyEnabled, or: \.hotkeyEnabled)
    hotkeyPreset = try container.decode(.hotkeyPreset, or: \.hotkeyPreset)
    meetingNotesFoldersByAccount = try container.decode(
      .meetingNotesFoldersByAccount,
      or: \.meetingNotesFoldersByAccount
    )
    meetingNotesFolderNamesByAccount = try container.decode(
      .meetingNotesFolderNamesByAccount,
      or: \.meetingNotesFolderNamesByAccount
    )
    meetingNotesTitleTemplatesByAccount = try container.decode(
      .meetingNotesTitleTemplatesByAccount,
      or: \.meetingNotesTitleTemplatesByAccount
    )
    meetingNotesTemplateDocsByAccount = try container.decode(
      .meetingNotesTemplateDocsByAccount,
      or: \.meetingNotesTemplateDocsByAccount
    )
    didApplyDefaultLaunchAtLogin = try container.decode(
      .didApplyDefaultLaunchAtLogin,
      or: \.didApplyDefaultLaunchAtLogin
    )
    skippedMenubarEvents = try container.decode(.skippedMenubarEvents, or: \.skippedMenubarEvents)
    macCalendarsEnabled = try container.decode(.macCalendarsEnabled, or: \.macCalendarsEnabled)
    macCalendarSelections = try container.decode(.macCalendarSelections, or: \.macCalendarSelections)
    joinHotkeyEnabled = try container.decode(.joinHotkeyEnabled, or: \.joinHotkeyEnabled)
    joinHotkeyPreset = try container.decode(.joinHotkeyPreset, or: \.joinHotkeyPreset)
    openMeetingsInApps = try container.decode(.openMeetingsInApps, or: \.openMeetingsInApps)
    startAlertStyle = try container.decode(.startAlertStyle, or: \.startAlertStyle)
    startAlertLeadMinutes = try container.decode(.startAlertLeadMinutes, or: \.startAlertLeadMinutes)
    startAlertVideoOnly = try container.decode(.startAlertVideoOnly, or: \.startAlertVideoOnly)
    menubarShowsTitle = try container.decode(.menubarShowsTitle, or: \.menubarShowsTitle)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    var oauth = container.nestedContainer(keyedBy: OAuthKeys.self, forKey: .oauth)
    try oauth.encode(oauthClientId, forKey: .clientId)
    // The OAuth client secret is no longer persisted in config.json; it lives in
    // the Keychain (see KeychainStore / ConfigStore). Encoding it here would
    // re-leak it into plaintext on the next save, so we deliberately omit it.
    try container.encode(filterRules, forKey: .filterRules)
    try container.encode(selectedCalendarIds, forKey: .selectedCalendarIds)
    try container.encode(lookaheadHours, forKey: .lookaheadHours)
    try container.encode(pollIntervalSeconds, forKey: .pollIntervalSeconds)
    try container.encode(maxTitleLength, forKey: .maxTitleLength)
    try container.encode(menubarLeadMinutes, forKey: .menubarLeadMinutes)
    try container.encode(menubarShowsNextAlways, forKey: .menubarShowsNextAlways)
    try container.encode(menubarPrefersImminentNext, forKey: .menubarPrefersImminentNext)
    try container.encode(notifyEnabled, forKey: .notifyEnabled)
    try container.encode(notifyVideoOnly, forKey: .notifyVideoOnly)
    try container.encode(notifyLeadMinutes, forKey: .notifyLeadMinutes)
    try container.encode(hotkeyEnabled, forKey: .hotkeyEnabled)
    try container.encode(hotkeyPreset, forKey: .hotkeyPreset)
    try container.encode(meetingNotesFoldersByAccount, forKey: .meetingNotesFoldersByAccount)
    try container.encode(meetingNotesFolderNamesByAccount, forKey: .meetingNotesFolderNamesByAccount)
    try container.encode(meetingNotesTitleTemplatesByAccount, forKey: .meetingNotesTitleTemplatesByAccount)
    try container.encode(meetingNotesTemplateDocsByAccount, forKey: .meetingNotesTemplateDocsByAccount)
    try container.encode(didApplyDefaultLaunchAtLogin, forKey: .didApplyDefaultLaunchAtLogin)
    try container.encode(skippedMenubarEvents, forKey: .skippedMenubarEvents)
    try container.encode(macCalendarsEnabled, forKey: .macCalendarsEnabled)
    try container.encode(macCalendarSelections, forKey: .macCalendarSelections)
    try container.encode(joinHotkeyEnabled, forKey: .joinHotkeyEnabled)
    try container.encode(joinHotkeyPreset, forKey: .joinHotkeyPreset)
    try container.encode(openMeetingsInApps, forKey: .openMeetingsInApps)
    try container.encode(startAlertStyle, forKey: .startAlertStyle)
    try container.encode(startAlertLeadMinutes, forKey: .startAlertLeadMinutes)
    try container.encode(startAlertVideoOnly, forKey: .startAlertVideoOnly)
    try container.encode(menubarShowsTitle, forKey: .menubarShowsTitle)
  }
}

/// How a meeting announces itself on screen as it starts.
enum StartAlertStyle: String, CaseIterable, Identifiable {
  case off
  case floating
  case fullScreen

  var id: String { rawValue }

  var label: String {
    switch self {
    case .off: return loc("Off")
    case .floating: return loc("Floating")
    case .fullScreen: return loc("Full screen")
    }
  }
}

private extension KeyedDecodingContainer where Key == AppConfig.CodingKeys {
  /// Missing keys (older config files) fall back to the default config.
  func decode<T: Decodable>(_ key: Key, or defaultValue: KeyPath<AppConfig, T>) throws -> T {
    try decodeIfPresent(T.self, forKey: key) ?? AppConfig.default[keyPath: defaultValue]
  }
}

private let defaultFilterRules = Rule.group(.and, [
  .condition("selfResponse", "is_not", .string("declined")),
  .condition("status", "is_not", .string("cancelled"))
])

extension ISO8601DateFormatter {
  static let shared: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  static let fallback: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  func date(fromAnyInternetDate string: String) -> Date? {
    date(from: string) ?? ISO8601DateFormatter.fallback.date(from: string)
  }
}
