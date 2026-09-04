import XCTest
@testable import Until

@MainActor
final class FreeDayHeroTests: XCTestCase {
  func testTimedEventLaterTodaySuppressesFreeDayFallback() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let event = makeEvent(
      id: "later-today",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 11))
    )

    guard case .notFree = AppModel.freeDayHeroNextEvent(timed: [event], now: now) else {
      return XCTFail("A later timed event today must suppress the free-day fallback")
    }
  }

  func testEndedEventsTodayAllowTomorrowAsFreeDayNext() {
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

    guard case .free(let next) = AppModel.freeDayHeroNextEvent(timed: [ended, tomorrow], now: now) else {
      return XCTFail("Only ended events today should allow the free-day fallback")
    }
    XCTAssertEqual(next?.id, tomorrow.id)
  }

  func testAllDayEventDoesNotSuppressFreeDayFallback() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10)
    let allDay = makeEvent(
      id: "all-day",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6)),
      allDay: true
    )

    guard case .free = AppModel.freeDayHeroNextEvent(timed: [allDay], now: now) else {
      return XCTFail("All-day events do not consume timed free-day space")
    }
  }

  func testMenubarHeroAlwaysWinsOverFreeDayFallback() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let tomorrow = makeEvent(
      id: "tomorrow",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 11))
    )

    let presentation = AppModel.timelinePresentation(
      menubarEvent: tomorrow,
      config: .default,
      timed: [tomorrow],
      now: now,
      coverageEnd: .distantFuture
    )

    XCTAssertEqual(presentation.heroEvent?.id, tomorrow.id)
    XCTAssertFalse(presentation.showsFreeDayHero)
  }

  func testAllDayMenubarEventStaysPlainAndDoesNotBecomeHeroCard() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let allDay = makeEvent(
      id: "all-day",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6)),
      allDay: true
    )

    let presentation = AppModel.timelinePresentation(
      menubarEvent: allDay,
      config: .default,
      timed: [],
      now: now,
      coverageEnd: .distantFuture
    )

    XCTAssertNil(presentation.heroEvent)
    XCTAssertTrue(presentation.showsFreeDayHero)
  }

  func testFreeDayFallbackAddsProminentItemToTodaySection() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let tomorrow = makeEvent(
      id: "tomorrow",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 11))
    )
    let presentation = AppModel.timelinePresentation(
      menubarEvent: nil,
      config: .default,
      timed: [tomorrow],
      now: now,
      coverageEnd: .distantFuture
    )

    let sections = AppModel.timelineSections(
      AppModel.groupByDay(timed: [tomorrow], allDay: [], now: now, lookaheadHours: 48),
      presentation: presentation,
      now: now,
      coverageEnd: .distantFuture
    )
    let todayItems = sections.first { Calendar.current.isDate($0.section.day, inSameDayAs: now) }?.items

    XCTAssertEqual(todayItems?.first, .freeDayHero(Calendar.current.startOfDay(for: now)))
    XCTAssertTrue(todayItems?.contains(.nowLine(now)) == true)
  }

  func testNowLineIsHiddenWhenAProgressEventMarksTheCurrentMoment() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 10)
    let ongoing = makeEvent(
      id: "ongoing",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 30))
    )

    XCTAssertNil(AppModel.nowLineInsertionIndex(timed: [ongoing], now: now))
  }

  func testHeroEventRemainsInTimelineItems() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let hero = makeEvent(
      id: "hero",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 11))
    )
    let later = makeEvent(
      id: "later",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 14)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 15))
    )
    let presentation = AppModel.timelinePresentation(
      menubarEvent: hero,
      config: .default,
      timed: [hero, later],
      now: now,
      coverageEnd: .distantFuture
    )

    let sections = AppModel.timelineSections(
      AppModel.groupByDay(timed: [hero, later], allDay: [], now: now, lookaheadHours: 24),
      presentation: presentation,
      now: now,
      coverageEnd: .distantFuture
    )
    let eventIDs = sections.flatMap(\.items).compactMap { item -> String? in
      guard case .event(let dayEvent) = item else { return nil }
      return dayEvent.event.id
    }

    XCTAssertEqual(eventIDs, ["hero", "later"])
  }

  func testNowEmphasisEventRemainsInTimelineItems() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 10)
    let hero = makeEvent(
      id: "hero",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 10)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 11))
    )
    let ongoing = makeEvent(
      id: "ongoing",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 9, minute: 30))
    )
    let config = DemoCalendarData.config()
    let presentation = AppModel.timelinePresentation(
      menubarEvent: hero,
      config: config,
      timed: [ongoing, hero],
      now: now,
      coverageEnd: .distantFuture
    )
    let sections = AppModel.timelineSections(
      AppModel.groupByDay(timed: [ongoing, hero], allDay: [], now: now, lookaheadHours: 24),
      presentation: presentation,
      now: now,
      coverageEnd: .distantFuture
    )
    let eventIDs = sections.flatMap(\.items).compactMap { item -> String? in
      guard case .event(let dayEvent) = item else { return nil }
      return dayEvent.event.id
    }

    XCTAssertEqual(presentation.nowEmphasisEvent?.id, "ongoing")
    XCTAssertEqual(eventIDs, ["ongoing", "hero"])
  }

  func testUnknownCoverageDoesNotClaimFreeDay() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let presentation = AppModel.timelinePresentation(
      menubarEvent: nil,
      config: .default,
      timed: [],
      now: now,
      coverageEnd: nil
    )

    XCTAssertFalse(presentation.showsFreeDayHero)
  }

  func testCoverageAtMidnightSynthesizesAnEmptyFutureDay() {
    let now = makeDate(year: 2026, month: 8, day: 8, hour: 9)
    let tomorrow = Calendar.current.date(
      byAdding: .day,
      value: 1,
      to: Calendar.current.startOfDay(for: now)
    )!
    let presentation = TimelinePresentation(
      heroEvent: nil,
      nowEmphasisEvent: nil,
      nextEvent: nil,
      freeDayNextEvent: nil,
      showsFreeDayHero: false
    )

    let sections = AppModel.timelineSections(
      [],
      presentation: presentation,
      now: now,
      coverageEnd: Calendar.current.date(byAdding: .day, value: 1, to: tomorrow)!
    )

    XCTAssertEqual(sections.map(\.section.day), [
      Calendar.current.startOfDay(for: now),
      tomorrow
    ])
    XCTAssertEqual(sections.last?.items, [.freeDay(tomorrow)])
  }

  func testEventEndingExactlyAtNowAllowsFreeDayFallback() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let ended = makeEvent(
      id: "ended-now",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 8)),
      endISO: isoString(from: now)
    )

    guard case .free(let next) = AppModel.freeDayHeroNextEvent(timed: [ended], now: now) else {
      return XCTFail("An event ending exactly now must allow the free-day fallback")
    }
    XCTAssertNil(next)
  }

  func testCrossMidnightInProgressEventSuppressesFreeDayFallback() {
    let now = makeDate(year: 2026, month: 7, day: 6, hour: 1, minute: 30)
    let overnight = makeEvent(
      id: "overnight",
      startISO: isoString(from: makeDate(year: 2026, month: 7, day: 5, hour: 23)),
      endISO: isoString(from: makeDate(year: 2026, month: 7, day: 6, hour: 2))
    )

    guard case .notFree = AppModel.freeDayHeroNextEvent(timed: [overnight], now: now) else {
      return XCTFail("An overnight in-progress event must suppress the free-day fallback")
    }
  }

  func testCoverageEndingOneSecondEarlyDoesNotClaimFreeDay() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let endOfToday = Calendar.current.date(
      byAdding: .day,
      value: 1,
      to: Calendar.current.startOfDay(for: now)
    )!

    let presentation = AppModel.timelinePresentation(
      menubarEvent: nil,
      config: .default,
      timed: [],
      now: now,
      coverageEnd: endOfToday.addingTimeInterval(-1)
    )

    XCTAssertFalse(presentation.showsFreeDayHero)
  }

  func testMiddleCoveredEmptyDayGetsOneFreeDayMarker() {
    let now = makeDate(year: 2026, month: 8, day: 8, hour: 9)
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
    let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today)!
    let dayAfterThat = calendar.date(byAdding: .day, value: 3, to: today)!
    let first = makeEvent(
      id: "first",
      startISO: isoString(from: tomorrow.addingTimeInterval(10 * 3600)),
      endISO: isoString(from: tomorrow.addingTimeInterval(11 * 3600))
    )
    let last = makeEvent(
      id: "last",
      startISO: isoString(from: dayAfterThat.addingTimeInterval(10 * 3600)),
      endISO: isoString(from: dayAfterThat.addingTimeInterval(11 * 3600))
    )
    let presentation = TimelinePresentation(
      heroEvent: nil,
      nowEmphasisEvent: nil,
      nextEvent: nil,
      freeDayNextEvent: nil,
      showsFreeDayHero: false
    )

    let sections = AppModel.timelineSections(
      [
        DaySection(day: tomorrow, rows: [DayEvent(day: tomorrow, event: first)]),
        DaySection(day: dayAfterThat, rows: [DayEvent(day: dayAfterThat, event: last)])
      ],
      presentation: presentation,
      now: now,
      coverageEnd: dayAfterThat.addingTimeInterval(24 * 3600)
    )

    XCTAssertEqual(sections.map(\.section.day), [today, tomorrow, dayAfterTomorrow, dayAfterThat])
    XCTAssertEqual(sections[2].items, [.freeDay(dayAfterTomorrow)])
  }

  func testUnknownCoverageKeepsRealFutureSectionsWithoutSynthesizingDays() {
    let now = makeDate(year: 2026, month: 8, day: 8, hour: 9)
    let tomorrow = makeDate(year: 2026, month: 8, day: 9)
    let event = makeEvent(
      id: "real-future",
      startISO: isoString(from: tomorrow.addingTimeInterval(10 * 3600)),
      endISO: isoString(from: tomorrow.addingTimeInterval(11 * 3600))
    )
    let presentation = TimelinePresentation(
      heroEvent: nil,
      nowEmphasisEvent: nil,
      nextEvent: nil,
      freeDayNextEvent: nil,
      showsFreeDayHero: false
    )

    let sections = AppModel.timelineSections(
      [DaySection(day: tomorrow, rows: [DayEvent(day: tomorrow, event: event)])],
      presentation: presentation,
      now: now,
      coverageEnd: nil
    )

    XCTAssertEqual(sections.map(\.section.day), [Calendar.current.startOfDay(for: now), tomorrow])
    XCTAssertEqual(
      sections.last?.items,
      [.event(DayEvent(day: tomorrow, event: event))]
    )
  }

  @MainActor
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
