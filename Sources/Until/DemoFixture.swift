import Foundation

/// A hand-authored demo day loaded from JSON (`--demo-json <path>`).
///
/// The built-in scenarios in `DemoCalendarData` anchor everything to `now`, so
/// a plain `--demo-mode` run looks sensible at any hour — but that is exactly
/// what makes some captures awkward: a state has to be *waited* for, the
/// half-hour rule decides which countdown you can film, and a shot taken on a
/// Sunday evening tells a morning story with evening timestamps.
///
/// A fixture inverts that. Times are wall-clock (`"09:30"`), so the machine's
/// clock decides the moment: pin it and the state is simply there, with no
/// waiting and no drift from the poll re-anchor. Days are expressed as offsets
/// from today rather than calendar dates, so a fixture keeps working tomorrow.
struct DemoFixture: Decodable {
  var config: ConfigOverrides?
  var calendars: [Calendar]
  var events: [Event]

  struct ConfigOverrides: Decodable {
    var menubarLeadMinutes: Int?
    var lookaheadHours: Int?
    var maxTitleLength: Int?
    var notifyEnabled: Bool?
    var notifyVideoOnly: Bool?
    var notifyLeadMinutes: Int?
  }

  struct Calendar: Decodable {
    var id: String
    var account: String
    var name: String
    var color: String
    /// Google's own id for the calendar. Defaults to `id`; only worth setting
    /// when a fixture wants to exercise the id-vs-googleId distinction that
    /// `RuleEngine.compareCalendar` matches on.
    var googleId: String?
    var primary: Bool?
    /// Whether the calendar starts selected. Unselected calendars still appear
    /// in settings, so a fixture can show the picker with a mix of states.
    var selected: Bool?
  }

  /// Named to avoid shadowing the model's `Attendee` inside this file.
  struct Guest: Decodable {
    var email: String
    var name: String?
    var response: String?
    var resource: Bool?
  }

  struct Event: Decodable {
    var id: String
    var title: String
    var calendar: String
    /// `"HH:MM"`, local time. Omitted for all-day events.
    var start: String?
    var end: String?
    /// Day offset from today: 0 today, 1 tomorrow, -1 yesterday.
    var day: Int?
    /// Day offset for `end`, when an event crosses midnight. Defaults to `day`;
    /// an `end` at or before `start` on the same day rolls to the next day.
    var endDay: Int?
    var allDay: Bool?
    /// All-day length in days (default 1), so a fixture can span a holiday.
    var days: Int?
    var description: String?
    var location: String?
    var attendees: [Guest]?
    var selfResponse: String?
    var conferenceUrl: String?
    var notesUrl: String?
    var colorId: String?
    var transparency: String?
    var isRecurring: Bool?
  }
}

// MARK: - Loading

extension DemoFixture {
  enum LoadError: Error, CustomStringConvertible {
    case unreadable(path: String, underlying: Error)
    case malformed(path: String, underlying: Error)
    case unknownCalendar(event: String, calendar: String)
    case badTime(event: String, value: String)
    case missingTime(event: String)

    var description: String {
      switch self {
      case .unreadable(let path, let underlying):
        return "cannot read \(path): \(underlying.localizedDescription)"
      case .malformed(let path, let underlying):
        return "cannot parse \(path): \(underlying)"
      case .unknownCalendar(let event, let calendar):
        return "event \"\(event)\" references unknown calendar \"\(calendar)\""
      case .badTime(let event, let value):
        return "event \"\(event)\" has an unparseable time \"\(value)\" (expected \"HH:MM\")"
      case .missingTime(let event):
        return "event \"\(event)\" is not all-day and needs both \"start\" and \"end\""
      }
    }
  }

  static func load(path: String) throws -> DemoFixture {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw LoadError.unreadable(path: path, underlying: error)
    }
    do {
      return try JSONDecoder().decode(DemoFixture.self, from: data)
    } catch {
      throw LoadError.malformed(path: path, underlying: error)
    }
  }
}

// MARK: - Resolution

extension DemoFixture {
  func appConfig(base: AppConfig) -> AppConfig {
    var next = base
    next.selectedCalendarIds = calendars
      .filter { $0.selected ?? true }
      .map(\.id)
    guard let overrides = config else { return next }
    if let value = overrides.menubarLeadMinutes { next.menubarLeadMinutes = value }
    if let value = overrides.lookaheadHours { next.lookaheadHours = value }
    if let value = overrides.maxTitleLength { next.maxTitleLength = value }
    if let value = overrides.notifyEnabled { next.notifyEnabled = value }
    if let value = overrides.notifyVideoOnly { next.notifyVideoOnly = value }
    if let value = overrides.notifyLeadMinutes { next.notifyLeadMinutes = value }
    return next
  }

