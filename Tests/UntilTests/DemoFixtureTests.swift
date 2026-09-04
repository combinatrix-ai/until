import XCTest
@testable import Until

/// Covers `--demo-json` parsing and the wall-clock resolution that makes a
/// fixture reproducible: the clock decides the moment, so the same file has to
/// produce the same day whenever it is loaded.
final class DemoFixtureTests: XCTestCase {
  private func write(_ json: String) throws -> String {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("demo-fixture-\(UUID().uuidString).json")
    try json.write(to: url, atomically: true, encoding: .utf8)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url.path
  }

  private let minimal = """
  {
    "calendars": [
      { "id": "work", "account": "work@example.com", "name": "Acme Work", "color": "#16a765", "primary": true }
    ],
    "events": [
      { "id": "review", "title": "Design review", "calendar": "work", "start": "10:00", "end": "10:45" }
    ]
  }
  """

  // MARK: - Flag parsing

  func testDemoJsonFlagImpliesDemoMode() {
    let options = AppRuntimeOptions.fromProcess(
      arguments: ["until", "--demo-json", "/tmp/day.json"],
      environment: [:]
    )
    XCTAssertTrue(options.demoMode)
    XCTAssertEqual(options.demoFixturePath, "/tmp/day.json")
  }

  func testDemoJsonAcceptsEqualsForm() {
    let options = AppRuntimeOptions.fromProcess(
      arguments: ["until", "--demo-json=/tmp/day.json"],
      environment: [:]
    )
    XCTAssertEqual(options.demoFixturePath, "/tmp/day.json")
  }

  func testDemoJsonEnvVarIsUsedWhenNoFlagIsGiven() {
    let options = AppRuntimeOptions.fromProcess(
      arguments: ["until"],
      environment: ["UNTIL_DEMO_JSON": "/tmp/env.json"]
    )
    XCTAssertTrue(options.demoMode)
    XCTAssertEqual(options.demoFixturePath, "/tmp/env.json")
  }

  func testFlagWinsOverEnvVar() {
    let options = AppRuntimeOptions.fromProcess(
      arguments: ["until", "--demo-json", "/tmp/flag.json"],
      environment: ["UNTIL_DEMO_JSON": "/tmp/env.json"]
    )
    XCTAssertEqual(options.demoFixturePath, "/tmp/flag.json")
  }

  func testNoFixturePathWithoutFlagOrEnv() {
    let options = AppRuntimeOptions.fromProcess(arguments: ["until", "--demo-mode"], environment: [:])
    XCTAssertNil(options.demoFixturePath)
  }

  // MARK: - Wall-clock resolution

