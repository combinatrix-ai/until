import XCTest
@testable import Until

@MainActor
final class GroupByDayTests: XCTestCase {
  let calendar = Calendar.current

  func testTimedEventsGroupedByStartOfDayOrderPreserved() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    let e1Start = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let e2Start = makeDate(year: 2026, month: 7, day: 5, hour: 14)
    let e3Start = makeDate(year: 2026, month: 7, day: 6, hour: 10)

    let e1 = makeEvent(id: "e1", startISO: isoString(from: e1Start), endISO: isoString(from: e1Start.addingTimeInterval(3600)))
    let e2 = makeEvent(id: "e2", startISO: isoString(from: e2Start), endISO: isoString(from: e2Start.addingTimeInterval(3600)))
    let e3 = makeEvent(id: "e3", startISO: isoString(from: e3Start), endISO: isoString(from: e3Start.addingTimeInterval(3600)))

    let sections = AppModel.groupByDay(timed: [e1, e2, e3], allDay: [], now: now, lookaheadHours: 48)

    XCTAssertEqual(sections.count, 2)
    XCTAssertEqual(sections[0].day, calendar.startOfDay(for: e1Start))
    XCTAssertEqual(sections[0].rows.map { $0.event.id }, ["e1", "e2"])
    XCTAssertEqual(sections[1].day, calendar.startOfDay(for: e3Start))
    XCTAssertEqual(sections[1].rows.map { $0.event.id }, ["e3"])
  }

  func testMultiDayAllDayEventRepeatsWithGoogleExclusiveEndDate() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    // Google all-day multi-day: start = July 5, end = July 8 (EXCLUSIVE),
    // meaning the event actually covers July 5, 6, 7 -- NOT July 8.
    let start = makeDate(year: 2026, month: 7, day: 5)
    let end = makeDate(year: 2026, month: 7, day: 8)
    let event = makeEvent(id: "multi", startISO: isoString(from: start), endISO: isoString(from: end), allDay: true)

    let sections = AppModel.groupByDay(timed: [], allDay: [event], now: now, lookaheadHours: 240)
    let days = sections.map { $0.day }

    XCTAssertEqual(days, [
      calendar.startOfDay(for: start),
      calendar.startOfDay(for: makeDate(year: 2026, month: 7, day: 6)),
      calendar.startOfDay(for: makeDate(year: 2026, month: 7, day: 7))
    ])
    // The exclusive end day (July 8) must NOT appear.
    XCTAssertFalse(days.contains(calendar.startOfDay(for: end)))
    for section in sections {
      XCTAssertEqual(section.rows.map { $0.event.id }, ["multi"])
    }
  }

  func testAllDayEventStartingBeforeNowIsClampedToWindowStart() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    // Started 3 days ago, ends tomorrow (exclusive) -> covers up through today.
    let start = makeDate(year: 2026, month: 7, day: 2)
    let end = makeDate(year: 2026, month: 7, day: 6)
    let event = makeEvent(id: "past-start", startISO: isoString(from: start), endISO: isoString(from: end), allDay: true)

    let sections = AppModel.groupByDay(timed: [], allDay: [event], now: now, lookaheadHours: 48)
    let days = sections.map { $0.day }

    // Clamped to windowStart (today, July 5), not the true start (July 2).
    XCTAssertEqual(days, [calendar.startOfDay(for: now)])
    XCTAssertFalse(days.contains(calendar.startOfDay(for: start)))
  }

  func testAllDayEventBeyondLookaheadWindowEndIsExcluded() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    // lookaheadHours: 24 -> windowEndDay = startOfDay(now + 24h) = July 6.
    // Event spans July 10 - July 12 (exclusive), entirely beyond the window.
    let start = makeDate(year: 2026, month: 7, day: 10)
    let end = makeDate(year: 2026, month: 7, day: 12)
    let event = makeEvent(id: "far-future", startISO: isoString(from: start), endISO: isoString(from: end), allDay: true)

    let sections = AppModel.groupByDay(timed: [], allDay: [event], now: now, lookaheadHours: 24)
    XCTAssertTrue(sections.isEmpty)
  }

  func testAllDaySpanningIntoButNotFullyPastWindowEndIsPartiallyIncluded() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    // windowEndDay = startOfDay(now + 24h) = July 6. Loop condition is
    // `day <= windowEndDay`, so July 6 itself IS included even though it's
    // at the edge of the window.
    let start = makeDate(year: 2026, month: 7, day: 5)
    let end = makeDate(year: 2026, month: 7, day: 9) // exclusive; covers 5,6,7,8
    let event = makeEvent(id: "spanning", startISO: isoString(from: start), endISO: isoString(from: end), allDay: true)

    let sections = AppModel.groupByDay(timed: [], allDay: [event], now: now, lookaheadHours: 24)
    let days = sections.map { $0.day }
    let windowEndDay = calendar.startOfDay(for: now.addingTimeInterval(24 * 3600))

    XCTAssertEqual(days, [
      calendar.startOfDay(for: makeDate(year: 2026, month: 7, day: 5)),
      calendar.startOfDay(for: makeDate(year: 2026, month: 7, day: 6))
    ])
    XCTAssertEqual(days.last, windowEndDay)
    // Days 7 and 8 are excluded because they're past windowEndDay.
    XCTAssertFalse(days.contains(calendar.startOfDay(for: makeDate(year: 2026, month: 7, day: 7))))
  }

  func testDaySectionsSortedAscendingAllDayBeforeTimedWithinSection() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    let day2Start = makeDate(year: 2026, month: 7, day: 6)
    let timedStart = makeDate(year: 2026, month: 7, day: 5, hour: 10)

    let timedEvent = makeEvent(id: "timed", startISO: isoString(from: timedStart), endISO: isoString(from: timedStart.addingTimeInterval(1800)))
    let allDayStart = makeDate(year: 2026, month: 7, day: 5)
    let allDayEnd = makeDate(year: 2026, month: 7, day: 6)
    let allDayEvent = makeEvent(id: "allday", startISO: isoString(from: allDayStart), endISO: isoString(from: allDayEnd), allDay: true)

    let laterTimedEvent = makeEvent(id: "later", startISO: isoString(from: day2Start), endISO: isoString(from: day2Start.addingTimeInterval(3600)))

    let sections = AppModel.groupByDay(
      timed: [timedEvent, laterTimedEvent],
      allDay: [allDayEvent],
      now: now,
      lookaheadHours: 48
    )

    XCTAssertEqual(sections.map { $0.day }, sections.map { $0.day }.sorted())
    XCTAssertEqual(sections.count, 2)
    // Within the first day's section, all-day rows come before timed rows.
    XCTAssertEqual(sections[0].rows.map { $0.event.id }, ["allday", "timed"])
    XCTAssertEqual(sections[1].rows.map { $0.event.id }, ["later"])
  }
}