  func accountEmails() -> [String] {
    var seen = Set<String>()
    return calendars.map(\.account).filter { seen.insert($0).inserted }
  }

  func calendarSummaries(selectedIds: [String]) -> [CalendarSummary] {
    let selected = Set(selectedIds)
    return calendars.map { calendar in
      CalendarSummary(
        id: calendar.id,
        googleId: calendar.googleId ?? calendar.id,
        name: calendar.name,
        primary: calendar.primary ?? false,
        backgroundColor: calendar.color,
        selected: selected.contains(calendar.id),
        accountEmail: calendar.account
      )
    }
  }

  /// Resolves every event against `now`'s calendar day. Throws rather than
  /// skipping a bad entry: a fixture exists to pin one exact frame, so a typo
  /// must stop the run instead of quietly producing a different picture.
  func calendarEvents(now: Date, selectedIds: [String]) throws -> [CalendarEvent] {
    let calendar = Foundation.Calendar.current
    let today = calendar.startOfDay(for: now)
    let byId = Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0) })
    let selected = Set(selectedIds)

    return try events.compactMap { event -> CalendarEvent? in
      guard let definition = byId[event.calendar] else {
        throw LoadError.unknownCalendar(event: event.id, calendar: event.calendar)
      }
      guard selected.contains(definition.id) else { return nil }

      let dayOffset = event.day ?? 0
      let startOfDay = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
      let isAllDay = event.allDay ?? false
      let start: Date
      let end: Date
      if isAllDay {
        start = startOfDay
        end = calendar.date(byAdding: .day, value: max(1, event.days ?? 1), to: startOfDay) ?? startOfDay
      } else {
        guard let startText = event.start, let endText = event.end else {
          throw LoadError.missingTime(event: event.id)
        }
        start = try Self.date(on: startOfDay, time: startText, event: event.id, calendar: calendar)
        let endDayOffset = event.endDay ?? dayOffset
        let endBase = calendar.date(byAdding: .day, value: endDayOffset, to: today) ?? today
        var resolved = try Self.date(on: endBase, time: endText, event: event.id, calendar: calendar)
        if resolved <= start, event.endDay == nil {
          // Crossing midnight without an explicit endDay.
          resolved = calendar.date(byAdding: .day, value: 1, to: resolved) ?? resolved
        }
        end = resolved
      }

      let ref = CalendarRef(
        id: definition.id,
        googleId: definition.googleId ?? definition.id,
        primary: definition.primary ?? false,
        backgroundColor: definition.color
      )
      let attendees = (event.attendees ?? []).map {
        Attendee(
          email: $0.email,
          name: $0.name ?? $0.email,
          responseStatus: $0.response ?? "accepted",
          selfUser: false,
          resource: $0.resource ?? false
        )
      }
      let withSelf = attendees.isEmpty
        ? []
        : [Attendee(
            email: definition.account,
            name: "You",
            responseStatus: event.selfResponse ?? "accepted",
            selfUser: true,
            resource: false
          )] + attendees

      return CalendarEvent(
        id: event.id,
        title: event.title,
        description: event.description ?? "",
        location: event.location ?? "",
        startISO: ISO8601DateFormatter.fallback.string(from: start),
        endISO: ISO8601DateFormatter.fallback.string(from: end),
        allDay: isAllDay,
        status: "confirmed",
        startMinutesFromNow: Int((start.timeIntervalSince(now) / 60).rounded()),
        durationMinutes: max(0, Int((end.timeIntervalSince(start) / 60).rounded())),
        calendar: ref,
        account: AccountRef(email: definition.account),
        attendees: withSelf,
        organizer: definition.account,
        selfResponse: event.selfResponse ?? "accepted",
        isRecurring: event.isRecurring ?? false,
        conferenceUrl: event.conferenceUrl ?? "",
        notesUrl: event.notesUrl ?? "",
        colorId: event.colorId ?? "9",
        transparency: event.transparency ?? "busy",
        htmlLink: "https://calendar.google.com/calendar/event?eid=demo-\(event.id)"
      )
    }
    .sorted { $0.startDate < $1.startDate }
  }

  private static func date(
    on day: Date,
    time: String,
    event: String,
    calendar: Foundation.Calendar
  ) throws -> Date {
    let parts = time.split(separator: ":")
    guard parts.count == 2,
          let hour = Int(parts[0]), let minute = Int(parts[1]),
          (0...23).contains(hour), (0...59).contains(minute) else {
      throw LoadError.badTime(event: event, value: time)
    }
    guard let resolved = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else {
      throw LoadError.badTime(event: event, value: time)
    }
    return resolved
  }
}
