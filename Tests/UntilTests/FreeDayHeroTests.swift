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

  func testEventStartingExactlyAtNowIsNotFree() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let event = makeEvent(
      id: "starts-now",
      startISO: isoString(from: now),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10))
    )

    let decision = AppModel.freeDayHeroNextEvent(timed: [event], now: now)

    guard case .notFree = decision else {
      return XCTFail("An event starting exactly now must suppress the free-day hero")
    }
  }

  func testEventEndingExactlyAtNowIsFree() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let event = makeEvent(
      id: "ends-now",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 8)),
      endISO: isoString(from: now)
    )

    let decision = AppModel.freeDayHeroNextEvent(timed: [event], now: now)

    guard case .free(let next) = decision else {
      return XCTFail("An event ending exactly now must allow the free-day hero")
    }
    XCTAssertNil(next)
  }

  func testCrossMidnightInProgressEventSuppressesHero() {
    let now = makeDate(year: 2026, month: 7, day: 6, hour: 1, minute: 30)
    let event = makeEvent(
      id: "cross-midnight",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 23)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 2))
    )

    let decision = AppModel.freeDayHeroNextEvent(timed: [event], now: now)

    guard case .notFree = decision else {
      return XCTFail("A cross-midnight in-progress event must suppress the free-day hero")
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

  func testNonImminentNextDayMenubarEventYieldsToFreeDayHero() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let tomorrow = makeEvent(
      id: "tomorrow",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 11))
    )

    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: tomorrow,
      config: .default,
      timed: [tomorrow],
      now: now,
      coverageEnd: .distantFuture
    )

    XCTAssertTrue(occupancy.showsFreeDayHero)
    XCTAssertNil(occupancy.heroEvent)
    XCTAssertNil(occupancy.nowStripEvent)
    XCTAssertEqual(occupancy.freeDayNextEvent?.id, tomorrow.id)
  }

  func testImminentNextDayMenubarEventKeepsUpNextHero() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 23, minute: 58)
    let imminent = makeEvent(
      id: "imminent",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 0, minute: 2)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 1, minute: 2))
    )

    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: imminent,
      config: .default,
      timed: [imminent],
      now: now,
      coverageEnd: .distantFuture
    )

    XCTAssertFalse(occupancy.showsFreeDayHero)
    XCTAssertEqual(occupancy.heroEvent?.id, imminent.id)
    XCTAssertNil(occupancy.freeDayNextEvent)
  }

  func testDisplacedNextDayEventRemainsInListRows() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let tomorrow = makeEvent(
      id: "tomorrow",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 11))
    )
    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: tomorrow,
      config: .default,
      timed: [tomorrow],
      now: now,
      coverageEnd: .distantFuture
    )
    let rows = [DayEvent(day: Calendar.current.startOfDay(for: tomorrow.startDate), event: tomorrow)]

    let remaining = PanelView.rowsExcludingRenderedSlots(rows, occupancy: occupancy)

    XCTAssertEqual(remaining, rows)
  }

  func testUnknownCoverageSuppressesFreeDayHero() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let tomorrow = makeEvent(
      id: "tomorrow",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 11))
    )

    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: tomorrow,
      config: .default,
      timed: [tomorrow],
      now: now,
      coverageEnd: nil
    )

    XCTAssertFalse(occupancy.showsFreeDayHero)
    XCTAssertEqual(occupancy.heroEvent?.id, tomorrow.id)
  }

  func testShortFetchWindowSuppressesFreeDayHero() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let tomorrow = makeEvent(
      id: "tomorrow",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 11))
    )
    var config = AppConfig.default
    config.lookaheadHours = 1

    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: tomorrow,
      config: config,
      timed: [tomorrow],
      now: now,
      coverageEnd: now.addingTimeInterval(3600)
    )

    XCTAssertFalse(occupancy.showsFreeDayHero)
    XCTAssertEqual(occupancy.heroEvent?.id, tomorrow.id)
  }

  func testImminentNextEventSuppressesFreeDayHeroWhenMenubarHeroIsNil() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 23, minute: 58)
    let imminent = makeEvent(
      id: "imminent",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 0, minute: 1)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 1, minute: 1))
    )
    var config = AppConfig.default
    config.menubarShowsNextAlways = false
    config.menubarLeadMinutes = 0

    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: nil,
      config: config,
      timed: [imminent],
      now: now,
      coverageEnd: .distantFuture
    )

    XCTAssertFalse(occupancy.showsFreeDayHero)
    XCTAssertNil(occupancy.heroEvent)
    XCTAssertNil(occupancy.nowStripEvent)
  }

  func testEndedCachedMenubarHeroDoesNotBlockFreeDayHeroOrPinItsRow() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10)
    let ended = makeEvent(
      id: "ended-cached-hero",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 8)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9))
    )

    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: ended,
      config: .default,
      timed: [ended],
      now: now,
      coverageEnd: .distantFuture
    )
    let row = DayEvent(day: Calendar.current.startOfDay(for: ended.startDate), event: ended)

    XCTAssertTrue(occupancy.showsFreeDayHero)
    XCTAssertNil(occupancy.heroEvent)
    XCTAssertEqual(PanelView.rowsExcludingRenderedSlots([row], occupancy: occupancy), [row])
  }

  func testNextEventExactlyAtNotifyLeadIsStillImminent() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 23, minute: 55)
    let start = makeDate(year: 2026, month: 7, day: 6, hour: 0)
    let event = makeEvent(
      id: "exact-lead",
      startISO: isoString(from: start),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 1))
    )

    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: nil,
      config: .default,
      timed: [event],
      now: now,
      coverageEnd: .distantFuture
    )

    XCTAssertFalse(occupancy.showsFreeDayHero)
    XCTAssertNil(occupancy.heroEvent)
  }

  func testNextEventOneSecondBeyondNotifyLeadAllowsFreeDayHero() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 23, minute: 55)
    let start = makeDate(year: 2026, month: 7, day: 6, hour: 0, second: 1)
    let event = makeEvent(
      id: "past-lead",
      startISO: isoString(from: start),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 1))
    )

    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: nil,
      config: .default,
      timed: [event],
      now: now,
      coverageEnd: .distantFuture
    )

    XCTAssertTrue(occupancy.showsFreeDayHero)
    XCTAssertEqual(occupancy.freeDayNextEvent?.id, event.id)
  }

  func testStaleEndedMenubarHeroLeavesOngoingEventInNowStrip() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let ended = makeEvent(
      id: "ended-cached-hero",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 7)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 8))
    )
    let ongoing = makeEvent(
      id: "ongoing",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 8, minute: 30)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10))
    )

    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: ended,
      config: .default,
      timed: [ended, ongoing],
      now: now,
      coverageEnd: .distantFuture
    )

    XCTAssertFalse(occupancy.showsFreeDayHero)
    XCTAssertNil(occupancy.heroEvent)
    XCTAssertEqual(occupancy.nowStripEvent?.id, ongoing.id)
  }

  func testCoverageEndingExactlyAtEndOfDayAllowsFreeDayHero() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let endOfToday = Calendar.current.date(
      byAdding: .day,
      value: 1,
      to: Calendar.current.startOfDay(for: now)
    )!

    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: nil,
      config: .default,
      timed: [],
      now: now,
      coverageEnd: endOfToday
    )

    XCTAssertTrue(occupancy.showsFreeDayHero)
  }

  func testCoverageEndingOneSecondBeforeEndOfDaySuppressesFreeDayHero() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let endOfToday = Calendar.current.date(
      byAdding: .day,
      value: 1,
      to: Calendar.current.startOfDay(for: now)
    )!

    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: nil,
      config: .default,
      timed: [],
      now: now,
      coverageEnd: endOfToday.addingTimeInterval(-1)
    )

    XCTAssertFalse(occupancy.showsFreeDayHero)
  }

  func testSectionEmptiedByHeroPinningIsDropped() {
    // 0:57, bbq today 18:00 as the UP NEXT hero and today's only event: the
    // "Today" section must disappear rather than render an empty header.
    let now = makeDate(year: 2026, month: 8, day: 8, hour: 0, minute: 57)
    let bbq = makeEvent(
      id: "bbq",
      startISO: isoString(from: makeDate(year: 2026, month: 8, day: 8, hour: 18)),
      endISO: isoString(from: makeDate(year: 2026, month: 8, day: 9, hour: 3))
    )
    let tomorrowEvent = makeEvent(
      id: "post",
      startISO: isoString(from: makeDate(year: 2026, month: 8, day: 9, hour: 8)),
      endISO: isoString(from: makeDate(year: 2026, month: 8, day: 9, hour: 9))
    )
    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: bbq,
      config: .default,
      timed: [bbq, tomorrowEvent],
      now: now,
      coverageEnd: makeDate(year: 2026, month: 8, day: 10)
    )
    XCTAssertEqual(occupancy.heroEvent?.id, bbq.id)

    let today = Calendar.current.startOfDay(for: now)
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
    let sections = [
      DaySection(day: today, rows: [DayEvent(day: today, event: bbq)]),
      DaySection(day: tomorrow, rows: [DayEvent(day: tomorrow, event: tomorrowEvent)])
    ]

    let visible = PanelView.visibleSections(sections, occupancy: occupancy, now: now)

    XCTAssertEqual(visible.map(\.section.day), [tomorrow])
    XCTAssertEqual(visible.first?.items.count, 1)
  }

  func testSectionWithRemainingRowsKeepsThemAfterHeroPinning() {
    let now = makeDate(year: 2026, month: 8, day: 8, hour: 9)
    let hero = makeEvent(
      id: "hero",
      startISO: isoString(from: makeDate(year: 2026, month: 8, day: 8, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 8, day: 8, hour: 11))
    )
    let later = makeEvent(
      id: "later",
      startISO: isoString(from: makeDate(year: 2026, month: 8, day: 8, hour: 15)),
      endISO: isoString(from: makeDate(year: 2026, month: 8, day: 8, hour: 16))
    )
    let occupancy = PanelView.heroSlotOccupancy(
      menubarEvent: hero,
      config: .default,
      timed: [hero, later],
      now: now,
      coverageEnd: makeDate(year: 2026, month: 8, day: 10)
    )
    let today = Calendar.current.startOfDay(for: now)
    let sections = [
      DaySection(day: today, rows: [DayEvent(day: today, event: hero), DayEvent(day: today, event: later)])
    ]

    let visible = PanelView.visibleSections(sections, occupancy: occupancy, now: now)

    XCTAssertEqual(visible.count, 1)
    XCTAssertEqual(
      visible.first?.items.compactMap { item -> String? in
        if case .event(let dayEvent) = item { return dayEvent.event.id }
        return nil
      },
      [later.id]
    )
  }

  func testStaleRefreshGenerationIsDiscardedWholesale() {
    let model = AppModel(options: AppRuntimeOptions(demoMode: true))
    let newerFetchStart = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    model.applyFetchResults(
      [AccountFetchResult(email: "b@example.com", calendars: [], events: [], error: nil)],
      fetchStart: newerFetchStart,
      lookaheadHours: 24,
      generation: 0
    )
    let expectedCoverage = newerFetchStart.addingTimeInterval(24 * 3600)
    XCTAssertEqual(model.state.lastSync, newerFetchStart)
    XCTAssertEqual(model.state.calendarCoverageEnd, expectedCoverage)
    XCTAssertNil(model.state.lastError)

    // An out-of-order completion from a superseded refresh must not publish
    // anything: not its (failed) error, not its older sync time, and above
    // all not a coverage horizon its snapshot doesn't back.
    model.applyFetchResults(
      [AccountFetchResult(email: "a@example.com", calendars: nil, events: nil, error: "boom")],
      fetchStart: makeDate(year: 2026, month: 7, day: 5, hour: 8),
      lookaheadHours: 1,
      generation: -1
    )
    XCTAssertEqual(model.state.lastSync, newerFetchStart)
    XCTAssertEqual(model.state.calendarCoverageEnd, expectedCoverage)
    XCTAssertNil(model.state.lastError)
  }
}
