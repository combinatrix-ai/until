import Foundation

struct Attendee: Codable, Hashable {
  var email: String
  var name: String
  var responseStatus: String
  var selfUser: Bool
  var organizer: Bool
  var optional: Bool
  var resource: Bool
}

struct CalendarRef: Codable, Hashable {
  var id: String
  var googleId: String
  var name: String
  var primary: Bool
  var backgroundColor: String
}

struct AccountRef: Codable, Hashable {
  var email: String
}

struct CalendarEvent: Identifiable, Codable, Hashable {
  var id: String
  var title: String
  var description: String
  var location: String
  var startISO: String
  var endISO: String
  var allDay: Bool
  var status: String
  var startMinutesFromNow: Int
  var durationMinutes: Int
  var calendar: CalendarRef
  var account: AccountRef
  var attendees: [Attendee]
  var attendeeCount: Int
  var organizer: String
  var creator: String
  var selfResponse: String
  var isRecurring: Bool
  var hangoutLink: String
  var conferenceUrl: String
  var notesUrl: String
  var notesFileId: String
  var visibility: String
  var colorId: String
  var transparency: String
  var htmlLink: String

  // Parsed once at construction from `startISO`/`endISO`. These were previously
  // computed properties that reparsed the ISO strings on every access; they are
  // read O(n log n) times per UI tick (sort comparators, filters, day grouping),
  // so caching avoids repeated `ISO8601DateFormatter` work.
  var startDate: Date
  var endDate: Date

