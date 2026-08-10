import XCTest
@testable import Until

/// Covers demo mode's runtime-option parsing (`--demo-mode` / `--demo-now` /
/// `--demo-overlap` / `--demo-free`) and the opt-in demo scenarios
/// (`DemoCalendarData.events(scenario:)`) that let the popover's in-progress
/// hero and green NOW rail row be demoed without disturbing the default
/// `--demo-mode` composition.
@MainActor
final class DemoCalendarDataTests: XCTestCase {
  // MARK: - AppRuntimeOptions.fromProcess

  func testDemoNowFlagImpliesDemoMode() {
    let options = AppRuntimeOptions.fromProcess(arguments: ["until", "--demo-now"], environment: [:])
    XCTAssertTrue(options.demoMode)
    XCTAssertEqual(options.demoScenario, .inProgress)
  }

  func testPlainDemoModeFlagDoesNotEnableNowEvent() {
    let options = AppRuntimeOptions.fromProcess(arguments: ["until", "--demo-mode"], environment: [:])
    XCTAssertTrue(options.demoMode)
    XCTAssertEqual(options.demoScenario, .upcoming)
  }

  func testDemoNowEnvVarImpliesDemoMode() {
    let options = AppRuntimeOptions.fromProcess(arguments: ["until"], environment: ["UNTIL_DEMO_NOW": "true"])
    XCTAssertTrue(options.demoMode)
    XCTAssertEqual(options.demoScenario, .inProgress)
  }

  func testDemoOverlapFlagImpliesDemoModeAndOverlapScenario() {
    let options = AppRuntimeOptions.fromProcess(arguments: ["until", "--demo-overlap"], environment: [:])
    XCTAssertTrue(options.demoMode)
    XCTAssertEqual(options.demoScenario, .overlap)
  }

  func testDemoOverlapEnvVarImpliesDemoModeAndOverlapScenario() {
    let options = AppRuntimeOptions.fromProcess(arguments: ["until"], environment: ["UNTIL_DEMO_OVERLAP": "1"])
    XCTAssertTrue(options.demoMode)
    XCTAssertEqual(options.demoScenario, .overlap)
  }

  func testDemoFreeFlagImpliesDemoModeAndFreeDayScenario() {
    let options = AppRuntimeOptions.fromProcess(arguments: ["until", "--demo-free"], environment: [:])
    XCTAssertTrue(options.demoMode)
    XCTAssertEqual(options.demoScenario, .freeDay)
  }

  func testDemoFreeEnvVarImpliesDemoModeAndFreeDayScenario() {
    let options = AppRuntimeOptions.fromProcess(arguments: ["until"], environment: ["UNTIL_DEMO_FREE": "true"])
    XCTAssertTrue(options.demoMode)
    XCTAssertEqual(options.demoScenario, .freeDay)
  }

  func testDemoNotificationFlagImpliesDemoModeAndNotificationScenario() {
    let options = AppRuntimeOptions.fromProcess(arguments: ["until", "--demo-notification"], environment: [:])
    XCTAssertTrue(options.demoMode)
    XCTAssertEqual(options.demoScenario, .notification)
  }

  func testDemoNotificationEnvVarImpliesDemoModeAndNotificationScenario() {
    let options = AppRuntimeOptions.fromProcess(
      arguments: ["until"],
      environment: ["UNTIL_DEMO_NOTIFICATION": "1"]
    )
    XCTAssertTrue(options.demoMode)
    XCTAssertEqual(options.demoScenario, .notification)
  }

  func testDemoNotificationWinsOverEveryOtherDemoSwitch() {
    // It is the only scenario with an effect outside the app, so combining it
    // with another switch must never silently drop it.
    let options = AppRuntimeOptions.fromProcess(
      arguments: ["until", "--demo-overlap", "--demo-free", "--demo-now", "--demo-notification"],
      environment: [:]
    )
    XCTAssertEqual(options.demoScenario, .notification)
  }

  // MARK: - Notification opt-in

  func testOnlyTheNotificationScenarioMayPostSystemNotifications() {
    for scenario in [AppRuntimeOptions.DemoScenario.upcoming, .inProgress, .overlap, .freeDay] {
      let options = AppRuntimeOptions(demoMode: true, demoScenario: scenario)
      XCTAssertFalse(options.allowsNotifications, "\(scenario) must stay silent")
      XCTAssertFalse(DemoCalendarData.config(scenario: scenario).notifyEnabled)
    }
    let notifying = AppRuntimeOptions(demoMode: true, demoScenario: .notification)
    XCTAssertTrue(notifying.allowsNotifications)
    XCTAssertTrue(DemoCalendarData.config(scenario: .notification).notifyEnabled)
  }

