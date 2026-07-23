import XCTest
@testable import Until

/// Covers demo mode's runtime-option parsing (`--demo-mode` / `--demo-now`)
/// and the opt-in in-progress demo event (`DemoCalendarData.events(includeNowEvent:)`)
/// that lets the popover's in-progress "Up next" hero be demoed without
/// disturbing the default `--demo-mode` composition.
@MainActor
final class DemoCalendarDataTests: XCTestCase {
  // MARK: - AppRuntimeOptions.fromProcess

  func testDemoNowFlagImpliesDemoMode() {
    let options = AppRuntimeOptions.fromProcess(arguments: ["until", "--demo-now"], environment: [:])
    XCTAssertTrue(options.demoMode)
    XCTAssertTrue(options.demoNowEvent)
  }

  func testPlainDemoModeFlagDoesNotEnableNowEvent() {
    let options = AppRuntimeOptions.fromProcess(arguments: ["until", "--demo-mode"], environment: [:])
    XCTAssertTrue(options.demoMode)
    XCTAssertFalse(options.demoNowEvent)
  }

  func testDemoNowEnvVarImpliesDemoMode() {
    let options = AppRuntimeOptions.fromProcess(arguments: ["until"], environment: ["UNTIL_DEMO_NOW": "true"])
    XCTAssertTrue(options.demoMode)
    XCTAssertTrue(options.demoNowEvent)
  }

  // MARK: - Default demo composition (includeNowEvent: false) is unaffected

  // All-day events (e.g. "Launch assets due") are trivially "in progress"
  // for their whole day by design, unrelated to the half-hour anchoring
  // this covers, so only timed events are checked here — those are what
  // feed the popover hero's in-progress state via `pickMenubarEvent`.

  func testDefaultDemoEventsHaveNothingInProgressJustBeforeHalfHourBoundary() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 29)
    let events = DemoCalendarData.events(now: now, selectedIds: [], includeNowEvent: false)
    XCTAssertFalse(events.contains { !$0.allDay && $0.startDate <= now && $0.endDate > now })
  }

  func testDefaultDemoEventsHaveNothingInProgressJustAfterHalfHourBoundary() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 1)
    let events = DemoCalendarData.events(now: now, selectedIds: [], includeNowEvent: false)
    XCTAssertFalse(events.contains { !$0.allDay && $0.startDate <= now && $0.endDate > now })
  }

  // MARK: - includeNowEvent: true adds "launch-standup" in progress

  func testIncludeNowEventAddsInProgressLaunchStandup() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 10, minute: 29)
    let events = DemoCalendarData.events(now: now, selectedIds: [], includeNowEvent: true)
    guard let standup = events.first(where: { $0.id == "launch-standup" }) else {
      XCTFail("Expected launch-standup event when includeNowEvent is true")
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
    let events = DemoCalendarData.events(now: now, selectedIds: [], includeNowEvent: true)
    let timed = events.filter { !$0.allDay }
    let allDay = events.filter(\.allDay)
    let picked = AppModel.pickMenubarEvent(config: DemoCalendarData.config(), timed: timed, allDay: allDay, now: now)
    XCTAssertEqual(picked?.id, "launch-standup")
  }
}
