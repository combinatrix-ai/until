import Foundation

struct WidgetAgendaEvent: Codable, Equatable, Hashable {
  var title: String
  var startDate: Date
  var endDate: Date
  var allDay: Bool
  var colorHex: String
}

struct WidgetAgendaSnapshot: Codable, Equatable {
  var authenticated: Bool
  var lastSync: Date?
  var coverageEnd: Date?
  var events: [WidgetAgendaEvent]
  var imminentNextLeadMinutes: Int?

  init(
    authenticated: Bool,
    lastSync: Date?,
    coverageEnd: Date?,
    events: [WidgetAgendaEvent],
    imminentNextLeadMinutes: Int? = nil
  ) {
    self.authenticated = authenticated
    self.lastSync = lastSync
    self.coverageEnd = coverageEnd
    self.events = events
    self.imminentNextLeadMinutes = imminentNextLeadMinutes
  }

  static let signedOut = WidgetAgendaSnapshot(
    authenticated: false,
    lastSync: nil,
    coverageEnd: nil,
    events: []
  )

  func presentation(at now: Date, calendar: Calendar = .current) -> WidgetAgendaPresentation {
    let start = calendar.startOfDay(for: now)
    guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
      return WidgetAgendaPresentation(allDay: [], hero: nil, hiddenCount: 0, coversDay: false)
    }
    let today = events.filter { $0.startDate < end && $0.endDate > start }
    let allDay = today.filter(\.allDay).sorted { $0.startDate < $1.startDate }
    let upcoming = today.filter { !$0.allDay && $0.endDate > now }
      .sorted { $0.startDate < $1.startDate }
    let imminent = imminentNextLeadMinutes.flatMap { leadMinutes in
      upcoming.first { event in
        let startsIn = event.startDate.timeIntervalSince(now)
        return startsIn >= 0 && startsIn <= TimeInterval(max(0, leadMinutes) * 60)
      }
    }
    let visibleAllDay = Array(allDay.prefix(2))
    return WidgetAgendaPresentation(
      allDay: visibleAllDay,
      // Match the menubar's default choice when events overlap: the most
      // recently started active event, then the next event by start time.
      hero: imminent ?? upcoming.last(where: { $0.startDate <= now }) ?? upcoming.first,
      hiddenCount: max(0, allDay.count + upcoming.count - visibleAllDay.count - (upcoming.isEmpty ? 0 : 1)),
      coversDay: coverageEnd.map { $0 >= end } ?? false
    )
  }

  func transitionDates(after now: Date, calendar: Calendar = .current) -> [Date] {
    let endOfToday = calendar.date(
      byAdding: .day,
      value: 1,
      to: calendar.startOfDay(for: now)
    )
    let horizon = now.addingTimeInterval(24 * 3600)
    return ([endOfToday].compactMap { $0 } + events.flatMap { [$0.startDate, $0.endDate] })
      .filter { $0 > now && $0 <= horizon }
      .sorted()
      .reduce(into: [Date]()) { result, date in
        if result.last != date { result.append(date) }
      }
  }
}

struct WidgetAgendaPresentation {
  var allDay: [WidgetAgendaEvent]
  var hero: WidgetAgendaEvent?
  var hiddenCount: Int
  var coversDay: Bool
}

enum WidgetAgendaStore {
  static let widgetKind = "ai.combinatrix.until.agenda"
  static let fileName = "agenda.json"

  static func sharedURL(fileManager: FileManager = .default) -> URL? {
    guard let groupIdentifier = Bundle.main.object(
      forInfoDictionaryKey: "UntilWidgetGroupIdentifier"
    ) as? String, !groupIdentifier.isEmpty else { return nil }
    return fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
      .appendingPathComponent(fileName)
  }

  static func read(from url: URL) -> WidgetAgendaSnapshot? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(WidgetAgendaSnapshot.self, from: data)
  }

  static func write(_ snapshot: WidgetAgendaSnapshot, to url: URL) throws {
    let data = try JSONEncoder().encode(snapshot)
    try data.write(to: url, options: .atomic)
  }
}
