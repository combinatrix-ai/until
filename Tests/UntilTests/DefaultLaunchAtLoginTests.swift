import XCTest
@testable import Until

final class DefaultLaunchAtLoginTests: XCTestCase {
  func testLegacyConfigDecodesToFalse() throws {
    // JSON without the didApplyDefaultLaunchAtLogin key (an existing install).
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
    XCTAssertFalse(config.didApplyDefaultLaunchAtLogin)
  }

  func testTrueRoundTrips() throws {
    var config = AppConfig.default
    config.didApplyDefaultLaunchAtLogin = true
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
    XCTAssertTrue(decoded.didApplyDefaultLaunchAtLogin)
  }

  func testDecisionAppliesOnlyWhenNotYetApplied() {
    XCTAssertTrue(AppModel.shouldApplyDefaultLaunchAtLogin(alreadyApplied: false))
    XCTAssertFalse(AppModel.shouldApplyDefaultLaunchAtLogin(alreadyApplied: true))
  }
}
