import XCTest
@testable import Until

/// Covers `AppModel.insertingFreeGaps`: the pure function that decides where
/// "free until …" dividers belong in the popover list, between two
/// consecutive TIMED rows separated by at least
/// `AppModel.freeGapThresholdMinutes` (30) of open time.
@MainActor
final class FreeGapDividerTests: XCTestCase {
  let calendar = Calendar.current

  func testGapOfAtLeastThirtyMinutesInsertsADivider() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    let firstStart = now.addingTimeInterval(10 * 60)
    let firstEnd = firstStart.addingTimeInterval(30 * 60) // ends 8:40
    let secondStart = firstEnd.addingTimeInterval(30 * 60) // starts 9:10 -> exactly 30m gap

    let first = makeEvent(id: "first", startISO: isoString(from: firstStart), endISO: isoString(from: firstEnd))
    let second = makeEvent(id: "second", startISO: isoString(from: secondStart), endISO: isoString(from: secondStart.addingTimeInterval(1800)))

    let rows = [DayEvent(day: calendar.startOfDay(for: now), event: first), DayEvent(day: calendar.startOfDay(for: now), event: second)]
    let items = AppModel.insertingFreeGaps(rows, now: now)

    XCTAssertEqual(items.count, 3)
    XCTAssertEqual(items[0], .event(rows[0]))
    guard case .gap(let gap) = items[1] else {
      XCTFail("Expected a gap divider between the two events")
      return
    }
    XCTAssertEqual(gap.afterActionKey, first.actionKey)
    XCTAssertEqual(gap.until, secondStart)
    XCTAssertEqual(items[2], .event(rows[1]))
  }

  func testGapUnderThirtyMinutesIsNotInserted() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    let firstStart = now.addingTimeInterval(10 * 60)
    let firstEnd = firstStart.addingTimeInterval(30 * 60)
    let secondStart = firstEnd.addingTimeInterval(29 * 60) // 29m gap -> below threshold

    let first = makeEvent(id: "first", startISO: isoString(from: firstStart), endISO: isoString(from: firstEnd))
    let second = makeEvent(id: "second", startISO: isoString(from: secondStart), endISO: isoString(from: secondStart.addingTimeInterval(1800)))
    let rows = [DayEvent(day: calendar.startOfDay(for: now), event: first), DayEvent(day: calendar.startOfDay(for: now), event: second)]

    let items = AppModel.insertingFreeGaps(rows, now: now)

    XCTAssertEqual(items, [.event(rows[0]), .event(rows[1])])
  }

  func testGapEndingInThePastIsNotInserted() {
    // The gap is long enough, but the next event's start has already passed
    // "now" (e.g. the popover just hasn't refreshed yet) -- no divider.
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 12)
    let firstStart = now.addingTimeInterval(-3 * 3600)
    let firstEnd = firstStart.addingTimeInterval(30 * 60)
    let secondStart = firstEnd.addingTimeInterval(60 * 60) // well past "now"

    let first = makeEvent(id: "first", startISO: isoString(from: firstStart), endISO: isoString(from: firstEnd))
    let second = makeEvent(id: "second", startISO: isoString(from: secondStart), endISO: isoString(from: secondStart.addingTimeInterval(1800)))
    let rows = [DayEvent(day: calendar.startOfDay(for: now), event: first), DayEvent(day: calendar.startOfDay(for: now), event: second)]

    let items = AppModel.insertingFreeGaps(rows, now: now)

    XCTAssertEqual(items, [.event(rows[0]), .event(rows[1])])
  }

  func testAllDayEventsAreIgnoredAndNeverBracketAGap() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    let allDayStart = makeDate(year: 2026, month: 7, day: 5)
    let allDayEnd = makeDate(year: 2026, month: 7, day: 6)
    let allDay = makeEvent(id: "allday", startISO: isoString(from: allDayStart), endISO: isoString(from: allDayEnd), allDay: true)

    let timedStart = now.addingTimeInterval(60 * 60)
    let timed = makeEvent(id: "timed", startISO: isoString(from: timedStart), endISO: isoString(from: timedStart.addingTimeInterval(1800)))

    // groupByDay orders all-day rows before timed rows within a section.
    let rows = [
      DayEvent(day: calendar.startOfDay(for: now), event: allDay),
      DayEvent(day: calendar.startOfDay(for: now), event: timed)
    ]

    let items = AppModel.insertingFreeGaps(rows, now: now)

    // No gap divider is inserted even though the all-day event "ends" the day
    // after and the timed event starts an hour from now -- all-day rows never
    // bracket a gap.
    XCTAssertEqual(items, [.event(rows[0]), .event(rows[1])])
  }

  func testMultipleGapsInARowEachGetTheirOwnDivider() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    let e1Start = now.addingTimeInterval(10 * 60)
    let e1End = e1Start.addingTimeInterval(30 * 60)
    let e2Start = e1End.addingTimeInterval(45 * 60) // 45m gap
    let e2End = e2Start.addingTimeInterval(30 * 60)
    let e3Start = e2End.addingTimeInterval(60 * 60) // 60m gap

    let e1 = makeEvent(id: "e1", startISO: isoString(from: e1Start), endISO: isoString(from: e1End))
    let e2 = makeEvent(id: "e2", startISO: isoString(from: e2Start), endISO: isoString(from: e2End))
    let e3 = makeEvent(id: "e3", startISO: isoString(from: e3Start), endISO: isoString(from: e3Start.addingTimeInterval(1800)))
    let rows = [
      DayEvent(day: calendar.startOfDay(for: now), event: e1),
      DayEvent(day: calendar.startOfDay(for: now), event: e2),
      DayEvent(day: calendar.startOfDay(for: now), event: e3)
    ]

    let items = AppModel.insertingFreeGaps(rows, now: now)

    XCTAssertEqual(items.count, 5)
    XCTAssertEqual(items[0], .event(rows[0]))
    guard case .gap(let firstGap) = items[1] else { return XCTFail("Expected first gap") }
    XCTAssertEqual(firstGap.until, e2Start)
    XCTAssertEqual(items[2], .event(rows[1]))
    guard case .gap(let secondGap) = items[3] else { return XCTFail("Expected second gap") }
    XCTAssertEqual(secondGap.until, e3Start)
    XCTAssertEqual(items[4], .event(rows[2]))
  }
}