  func testRealRunsAlwaysAllowNotifications() {
    XCTAssertTrue(AppRuntimeOptions(demoMode: false, demoScenario: .upcoming).allowsNotifications)
  }

  func testNotificationScenarioFiresShortlyAfterLaunchRatherThanAfterTheFullLead() throws {
    let now = Date()
    let events = DemoCalendarData.events(
      now: now,
      selectedIds: DemoCalendarData.config(scenario: .notification).selectedCalendarIds,
      scenario: .notification
    )
    let next = try XCTUnwrap(
      events.filter { !$0.allDay && $0.startDate > now }.min { $0.startDate < $1.startDate }
    )
    let lead = TimeInterval(DemoCalendarData.notificationLeadMinutes * 60)
    let delay = next.startDate.addingTimeInterval(-lead).timeIntervalSince(now)
    XCTAssertEqual(
      delay,
      DemoCalendarData.notificationFireDelay,
      accuracy: 2,
      "the banner should land seconds after launch, not a full lead window later"
    )
  }

  func testDemoNowAndDemoOverlapFlagsTogetherPickOverlap() {
    // Overlap is the superset state, so it wins regardless of flag order.
    let options = AppRuntimeOptions.fromProcess(
      arguments: ["until", "--demo-now", "--demo-overlap"],
      environment: [:]
    )
    XCTAssertTrue(options.demoMode)
    XCTAssertEqual(options.demoScenario, .overlap)
  }

  // MARK: - Default demo composition (scenario: .upcoming) is unaffected

  // All-day events (e.g. "Launch assets due") are trivially "in progress"
  // for their whole day by design, unrelated to the half-hour anchoring
  // this covers, so only timed events are checked here — those are what
  // feed the popover hero's in-progress state via `pickMenubarEvent`.

