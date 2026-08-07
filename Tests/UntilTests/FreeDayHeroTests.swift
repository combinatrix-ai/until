import XCTest
@testable import Until

@MainActor
final class FreeDayHeroTests: XCTestCase {
  func testTimedEventLaterTodaySuppressesHero() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let event = makeEvent(
      id: "later-today",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 11))
    )

    let decision = AppModel.freeDayHeroNextEvent(timed: [event], now: now)

    guard case .notFree = decision else {
      return XCTFail("A later timed event today must suppress the free-day hero")
    }
  }

  func testTimedEventInProgressSuppressesHero() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let event = makeEvent(
      id: "in-progress",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 8)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10))
    )

    let decision = AppModel.freeDayHeroNextEvent(timed: [event], now: now)

    guard case .notFree = decision else {
      return XCTFail("An in-progress timed event must suppress the free-day hero")
    }
  }

  func testEmptyTodayShowsWithTomorrowAsNextEvent() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let tomorrow = makeEvent(
      id: "tomorrow",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 11))
    )

    let decision = AppModel.freeDayHeroNextEvent(timed: [tomorrow], now: now)

    guard case .free(let next) = decision else {
      return XCTFail("An empty day with a future event should show the hero")
    }
    XCTAssertEqual(next?.id, tomorrow.id)
  }

  func testEndedEventsTodayDoNotSuppressTomorrowNextEvent() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10)
    let ended = makeEvent(
      id: "ended",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 8)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9))
    )
    let tomorrow = makeEvent(
      id: "tomorrow",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 11))
    )

    let decision = AppModel.freeDayHeroNextEvent(timed: [ended, tomorrow], now: now)

    guard case .free(let next) = decision else {
      return XCTFail("Only ended events today should allow the free-day hero")
    }
    XCTAssertEqual(next?.id, tomorrow.id)
  }

  func testAllDayTodayDoesNotSuppressTomorrowNextEvent() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10)
    let allDay = makeEvent(
      id: "all-day",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6)),
      allDay: true
    )
    let tomorrow = makeEvent(
      id: "tomorrow",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 11))
    )

    let decision = AppModel.freeDayHeroNextEvent(timed: [allDay, tomorrow], now: now)

    guard case .free(let next) = decision else {
      return XCTFail("All-day events must not suppress the free-day hero")
    }
    XCTAssertEqual(next?.id, tomorrow.id)
  }

  func testNothingUpcomingShowsWithoutNextEvent() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10)
    let ended = makeEvent(
      id: "ended",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 8)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9))
    )

    let decision = AppModel.freeDayHeroNextEvent(timed: [ended], now: now)

    guard case .free(let next) = decision else {
      return XCTFail("A day with no future timed event should still show the hero")
    }
    XCTAssertNil(next)
  }
}
