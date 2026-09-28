import XCTest
@testable import Until

final class WidgetAgendaSnapshotTests: XCTestCase {
  private let calendar = Calendar(identifier: .gregorian)

  func testPresentationIncludesSpanningAllDayAndCurrentTimedEvent() throws {
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
    let now = day.addingTimeInterval(12 * 3600)
    let allDay = WidgetAgendaEvent(
      title: "Multi-day",
      startDate: day.addingTimeInterval(-24 * 3600),
      endDate: day.addingTimeInterval(24 * 3600),
      allDay: true,
      colorHex: "#123456"
    )
    let elapsed = WidgetAgendaEvent(
      title: "Elapsed",
      startDate: day.addingTimeInterval(9 * 3600),
      endDate: day.addingTimeInterval(10 * 3600),
      allDay: false,
      colorHex: "#123456"
    )
    let current = WidgetAgendaEvent(
      title: "Current",
      startDate: day.addingTimeInterval(11 * 3600),
      endDate: day.addingTimeInterval(13 * 3600),
      allDay: false,
      colorHex: "#123456"
    )
    let later = WidgetAgendaEvent(
      title: "Later",
      startDate: day.addingTimeInterval(14 * 3600),
      endDate: day.addingTimeInterval(15 * 3600),
      allDay: false,
      colorHex: "#123456"
    )
    let snapshot = WidgetAgendaSnapshot(
      authenticated: true,
      lastSync: now,
      coverageEnd: day.addingTimeInterval(24 * 3600),
      events: [later, elapsed, current, allDay]
    )

    let view = snapshot.presentation(at: now, calendar: calendar)
    XCTAssertEqual(view.allDay, [allDay])
    XCTAssertEqual(view.hero, current)
    XCTAssertEqual(view.additionalEvents, [later])
    XCTAssertEqual(view.hiddenCount, 0)
    XCTAssertTrue(view.coversDay)
  }

  func testAllDayEndDateIsExclusive() throws {
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
    let event = WidgetAgendaEvent(
      title: "Yesterday",
      startDate: day.addingTimeInterval(-24 * 3600),
      endDate: day,
      allDay: true,
      colorHex: "#123456"
    )
    let snapshot = WidgetAgendaSnapshot(
      authenticated: true,
      lastSync: day,
      coverageEnd: day.addingTimeInterval(24 * 3600),
      events: [event]
    )
    XCTAssertTrue(snapshot.presentation(at: day, calendar: calendar).allDay.isEmpty)
  }

  func testPresentationPrefersMostRecentlyStartedCurrentEvent() throws {
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
    let now = day.addingTimeInterval(12 * 3600)
    let earlier = WidgetAgendaEvent(
      title: "Earlier",
      startDate: day.addingTimeInterval(10 * 3600),
      endDate: day.addingTimeInterval(13 * 3600),
      allDay: false,
      colorHex: "#123456"
    )
    let later = WidgetAgendaEvent(
      title: "Later",
      startDate: day.addingTimeInterval(11 * 3600),
      endDate: day.addingTimeInterval(14 * 3600),
      allDay: false,
      colorHex: "#123456"
    )
    let next = WidgetAgendaEvent(
      title: "Next",
      startDate: day.addingTimeInterval(15 * 3600),
      endDate: day.addingTimeInterval(16 * 3600),
      allDay: false,
      colorHex: "#123456"
    )
    let snapshot = WidgetAgendaSnapshot(
      authenticated: true,
      lastSync: now,
      coverageEnd: day.addingTimeInterval(24 * 3600),
      events: [next, earlier, later]
    )

    XCTAssertEqual(snapshot.presentation(at: now, calendar: calendar).hero, later)
    XCTAssertEqual(snapshot.presentation(at: now, calendar: calendar).additionalEvents, [earlier, next])
    XCTAssertEqual(snapshot.presentation(at: later.endDate, calendar: calendar).hero, next)
  }