  func testDefaultDemoEventsHaveNothingInProgressJustBeforeHalfHourBoundary() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 29)
    let events = DemoCalendarData.events(now: now, selectedIds: [], scenario: .upcoming)
    XCTAssertFalse(events.contains { !$0.allDay && $0.startDate <= now && $0.endDate > now })
  }

  func testDefaultDemoEventsHaveNothingInProgressJustAfterHalfHourBoundary() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 1)
    let events = DemoCalendarData.events(now: now, selectedIds: [], scenario: .upcoming)
    XCTAssertFalse(events.contains { !$0.allDay && $0.startDate <= now && $0.endDate > now })
  }

  // MARK: - scenario: .inProgress adds "launch-standup" in progress

  func testInProgressScenarioAddsInProgressLaunchStandup() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 29)
    let events = DemoCalendarData.events(now: now, selectedIds: [], scenario: .inProgress)
    guard let standup = events.first(where: { $0.id == "launch-standup" }) else {
      XCTFail("Expected launch-standup event for the .inProgress scenario")
      return
    }
    XCTAssertLessThanOrEqual(standup.startDate, now)
    XCTAssertGreaterThan(standup.endDate, now)
    XCTAssertFalse(standup.conferenceUrl.isEmpty)
    XCTAssertGreaterThanOrEqual(standup.attendees.filter { !$0.selfUser }.count, 2)
  }

  // MARK: - pickMenubarEvent picks the in-progress event even near a boundary

  func testPickMenubarEventPrefersInProgressLaunchStandupJustBeforeHalfHourBoundary() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 29)
    assertLaunchStandupIsPickedForMenubar(now: now)
  }

  func testPickMenubarEventPrefersInProgressLaunchStandupJustAfterHalfHourBoundary() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 1)
    assertLaunchStandupIsPickedForMenubar(now: now)
  }

  private func assertLaunchStandupIsPickedForMenubar(now: Date) {
    let events = DemoCalendarData.events(now: now, selectedIds: [], scenario: .inProgress)
    let timed = events.filter { !$0.allDay }
    let allDay = events.filter(\.allDay)
    let picked = AppModel.pickMenubarEvent(config: DemoCalendarData.config(), timed: timed, allDay: allDay, now: now)
    XCTAssertEqual(picked?.id, "launch-standup")
  }

  // MARK: - scenario: .overlap composes the standup and an imminent "Design review"

  func testOverlapScenarioLaunchStandupIsSeventyThreePercentElapsed() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 29)
    let events = DemoCalendarData.events(now: now, selectedIds: [], scenario: .overlap)
    guard let standup = events.first(where: { $0.id == "launch-standup" }) else {
      XCTFail("Expected launch-standup event for the .overlap scenario")
      return
    }
    XCTAssertEqual(standup.startDate, now.addingTimeInterval(-22 * 60))
    XCTAssertEqual(standup.endDate, now.addingTimeInterval(8 * 60))
  }

  func testOverlapScenarioDesignReviewStartsFourMinutesOut() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 29)
    let events = DemoCalendarData.events(now: now, selectedIds: [], scenario: .overlap)
    guard let review = events.first(where: { $0.id == "design-review" }) else {
      XCTFail("Expected design-review event for the .overlap scenario")
      return
    }
    XCTAssertEqual(review.startDate, now.addingTimeInterval(4 * 60))
  }

  // MARK: - scenario: .overlap pins the exact state the embedded-hero capture needs

  func testOverlapScenarioUsesMenubarHeroAndNowRailEmphasis() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 29)
    // Mirrors the event split the popover actually renders.
    let events = DemoCalendarData.events(now: now, selectedIds: [], scenario: .overlap)
      .filter { $0.endDate > now }
    let timed = events.filter { !$0.allDay }
    let allDay = events.filter(\.allDay)
    let config = DemoCalendarData.config()

    let menubarEvent = AppModel.pickMenubarEvent(config: config, timed: timed, allDay: allDay, now: now)
    XCTAssertEqual(menubarEvent?.id, "design-review")

    let presentation = AppModel.timelinePresentation(
      menubarEvent: menubarEvent,
      config: config,
      timed: timed,
      now: now,
      coverageEnd: .distantFuture
    )
    XCTAssertEqual(presentation.heroEvent?.id, "design-review")
    XCTAssertEqual(presentation.nowEmphasisEvent?.id, "launch-standup")
  }

  // MARK: - scenario: .freeDay is stable at any wall-clock time

  func testFreeDayScenarioHasEndedTimedEventsAllDayTodayAndTomorrowNext() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10)
    let events = DemoCalendarData.events(now: now, selectedIds: [], scenario: .freeDay)
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!

    let timed = events.filter { !$0.allDay }
    let allDay = events.filter(\.allDay)
    XCTAssertEqual(timed.map(\.id), ["free-day-focus", "free-day-lunch", "free-day-tomorrow"])
    XCTAssertEqual(allDay.map(\.id), ["free-day-all-day"])
    XCTAssertTrue(timed.filter { $0.id != "free-day-tomorrow" }.allSatisfy { event in
      calendar.isDate(event.startDate, inSameDayAs: now) && event.endDate <= now
    })
    XCTAssertTrue(allDay.allSatisfy { calendar.isDate($0.startDate, inSameDayAs: now) })
    guard let tomorrowEvent = timed.first(where: { $0.id == "free-day-tomorrow" }) else {
      return XCTFail("Expected the free-day scenario's tomorrow event")
    }
    XCTAssertTrue(calendar.isDate(tomorrowEvent.startDate, inSameDayAs: tomorrow))
    XCTAssertEqual(Calendar.current.component(.hour, from: tomorrowEvent.startDate), 10)
    XCTAssertFalse(timed.contains { $0.startDate <= now && $0.endDate > now })
  }

  func testFreeDayScenarioKeepsTomorrowEventOnNextCalendarDayLateAtNight() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 23, minute: 50)
    let events = DemoCalendarData.events(now: now, selectedIds: [], scenario: .freeDay)
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!

    guard let tomorrowEvent = events.first(where: { $0.id == "free-day-tomorrow" }) else {
      return XCTFail("Expected the free-day scenario's tomorrow event")
    }
    XCTAssertTrue(tomorrowEvent.startDate > now)
    XCTAssertTrue(calendar.isDate(tomorrowEvent.startDate, inSameDayAs: tomorrow))
    XCTAssertFalse(events.contains { !$0.allDay && $0.startDate <= now && $0.endDate > now })
  }

  func testFreeDayScenarioRendersFreeHeroWhenMenubarHasNoSelection() {
    var config = DemoCalendarData.config()
    config.menubarShowsNextAlways = false
    config.menubarLeadMinutes = 0

    let anchors = [
      makeDate(year: 2026, month: 7, day: 5, hour: 0, minute: 5),
      makeDate(year: 2026, month: 7, day: 5, hour: 10),
      makeDate(year: 2026, month: 7, day: 5, hour: 23, minute: 50)
    ]

    for now in anchors {
      let events = DemoCalendarData.events(now: now, selectedIds: [], scenario: .freeDay)
        .filter { $0.endDate > now }
      let timed = events.filter { !$0.allDay }
      let allDay = events.filter(\.allDay)
      let menubarEvent = AppModel.pickMenubarEvent(
        config: config,
        timed: timed,
        allDay: allDay,
        now: now
      )
      let presentation = AppModel.timelinePresentation(
        menubarEvent: menubarEvent,
        config: config,
        timed: timed,
        now: now,
        coverageEnd: .distantFuture
      )

      XCTAssertTrue(presentation.showsFreeDayHero)
      XCTAssertEqual(presentation.freeDayNextEvent?.id, "free-day-tomorrow")
    }
  }
}