  var actionKey: String { "\(account.email)::\(calendar.googleId)::\(id)" }

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
    attendeeCount: Int,
    organizer: String,
    creator: String,
    selfResponse: String,
    isRecurring: Bool,
    hangoutLink: String,
    conferenceUrl: String,
    notesUrl: String,
    notesFileId: String,
    visibility: String,
    colorId: String,
    transparency: String,
    htmlLink: String
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
    self.endISO = endISO
    self.allDay = allDay
    self.status = status
    self.startMinutesFromNow = startMinutesFromNow
    self.durationMinutes = durationMinutes
    self.calendar = calendar
    self.account = account
    self.attendees = attendees
    self.attendeeCount = attendeeCount
    self.organizer = organizer
    self.creator = creator
    self.selfResponse = selfResponse
    self.isRecurring = isRecurring
    self.hangoutLink = hangoutLink
    self.conferenceUrl = conferenceUrl
    self.notesUrl = notesUrl
    self.notesFileId = notesFileId
    self.visibility = visibility
    self.colorId = colorId
    self.transparency = transparency
    self.htmlLink = htmlLink
    self.startDate = start
    self.endDate = end
  }

  enum CodingKeys: String, CodingKey {
    case id, title, description, location, startISO, endISO, allDay, status
    case startMinutesFromNow, durationMinutes, calendar, account, attendees
    case attendeeCount, organizer, creator, selfResponse, isRecurring
    case hangoutLink, conferenceUrl, notesUrl, notesFileId, visibility
    case colorId, transparency, htmlLink
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    description = try container.decode(String.self, forKey: .description)
    location = try container.decode(String.self, forKey: .location)
    startISO = try container.decode(String.self, forKey: .startISO)
    endISO = try container.decode(String.self, forKey: .endISO)
    allDay = try container.decode(Bool.self, forKey: .allDay)
    status = try container.decode(String.self, forKey: .status)
    startMinutesFromNow = try container.decode(Int.self, forKey: .startMinutesFromNow)
    durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
    calendar = try container.decode(CalendarRef.self, forKey: .calendar)
    account = try container.decode(AccountRef.self, forKey: .account)
    attendees = try container.decode([Attendee].self, forKey: .attendees)
    attendeeCount = try container.decode(Int.self, forKey: .attendeeCount)
    organizer = try container.decode(String.self, forKey: .organizer)
    creator = try container.decode(String.self, forKey: .creator)
    selfResponse = try container.decode(String.self, forKey: .selfResponse)
    isRecurring = try container.decode(Bool.self, forKey: .isRecurring)
    hangoutLink = try container.decode(String.self, forKey: .hangoutLink)
    conferenceUrl = try container.decode(String.self, forKey: .conferenceUrl)
    notesUrl = try container.decode(String.self, forKey: .notesUrl)
    notesFileId = try container.decode(String.self, forKey: .notesFileId)
    visibility = try container.decode(String.self, forKey: .visibility)
    colorId = try container.decode(String.self, forKey: .colorId)
    transparency = try container.decode(String.self, forKey: .transparency)
    htmlLink = try container.decode(String.self, forKey: .htmlLink)
    // Parse once on decode; fall back to `.distantPast` so a corrupt persisted
    // value never renders as "happening now".
    startDate = ISO8601DateFormatter.shared.date(fromAnyInternetDate: startISO) ?? .distantPast
    endDate = ISO8601DateFormatter.shared.date(fromAnyInternetDate: endISO) ?? .distantPast
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(description, forKey: .description)
    try container.encode(location, forKey: .location)
    try container.encode(startISO, forKey: .startISO)
    try container.encode(endISO, forKey: .endISO)
    try container.encode(allDay, forKey: .allDay)
    try container.encode(status, forKey: .status)
    try container.encode(startMinutesFromNow, forKey: .startMinutesFromNow)
    try container.encode(durationMinutes, forKey: .durationMinutes)
    try container.encode(calendar, forKey: .calendar)
    try container.encode(account, forKey: .account)
    try container.encode(attendees, forKey: .attendees)
    try container.encode(attendeeCount, forKey: .attendeeCount)
    try container.encode(organizer, forKey: .organizer)
    try container.encode(creator, forKey: .creator)
    try container.encode(selfResponse, forKey: .selfResponse)
    try container.encode(isRecurring, forKey: .isRecurring)
    try container.encode(hangoutLink, forKey: .hangoutLink)
    try container.encode(conferenceUrl, forKey: .conferenceUrl)
    try container.encode(notesUrl, forKey: .notesUrl)
    try container.encode(notesFileId, forKey: .notesFileId)
    try container.encode(visibility, forKey: .visibility)
    try container.encode(colorId, forKey: .colorId)
    try container.encode(transparency, forKey: .transparency)
    try container.encode(htmlLink, forKey: .htmlLink)
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

struct MeetingNoteResult: Codable, Hashable {
  var fileId: String
  var fileName: String
  var webViewLink: String
  var folderId: String
  var sharedWith: [String]
  var skippedExternal: [String]
  var reused: Bool
  /// When set, the notes folder was (re)resolved to an app-managed folder — the
  /// stored one was missing or inaccessible. Callers persist this into config.
  var resolvedFolder: DriveFolderRef?
  /// When set, the configured template couldn't be copied and the built-in
  /// template was used for this note; surfaced to the user as a per-event note.
  var templateError: String?
}

/// Result of creating an app-managed template Google Doc under `drive.file`.
struct TemplateDocResult: Hashable {
  var id: String
  var webViewLink: String
  /// Set when the notes folder had to be (re)created while resolving where to
  /// put the template; callers persist it into config.
  var resolvedFolder: DriveFolderRef?
}

enum DriveFolderSource: String, Codable, Hashable {
  case myDrive
  case sharedDrive
  case sharedWithMe
}

struct DriveFolderRef: Identifiable, Codable, Hashable {
  var id: String
  var name: String
  var source: DriveFolderSource
  var driveId: String?
  var path: [String]

  var displayPath: String {
    path.isEmpty ? name : path.joined(separator: " / ")
  }
}

struct ExternalSharePrompt: Identifiable, Hashable {
  var event: CalendarEvent
  var externalAttendees: [String]

  var id: String { event.actionKey }
}

struct CalendarSummary: Identifiable, Codable, Hashable {
  var id: String
  var googleId: String
  var name: String
  var primary: Bool
  var backgroundColor: String
  var selected: Bool
  var accountEmail: String
}

struct AccountState: Identifiable, Hashable {
  var id: String { email }
  var email: String
  var authenticated: Bool
}

struct AuthState: Hashable {
  var authenticated: Bool
  var email: String
  var accounts: [AccountState]
}

struct AppState: Hashable {
  var auth = AuthState(authenticated: false, email: "", accounts: [])
  var events: [CalendarEvent] = []
  var allDayEvents: [CalendarEvent] = []
  var next: CalendarEvent?
  var lastSync: Date?
  var lastError: String?
  var filterError: String?
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
    didApplyDefaultLaunchAtLogin: false
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
    didApplyDefaultLaunchAtLogin: Bool = false
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
  }

  init(from decoder: Decoder) throws {
    let defaults = AppConfig.default
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let oauth = try container.nestedContainer(keyedBy: OAuthKeys.self, forKey: .oauth)
    let storedClientId = try oauth.decodeIfPresent(String.self, forKey: .clientId)
    let storedClientSecret = try oauth.decodeIfPresent(String.self, forKey: .clientSecret)
    // Build-time credentials (from Info.plist / env) are the source of truth and
    // win over any value persisted in config.json, so rotating .env takes effect
    // without clearing config. Fall back to a stored value only when the build
    // injected none.
    func resolve(buildTime: String, stored: String?) -> String {
      if !buildTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return buildTime }
      let stored = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return stored.isEmpty ? buildTime : stored
    }
    oauthClientId = resolve(buildTime: defaults.oauthClientId, stored: storedClientId)
    oauthClientSecret = resolve(buildTime: defaults.oauthClientSecret, stored: storedClientSecret)
    filterRules = try container.decode(.filterRules, default: defaults.filterRules)
    selectedCalendarIds = try container.decode(.selectedCalendarIds, default: defaults.selectedCalendarIds)
    lookaheadHours = try container.decode(.lookaheadHours, default: defaults.lookaheadHours)
    pollIntervalSeconds = try container.decode(.pollIntervalSeconds, default: defaults.pollIntervalSeconds)
    maxTitleLength = try container.decode(.maxTitleLength, default: defaults.maxTitleLength)
    menubarLeadMinutes = AppConfig.snappedMenubarLead(
      try container.decode(.menubarLeadMinutes, default: defaults.menubarLeadMinutes)
    )
    menubarShowsNextAlways = try container.decode(.menubarShowsNextAlways, default: defaults.menubarShowsNextAlways)
    menubarPrefersImminentNext = try container.decode(
      .menubarPrefersImminentNext,
      default: defaults.menubarPrefersImminentNext
    )
    notifyEnabled = try container.decode(.notifyEnabled, default: defaults.notifyEnabled)
    notifyVideoOnly = try container.decode(.notifyVideoOnly, default: defaults.notifyVideoOnly)
    notifyLeadMinutes = try container.decode(.notifyLeadMinutes, default: defaults.notifyLeadMinutes)
    hotkeyEnabled = try container.decode(.hotkeyEnabled, default: defaults.hotkeyEnabled)
    hotkeyPreset = try container.decode(.hotkeyPreset, default: defaults.hotkeyPreset)
    meetingNotesFoldersByAccount = try container.decode(
      .meetingNotesFoldersByAccount,
      default: defaults.meetingNotesFoldersByAccount
    )
    meetingNotesFolderNamesByAccount = try container.decode(
      .meetingNotesFolderNamesByAccount,
      default: defaults.meetingNotesFolderNamesByAccount
    )
    meetingNotesTitleTemplatesByAccount = try container.decode(
      .meetingNotesTitleTemplatesByAccount,
      default: defaults.meetingNotesTitleTemplatesByAccount
    )
    meetingNotesTemplateDocsByAccount = try container.decode(
      .meetingNotesTemplateDocsByAccount,
      default: defaults.meetingNotesTemplateDocsByAccount
    )
    didApplyDefaultLaunchAtLogin = try container.decode(
      .didApplyDefaultLaunchAtLogin,
      default: defaults.didApplyDefaultLaunchAtLogin
    )
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
  }
}

private extension KeyedDecodingContainer where Key == AppConfig.CodingKeys {
  func decode<T: Decodable>(_ key: Key, default defaultValue: T) throws -> T {
    try decodeIfPresent(T.self, forKey: key) ?? defaultValue
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
