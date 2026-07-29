import XCTest
@testable import Until

/// Covers the NOW strip feature: `pickMenubarEvent`'s double-booking
/// tie-break (the most recently entered ongoing event wins, not the
/// earliest-started one) and the new `pickNowStripEvent` picker that decides
/// what — if anything — appears in the strip pinned above the hero.
@MainActor
final class NowStripTests: XCTestCase {
  // MARK: - pickMenubarEvent: double-booking tie-break

  func testDoubleBookedOngoingEventsPickTheMostRecentlyStarted() {
    // A: 9:00-10:00, B: 9:30-10:30, now 9:35 -- both ongoing, B started later.
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 35)
    let a = makeEvent(
      id: "a",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10))
    )
    let b = makeEvent(
      id: "b",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 30)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 30))
    )

    let picked = AppModel.pickMenubarEvent(config: .default, timed: [a, b], allDay: [], now: now)

    // The meeting most recently entered (B), not the earliest-starting (A) --
    // otherwise the menubar would bounce back to A the instant B started.
    XCTAssertEqual(picked?.id, "b")
  }

  func testSingleOngoingEventIsStillPickedUnchanged() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 15)
    let event = makeEvent(
      id: "solo",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10))
    )

    let picked = AppModel.pickMenubarEvent(config: .default, timed: [event], allDay: [], now: now)

    XCTAssertEqual(picked?.id, "solo")
  }

  // MARK: - pickNowStripEvent

  func testOngoingEventShowsInStripWhenMenubarHasSwitchedToImminentNext() {
    // A: 9:00-9:30 (ongoing), B: 9:30-10:00 (menubar already switched to it
    // as the imminent-next event, per `pickMenubarEvent`). The strip must
    // still surface A -- it would otherwise vanish from view entirely.
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 22)
    let a = makeEvent(
      id: "a",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 30))
    )
    let b = makeEvent(
      id: "b",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 30)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10))
    )

    let strip = AppModel.pickNowStripEvent(menubarEvent: b, config: .default, timed: [a, b], now: now)

    XCTAssertEqual(strip?.id, "a")
  }

  func testNoStripWhenMenubarEventIsItselfInProgress() {
    // The hero already renders "Now" for this event -- the strip must not
    // duplicate it.
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 10)
    let a = makeEvent(
      id: "a",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 30))
    )

    let strip = AppModel.pickNowStripEvent(menubarEvent: a, config: .default, timed: [a], now: now)

    XCTAssertNil(strip)
  }

  func testSkippedOngoingEventDoesNotAppearInStrip() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 10)
    let a = makeEvent(
      id: "a",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 30))
    )
    var config = AppConfig.default
    config.skippedMenubarEvents[a.actionKey] = a.endDate

    let strip = AppModel.pickNowStripEvent(menubarEvent: nil, config: config, timed: [a], now: now)

    XCTAssertNil(strip)
  }

  func testTwoOngoingEventsPickTheSoonerEndingOne() {
    // A ends later (10:00), B ends sooner (9:30) -- "when am I next free"
    // means B wins, even though A started first.
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 10)
    let a = makeEvent(
      id: "a",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10))
    )
    let b = makeEvent(
      id: "b",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 8, minute: 45)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 30))
    )

    let strip = AppModel.pickNowStripEvent(menubarEvent: nil, config: .default, timed: [a, b], now: now)

    XCTAssertEqual(strip?.id, "b")
  }

  func testNoStripWhenNothingIsOngoing() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let upcomingStart = now.addingTimeInterval(30 * 60)
    let upcoming = makeEvent(
      id: "upcoming",
      startISO: isoString(from: upcomingStart),
      endISO: isoString(from: upcomingStart.addingTimeInterval(30 * 60))
    )

    let strip = AppModel.pickNowStripEvent(menubarEvent: nil, config: .default, timed: [upcoming], now: now)

    XCTAssertNil(strip)
  }

  func testOngoingEventReturnedWhenThereIsNoMenubarEvent() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 10)
    let a = makeEvent(
      id: "a",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 30))
    )

    let strip = AppModel.pickNowStripEvent(menubarEvent: nil, config: .default, timed: [a], now: now)

    XCTAssertEqual(strip?.id, "a")
  }
}
