import XCTest
@testable import Until

/// Covers the menubar picker's double-booking tie-break and the picker that
/// decides which non-hero event receives green NOW treatment in the rail.
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

  // MARK: - Embedded hero state and now-line placement

  func testMenubarHeroStateDerivesNowFromTheMenubarEvent() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 10)
    let event = makeEvent(
      id: "now",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 30))
    )

    XCTAssertEqual(AppModel.menubarHeroState(event: event, now: now), .now)
  }

  func testMenubarHeroStateDerivesNextFromTheMenubarEvent() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let event = makeEvent(
      id: "next",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 11))
    )

    XCTAssertEqual(AppModel.menubarHeroState(event: event, now: now), .next)
  }

  func testAllDayMenubarEventHasNoHeroCardState() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let allDay = makeEvent(
      id: "all-day",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6)),
      allDay: true
    )

    XCTAssertNil(AppModel.menubarHeroState(event: allDay, now: now))
  }

  func testNowLineIsPlacedBetweenPastAndUpcomingRows() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 12)
    let past = makeEvent(
      id: "past",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 11))
    )
    let upcoming = makeEvent(
      id: "upcoming",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 13)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 14))
    )

    XCTAssertEqual(AppModel.nowLineInsertionIndex(timed: [past, upcoming], now: now), 1)
  }

  func testNowLineIsBeforeTheFirstUpcomingRow() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let upcoming = makeEvent(
      id: "upcoming",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 11))
    )

    XCTAssertEqual(AppModel.nowLineInsertionIndex(timed: [upcoming], now: now), 0)
  }

  func testNextTimelineEventIsOnlyEmphasizedWhenHeroIsInProgress() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 10)
    let hero = makeEvent(
      id: "hero",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 30))
    )
    let next = makeEvent(
      id: "next",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 11))
    )

    XCTAssertEqual(AppModel.nextTimelineEvent(heroEvent: hero, timed: [hero, next], now: now)?.id, "next")
    XCTAssertNil(AppModel.nextTimelineEvent(heroEvent: next, timed: [hero, next], now: now))
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
