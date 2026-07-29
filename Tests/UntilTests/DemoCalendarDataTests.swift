import XCTest
@testable import Until

/// Covers demo mode's runtime-option parsing (`--demo-mode` / `--demo-now` /
/// `--demo-overlap`) and the opt-in demo scenarios
/// (`DemoCalendarData.events(scenario:)`) that let the popover's in-progress
/// "Now" hero and NOW strip be demoed without disturbing the default
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

  // MARK: - scenario: .overlap pins the exact state the README NOW-strip capture needs

  func testOverlapScenarioPinsMenubarOnDesignReviewAndStripOnLaunchStandup() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 29)
    // Mirrors AppModel.reapplyFilter's split (non-allDay, endDate > now) so
    // this exercises the same shape the popover actually renders.
    let events = DemoCalendarData.events(now: now, selectedIds: [], scenario: .overlap)
      .filter { $0.endDate > now }
    let timed = events.filter { !$0.allDay }
    let allDay = events.filter(\.allDay)
    let config = DemoCalendarData.config()

    let menubarEvent = AppModel.pickMenubarEvent(config: config, timed: timed, allDay: allDay, now: now)
    XCTAssertEqual(menubarEvent?.id, "design-review")

    let stripEvent = AppModel.pickNowStripEvent(menubarEvent: menubarEvent, config: config, timed: timed, now: now)
    XCTAssertEqual(stripEvent?.id, "launch-standup")
  }
}