  func testPresentationUsesMenubarImminentNextPreference() throws {
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
    let now = day.addingTimeInterval(12 * 3600)
    let current = WidgetAgendaEvent(
      title: "Current",
      startDate: day.addingTimeInterval(11 * 3600),
      endDate: day.addingTimeInterval(13 * 3600),
      allDay: false,
      colorHex: "#123456"
    )
    let next = WidgetAgendaEvent(
      title: "Next",
      startDate: now.addingTimeInterval(5 * 60),
      endDate: day.addingTimeInterval(14 * 3600),
      allDay: false,
      colorHex: "#123456"
    )
    let snapshot = WidgetAgendaSnapshot(
      authenticated: true,
      lastSync: now,
      coverageEnd: day.addingTimeInterval(24 * 3600),
      events: [current, next],
      imminentNextLeadMinutes: 10
    )

    XCTAssertEqual(snapshot.presentation(at: now, calendar: calendar).hero, next)
    XCTAssertEqual(snapshot.presentation(at: now, calendar: calendar).additionalEvents, [current])
    XCTAssertEqual(snapshot.presentation(at: now.addingTimeInterval(-6 * 60), calendar: calendar).hero, current)
    XCTAssertEqual(snapshot.presentation(at: next.startDate, calendar: calendar).hero, next)
    XCTAssertTrue(snapshot.transitionDates(after: now.addingTimeInterval(-6 * 60), calendar: calendar)
      .contains(next.startDate.addingTimeInterval(-10 * 60)))
  }

  func testTransitionsAreFutureSortedAndUnique() throws {
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
    let now = day.addingTimeInterval(12 * 3600)
    let first = WidgetAgendaEvent(
      title: "First",
      startDate: day.addingTimeInterval(13 * 3600),
      endDate: day.addingTimeInterval(14 * 3600),
      allDay: false,
      colorHex: "#123456"
    )
    let second = WidgetAgendaEvent(
      title: "Second",
      startDate: first.endDate,
      endDate: day.addingTimeInterval(25 * 3600),
      allDay: false,
      colorHex: "#123456"
    )
    let snapshot = WidgetAgendaSnapshot(
      authenticated: true,
      lastSync: now,
      coverageEnd: day.addingTimeInterval(48 * 3600),
      events: [second, first]
    )
    XCTAssertEqual(snapshot.transitionDates(after: now, calendar: calendar), [
      first.startDate, first.endDate, day.addingTimeInterval(24 * 3600), second.endDate
    ])
  }

  func testAdditionalEventsAreOrderedLimitedAndExcludedFromHiddenCount() throws {
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
    let events = (10...15).map { hour in
      WidgetAgendaEvent(
        title: "Event \(hour)",
        startDate: day.addingTimeInterval(Double(hour) * 3600),
        endDate: day.addingTimeInterval(Double(hour + 1) * 3600),
        allDay: false,
        colorHex: "#123456"
      )
    }
    let snapshot = WidgetAgendaSnapshot(
      authenticated: true, lastSync: day, coverageEnd: day.addingTimeInterval(24 * 3600),
      events: events.reversed()
    )
    let view = snapshot.presentation(at: day.addingTimeInterval(9 * 3600), calendar: calendar)
    XCTAssertEqual(view.hero, events[0])
    XCTAssertEqual(view.additionalEvents, Array(events[1...3]))
    XCTAssertEqual(view.hiddenCount, 2)

    let later = snapshot.presentation(at: events[3].endDate, calendar: calendar)
    XCTAssertEqual(later.hero, events[4])
    XCTAssertEqual(later.additionalEvents, [events[5]])
    XCTAssertEqual(later.hiddenCount, 0)
  }

  func testIdenticalEventsRemainSeparateOccurrences() throws {
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28)))
    let event = WidgetAgendaEvent(
      title: "Same event on two calendars", startDate: day.addingTimeInterval(3600),
      endDate: day.addingTimeInterval(7200), allDay: false, colorHex: "#123456"
    )
    let snapshot = WidgetAgendaSnapshot(
      authenticated: true, lastSync: day, coverageEnd: day.addingTimeInterval(24 * 3600),
      events: [event, event]
    )
    let view = snapshot.presentation(at: day, calendar: calendar)
    XCTAssertEqual(view.hero, event)
    XCTAssertEqual(view.additionalEvents, [event])
    XCTAssertEqual(view.hiddenCount, 0)
  }

  func testSnapshotRoundTripsThroughSharedFile() throws {
    let snapshot = WidgetAgendaSnapshot(
      authenticated: true,
      lastSync: Date(timeIntervalSince1970: 1_000),
      coverageEnd: Date(timeIntervalSince1970: 3_000),
      events: [WidgetAgendaEvent(
        title: "Meeting",
        startDate: Date(timeIntervalSince1970: 1_500),
        endDate: Date(timeIntervalSince1970: 2_000),
        allDay: false,
        colorHex: "#abcdef"
      )]
    )
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try WidgetAgendaStore.write(snapshot, to: url)
    XCTAssertEqual(WidgetAgendaStore.read(from: url), snapshot)
  }
}