  func testTimesResolveAgainstTheClockNotTheLoadMoment() throws {
    let fixture = try DemoFixture.load(path: try write(minimal))
    let calendar = Calendar.current
    let morning = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 9, minute: 0))
    )
    let evening = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 21, minute: 0))
    )
    for now in [morning, evening] {
      let events = try fixture.calendarEvents(now: now, selectedIds: ["work"])
      let review = try XCTUnwrap(events.first)
      XCTAssertEqual(calendar.component(.hour, from: review.startDate), 10)
      XCTAssertEqual(calendar.component(.minute, from: review.startDate), 0)
      XCTAssertEqual(review.durationMinutes, 45)
    }
  }

  func testDayOffsetPlacesEventsRelativeToTodayNotAFixedDate() throws {
    let json = """
    {
      "calendars": [{ "id": "work", "account": "w@example.com", "name": "W", "color": "#16a765" }],
      "events": [
        { "id": "today", "title": "Today", "calendar": "work", "start": "10:00", "end": "10:30" },
        { "id": "tomorrow", "title": "Tomorrow", "calendar": "work", "day": 1, "start": "10:00", "end": "10:30" }
      ]
    }
    """
    let fixture = try DemoFixture.load(path: try write(json))
    let now = Date()
    let events = try fixture.calendarEvents(now: now, selectedIds: ["work"])
    let calendar = Calendar.current
    let today = try XCTUnwrap(events.first { $0.id == "today" })
    let tomorrow = try XCTUnwrap(events.first { $0.id == "tomorrow" })
    XCTAssertTrue(calendar.isDate(today.startDate, inSameDayAs: now))
    XCTAssertEqual(calendar.dateComponents([.day], from: today.startDate, to: tomorrow.startDate).day, 1)
  }

  func testAllDayEventSpansWholeDaysAndDefaultsToOne() throws {
    let json = """
    {
      "calendars": [{ "id": "p", "account": "p@example.com", "name": "P", "color": "#5484ed" }],
      "events": [
        { "id": "holiday", "title": "Company holiday", "calendar": "p", "allDay": true },
        { "id": "offsite", "title": "Offsite", "calendar": "p", "allDay": true, "days": 3 }
      ]
    }
    """
    let fixture = try DemoFixture.load(path: try write(json))
    let events = try fixture.calendarEvents(now: Date(), selectedIds: ["p"])
    let holiday = try XCTUnwrap(events.first { $0.id == "holiday" })
    let offsite = try XCTUnwrap(events.first { $0.id == "offsite" })
    XCTAssertTrue(holiday.allDay)
    XCTAssertEqual(holiday.durationMinutes, 24 * 60)
    XCTAssertEqual(offsite.durationMinutes, 3 * 24 * 60)
  }

  func testEndBeforeStartRollsToTheNextDay() throws {
    let json = """
    {
      "calendars": [{ "id": "w", "account": "w@example.com", "name": "W", "color": "#16a765" }],
      "events": [
        { "id": "late", "title": "Late call", "calendar": "w", "start": "23:30", "end": "00:15" }
      ]
    }
    """
    let fixture = try DemoFixture.load(path: try write(json))
    let event = try XCTUnwrap(try fixture.calendarEvents(now: Date(), selectedIds: ["w"]).first)
    XCTAssertEqual(event.durationMinutes, 45)
  }

  func testUnselectedCalendarsAreExcluded() throws {
    let fixture = try DemoFixture.load(path: try write(minimal))
    XCTAssertTrue(try fixture.calendarEvents(now: Date(), selectedIds: []).isEmpty)
  }

  func testSelectedFlagDrivesTheDefaultSelection() throws {
    let json = """
    {
      "calendars": [
        { "id": "a", "account": "x@example.com", "name": "A", "color": "#111111" },
        { "id": "b", "account": "x@example.com", "name": "B", "color": "#222222", "selected": false }
      ],
      "events": []
    }
    """
    let fixture = try DemoFixture.load(path: try write(json))
    XCTAssertEqual(fixture.appConfig(base: .default).selectedCalendarIds, ["a"])
  }

  func testConfigOverridesApplyOnTopOfTheBase() throws {
    let json = """
    {
      "config": { "menubarLeadMinutes": 15, "notifyEnabled": true },
      "calendars": [{ "id": "w", "account": "w@example.com", "name": "W", "color": "#16a765" }],
      "events": []
    }
    """
    let fixture = try DemoFixture.load(path: try write(json))
    var base = AppConfig.default
    base.lookaheadHours = 72
    let resolved = fixture.appConfig(base: base)
    XCTAssertEqual(resolved.menubarLeadMinutes, 15)
    XCTAssertTrue(resolved.notifyEnabled)
    XCTAssertEqual(resolved.lookaheadHours, 72, "untouched keys keep the base value")
  }

  func testAccountsAreDerivedFromCalendarsInOrderWithoutDuplicates() throws {
    let json = """
    {
      "calendars": [
        { "id": "a", "account": "one@example.com", "name": "A", "color": "#111111" },
        { "id": "b", "account": "two@example.com", "name": "B", "color": "#222222" },
        { "id": "c", "account": "one@example.com", "name": "C", "color": "#333333" }
      ],
      "events": []
    }
    """
    let fixture = try DemoFixture.load(path: try write(json))
    XCTAssertEqual(fixture.accountEmails(), ["one@example.com", "two@example.com"])
  }

  func testAttendeesGainASelfEntryOnlyWhenOthersArePresent() throws {
    let json = """
    {
      "calendars": [{ "id": "w", "account": "me@example.com", "name": "W", "color": "#16a765" }],
      "events": [
        { "id": "solo", "title": "Solo", "calendar": "w", "start": "09:00", "end": "09:30" },
        {
          "id": "group", "title": "Group", "calendar": "w", "start": "10:00", "end": "10:30",
          "attendees": [{ "email": "other@example.com", "name": "Other" }]
        }
      ]
    }
    """
    let fixture = try DemoFixture.load(path: try write(json))
    let events = try fixture.calendarEvents(now: Date(), selectedIds: ["w"])
    let solo = try XCTUnwrap(events.first { $0.id == "solo" })
    let group = try XCTUnwrap(events.first { $0.id == "group" })
    XCTAssertTrue(solo.attendees.isEmpty)
    XCTAssertEqual(group.attendees.count, 2)
    XCTAssertEqual(group.attendees.first?.email, "me@example.com")
    XCTAssertTrue(try XCTUnwrap(group.attendees.first).selfUser)
  }

  // MARK: - Failures stop the run

  func testUnknownCalendarReferenceThrows() throws {
    let json = """
    {
      "calendars": [{ "id": "w", "account": "w@example.com", "name": "W", "color": "#16a765" }],
      "events": [{ "id": "x", "title": "X", "calendar": "nope", "start": "10:00", "end": "10:30" }]
    }
    """
    let fixture = try DemoFixture.load(path: try write(json))
    XCTAssertThrowsError(try fixture.calendarEvents(now: Date(), selectedIds: ["w"]))
  }

  func testUnparseableTimeThrows() throws {
    let json = """
    {
      "calendars": [{ "id": "w", "account": "w@example.com", "name": "W", "color": "#16a765" }],
      "events": [{ "id": "x", "title": "X", "calendar": "w", "start": "25:00", "end": "10:30" }]
    }
    """
    let fixture = try DemoFixture.load(path: try write(json))
    XCTAssertThrowsError(try fixture.calendarEvents(now: Date(), selectedIds: ["w"]))
  }

  func testTimedEventWithoutTimesThrows() throws {
    let json = """
    {
      "calendars": [{ "id": "w", "account": "w@example.com", "name": "W", "color": "#16a765" }],
      "events": [{ "id": "x", "title": "X", "calendar": "w" }]
    }
    """
    let fixture = try DemoFixture.load(path: try write(json))
    XCTAssertThrowsError(try fixture.calendarEvents(now: Date(), selectedIds: ["w"]))
  }

  func testMissingFileThrows() {
    XCTAssertThrowsError(try DemoFixture.load(path: "/tmp/definitely-not-here-\(UUID().uuidString).json"))
  }

  // MARK: - The shipped example must stay loadable

  func testShippedExampleFixtureLoadsAndResolves() throws {
    let path = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("scripts/demo-data-example.json")
      .path
    let fixture = try DemoFixture.load(path: path)
    let config = fixture.appConfig(base: .default)
    let events = try fixture.calendarEvents(now: Date(), selectedIds: config.selectedCalendarIds)
    XCTAssertFalse(events.isEmpty)
    XCTAssertEqual(fixture.accountEmails().count, 2)
    XCTAssertTrue(events.contains { $0.id == "design-review" && !$0.conferenceUrl.isEmpty })
  }
}
