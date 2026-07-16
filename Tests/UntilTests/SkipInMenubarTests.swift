import XCTest
@testable import Until

/// Covers "Skip in menubar": hiding a single event from the menubar
/// countdown (`AppModel.pickMenubarEvent`) without touching the popover
/// list, plus the `AppConfig.skippedMenubarEvents` persistence and its
/// automatic expiry purge.
@MainActor
final class SkipInMenubarTests: XCTestCase {
  // MARK: - pickMenubarEvent (pure, deterministic — same style as GroupByDayTests)

  func testSkippedNextEventIsNotPickedAndFollowingEventIsPickedInstead() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    let e1Start = now.addingTimeInterval(10 * 60)
    let e2Start = now.addingTimeInterval(70 * 60)
    let e1 = makeEvent(
      id: "e1", startISO: isoString(from: e1Start), endISO: isoString(from: e1Start.addingTimeInterval(30 * 60))
    )
    let e2 = makeEvent(
      id: "e2", startISO: isoString(from: e2Start), endISO: isoString(from: e2Start.addingTimeInterval(30 * 60))
    )

    // Baseline: with nothing skipped, the sooner event (e1) is picked.
    let baseline = AppModel.pickMenubarEvent(config: .default, timed: [e1, e2], allDay: [], now: now)
    XCTAssertEqual(baseline?.id, "e1")

    // Skip e1: e2 should be picked instead.
    var config = AppConfig.default
    config.skippedMenubarEvents[e1.actionKey] = e1.endDate
    let picked = AppModel.pickMenubarEvent(config: config, timed: [e1, e2], allDay: [], now: now)
    XCTAssertEqual(picked?.id, "e2")
  }

  func testUnskipRestoresEventToMenubarConsideration() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    let e1Start = now.addingTimeInterval(10 * 60)
    let e2Start = now.addingTimeInterval(70 * 60)
    let e1 = makeEvent(
      id: "e1", startISO: isoString(from: e1Start), endISO: isoString(from: e1Start.addingTimeInterval(30 * 60))
    )
    let e2 = makeEvent(
      id: "e2", startISO: isoString(from: e2Start), endISO: isoString(from: e2Start.addingTimeInterval(30 * 60))
    )

    var config = AppConfig.default
    config.skippedMenubarEvents[e1.actionKey] = e1.endDate
    XCTAssertEqual(AppModel.pickMenubarEvent(config: config, timed: [e1, e2], allDay: [], now: now)?.id, "e2")

    // Unskip (i.e. remove the entry) restores e1 as the picked event.
    config.skippedMenubarEvents.removeValue(forKey: e1.actionKey)
    XCTAssertEqual(AppModel.pickMenubarEvent(config: config, timed: [e1, e2], allDay: [], now: now)?.id, "e1")
  }

  func testSkippingAppliesToAllDayCandidatesToo() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    let start = makeDate(year: 2026, month: 7, day: 5)
    let end = makeDate(year: 2026, month: 7, day: 6)
    let allDayEvent = makeEvent(id: "holiday", startISO: isoString(from: start), endISO: isoString(from: end), allDay: true)

    // With no timed events "current", the all-day event would otherwise be picked.
    let baseline = AppModel.pickMenubarEvent(config: .default, timed: [], allDay: [allDayEvent], now: now)
    XCTAssertEqual(baseline?.id, "holiday")

    var config = AppConfig.default
    config.skippedMenubarEvents[allDayEvent.actionKey] = allDayEvent.endDate
    let picked = AppModel.pickMenubarEvent(config: config, timed: [], allDay: [allDayEvent], now: now)
    XCTAssertNil(picked)
  }

  // MARK: - Expiry purge

  func testExpiredSkipEntriesArePurged() {
    let now = makeDate(year: 2026, month: 7, day: 5, hour: 8)
    var config = AppConfig.default
    config.skippedMenubarEvents = [
      "stale::key::1": now.addingTimeInterval(-3600), // ended an hour ago -> purged
      "fresh::key::2": now.addingTimeInterval(3600) // still ongoing/upcoming -> kept
    ]

    let purged = AppModel.purgingExpiredSkips(config, now: now)

    XCTAssertNil(purged.skippedMenubarEvents["stale::key::1"])
    XCTAssertNotNil(purged.skippedMenubarEvents["fresh::key::2"])
  }

  // MARK: - AppConfig persistence

  func testLegacyConfigDecodesSkippedMenubarEventsToEmpty() throws {
    // JSON without the skippedMenubarEvents key (an existing install).
    let json = """
    {
      "oauth": { "clientId": "id" },
      "filterRules": { "kind": "group", "groupOperator": "and", "negate": false, "children": [] },
      "selectedCalendarIds": [],
      "lookaheadHours": 24,
      "pollIntervalSeconds": 120,
      "maxTitleLength": 40,
      "menubarLeadMinutes": 720,
      "menubarShowsNextAlways": true,
      "notifyEnabled": true,
      "notifyVideoOnly": false,
      "notifyLeadMinutes": 5,
      "hotkeyEnabled": false,
      "hotkeyPreset": "ctrl-opt-u",
      "meetingNotesFoldersByAccount": {},
      "meetingNotesFolderNamesByAccount": {},
      "meetingNotesTitleTemplatesByAccount": {},
      "meetingNotesTemplateDocsByAccount": {}
    }
    """
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    XCTAssertEqual(config.skippedMenubarEvents, [:])
  }

  func testSkippedMenubarEventsRoundTrips() throws {
    var config = AppConfig.default
    let endDate = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    config.skippedMenubarEvents = ["me@example.com::cal-1::event-1": endDate]
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    XCTAssertEqual(decoded.skippedMenubarEvents.keys.first, "me@example.com::cal-1::event-1")
    XCTAssertEqual(
      decoded.skippedMenubarEvents["me@example.com::cal-1::event-1"]?.timeIntervalSince1970 ?? -1,
      endDate.timeIntervalSince1970,
      accuracy: 0.001
    )
  }

  // MARK: - AppModel skip/unskip (demo mode, live instance)

  @MainActor
  func testSkipUnskipUpdateModelStateAndPopoverListStaysIntact() {
    let model = AppModel(options: AppRuntimeOptions(demoMode: true))
    guard let event = model.state.events.first else {
      XCTFail("Demo data should seed at least one timed event")
      return
    }

    XCTAssertFalse(model.isSkippedInMenubar(event))

    model.skipInMenubar(event)
    XCTAssertTrue(model.isSkippedInMenubar(event))
    // The popover event list is untouched by a menubar skip.
    XCTAssertTrue(model.state.events.contains { $0.actionKey == event.actionKey })

    model.unskipInMenubar(event)
    XCTAssertFalse(model.isSkippedInMenubar(event))
    XCTAssertTrue(model.state.events.contains { $0.actionKey == event.actionKey })
  }

  @MainActor
  func testSkipInMenubarPurgesStaleEntriesFromConfig() {
    let model = AppModel(options: AppRuntimeOptions(demoMode: true))
    guard let event = model.state.events.first else {
      XCTFail("Demo data should seed at least one timed event")
      return
    }
    model.config.skippedMenubarEvents["gone::stale::0"] = Date().addingTimeInterval(-86400)

    model.skipInMenubar(event)

    XCTAssertNil(model.config.skippedMenubarEvents["gone::stale::0"])
    XCTAssertNotNil(model.config.skippedMenubarEvents[event.actionKey])
  }
}
