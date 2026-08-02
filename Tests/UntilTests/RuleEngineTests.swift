import XCTest
@testable import Until

final class RuleEngineTests: XCTestCase {

  // MARK: - String operators

  func testContainsIsCaseInsensitive() {
    let event = makeEvent(title: "Weekly SYNC Meeting")
    let rule = Rule.condition("title", "contains", .string("sync"))
    XCTAssertTrue(RuleEngine.evaluate(rule, event: event))
  }

  func testNotContains() {
    let event = makeEvent(title: "Weekly Sync")
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "not_contains", .string("sync")), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "not_contains", .string("standup")), event: event))
  }

  func testStartsWith() {
    let event = makeEvent(title: "Daily Standup")
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "starts_with", .string("daily")), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "starts_with", .string("weekly")), event: event))
  }

  func testEndsWith() {
    let event = makeEvent(title: "Daily Standup")
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "ends_with", .string("STANDUP")), event: event))
  }

  func testEqualsIsCaseInsensitive() {
    let event = makeEvent(title: "Standup")
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "equals", .string("Standup")), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "equals", .string("standup")), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "equals", .string("other")), event: event))
  }

  func testNotEquals() {
    let event = makeEvent(title: "Standup")
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "not_equals", .string("Standup")), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "not_equals", .string("standup")), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "not_equals", .string("Other")), event: event))
  }

  func testMatchesRegexIsCaseInsensitive() {
    let event = makeEvent(title: "Q3 Planning Review")
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "matches", .string("^q3.*review$")), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "matches", .string("^q4")), event: event))
  }

  func testIsEmptyAndIsNotEmptyString() {
    let empty = makeEvent(description: "")
    let filled = makeEvent(description: "notes here")
    XCTAssertTrue(RuleEngine.evaluate(.condition("description", "is_empty"), event: empty))
    XCTAssertFalse(RuleEngine.evaluate(.condition("description", "is_empty"), event: filled))
    XCTAssertTrue(RuleEngine.evaluate(.condition("description", "is_not_empty"), event: filled))
    XCTAssertFalse(RuleEngine.evaluate(.condition("description", "is_not_empty"), event: empty))
  }

  // MARK: - Enum operators (selfResponse/status/transparency)

  func testEnumIsAndIsNot() {
    let event = makeEvent(selfResponse: "accepted")
    XCTAssertTrue(RuleEngine.evaluate(.condition("selfResponse", "is", .string("accepted")), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("selfResponse", "is", .string("declined")), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("selfResponse", "is_not", .string("declined")), event: event))
  }

  func testEnumIsAnyOfAndIsNoneOf() {
    let event = makeEvent(status: "confirmed")
    XCTAssertTrue(RuleEngine.evaluate(.condition("status", "is_any_of", .strings(["confirmed", "tentative"])), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("status", "is_any_of", .strings(["cancelled"])), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("status", "is_none_of", .strings(["cancelled"])), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("status", "is_none_of", .strings(["confirmed"])), event: event))
  }

  func testEnumIsEmptyAndIsSet() {
    let event = makeEvent(transparency: "busy")
    XCTAssertFalse(RuleEngine.evaluate(.condition("transparency", "is_empty"), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("transparency", "is_set"), event: event))
  }

  // MARK: - Bool fields

  func testAllDayIsTrueIsFalse() {
    let allDay = makeEvent(allDay: true)
    let timed = makeEvent(allDay: false)
    XCTAssertTrue(RuleEngine.evaluate(.condition("allDay", "is_true"), event: allDay))
    XCTAssertFalse(RuleEngine.evaluate(.condition("allDay", "is_true"), event: timed))
    XCTAssertTrue(RuleEngine.evaluate(.condition("allDay", "is_false"), event: timed))
  }

  func testIsRecurring() {
    let recurring = makeEvent(isRecurring: true)
    let single = makeEvent(isRecurring: false)
    XCTAssertTrue(RuleEngine.evaluate(.condition("isRecurring", "is_true"), event: recurring))
    XCTAssertTrue(RuleEngine.evaluate(.condition("isRecurring", "is_false"), event: single))
  }

  func testHasVideoDerivedFromConferenceUrl() {
    let withVideo = makeEvent(conferenceUrl: "https://meet.google.com/abc-defg-hij")
    let withoutVideo = makeEvent(conferenceUrl: "")
    XCTAssertTrue(RuleEngine.evaluate(.condition("hasVideo", "is_true"), event: withVideo))
    XCTAssertFalse(RuleEngine.evaluate(.condition("hasVideo", "is_true"), event: withoutVideo))
    XCTAssertTrue(RuleEngine.evaluate(.condition("hasVideo", "is_false"), event: withoutVideo))
  }

  // MARK: - Number operators

  func testNumberComparisons() {
    let event = makeEvent(durationMinutes: 30)
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "lt", .number(60)), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "lt", .number(30)), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "lte", .number(30)), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "gt", .number(10)), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "gt", .number(30)), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "gte", .number(30)), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "eq", .number(30)), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "neq", .number(31)), event: event))
  }

  func testAttendeeCountNumberField() {
    let event = makeEvent(attendees: [
      Attendee(email: "me@example.com", name: "Me", responseStatus: "accepted", selfUser: true, resource: false),
      Attendee(email: "guest@example.com", name: "Guest", responseStatus: "accepted", selfUser: false, resource: false),
      Attendee(email: "room@example.com", name: "Room", responseStatus: "accepted", selfUser: false, resource: true)
    ])
    // The self attendee counts, while resource attendees do not.
    XCTAssertTrue(RuleEngine.evaluate(.condition("attendeeCount", "eq", .number(2)), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("attendeeCount", "gte", .number(2)), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("attendeeCount", "gt", .number(2)), event: event))
  }

  func testBetweenAndNotBetween() {
    let event = makeEvent(durationMinutes: 45)
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "between", .numbers([30, 60])), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "between", .numbers([50, 60])), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "not_between", .numbers([30, 60])), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "not_between", .numbers([50, 60])), event: event))
  }

  /// Inverted ranges are malformed and therefore fail closed for both
  /// operators.
  func testBetweenWithInvertedBoundsFailsClosed() {
    let event = makeEvent(durationMinutes: 45)
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "between", .numbers([60, 30])), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "not_between", .numbers([60, 30])), event: event))
  }

  /// Malformed ranges fail closed for both range operators.
  func testBetweenWithMissingBoundFailsClosed() {
    let event = makeEvent(durationMinutes: 999)
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "between", .number(30)), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "not_between", .number(30)), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "between", .numbers([])), event: event))
  }

  // MARK: - Special fields

  func testStartsWithinRequiresNonNegativeAndWithinValue() {
    // startMinutesFromNow >= 0 && <= value.number
    let soon = makeEvent(startMinutesFromNow: 10)
    let past = makeEvent(startMinutesFromNow: -5)
    let far = makeEvent(startMinutesFromNow: 120)
    XCTAssertTrue(RuleEngine.evaluate(.condition("startsWithin", "within", .number(30)), event: soon))
    XCTAssertFalse(RuleEngine.evaluate(.condition("startsWithin", "within", .number(30)), event: past))
    XCTAssertFalse(RuleEngine.evaluate(.condition("startsWithin", "within", .number(30)), event: far))
    // Boundary: exactly equal to value passes (<=).
    let boundary = makeEvent(startMinutesFromNow: 30)
    XCTAssertTrue(RuleEngine.evaluate(.condition("startsWithin", "within", .number(30)), event: boundary))
  }

  func testHourFieldUsesEventStartDateComponent() {
    // 2026-07-05T15:30:00Z in whatever local calendar; derive the expected
    // hour the same way the source does, so this test is timezone-agnostic.
    let start = makeDate(year: 2026, month: 7, day: 5, hour: 15, minute: 30)
    let event = makeEvent(startISO: isoString(from: start), endISO: isoString(from: start.addingTimeInterval(3600)))
    let expectedHour = Calendar.current.component(.hour, from: start)
    XCTAssertTrue(RuleEngine.evaluate(.condition("hour", "eq", .number(Double(expectedHour))), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("hour", "eq", .number(Double((expectedHour + 1) % 24))), event: event))
  }

  /// Source: `Calendar.current.component(.weekday, from: event.startDate) - 1`.
  /// `.weekday` is 1-based with Sunday == 1, so after the `- 1` offset,
  /// Sunday == 0, Monday == 1, ... Saturday == 6. Compared via `compareEnum`
  /// against a String, so the rule value must be `.string`.
  func testWeekdayFieldZeroBasedWithSundayZero() {
    // 2026-07-05 is a Sunday.
    let sunday = makeDate(year: 2026, month: 7, day: 5, hour: 9)
    let sundayEvent = makeEvent(startISO: isoString(from: sunday), endISO: isoString(from: sunday.addingTimeInterval(3600)))
    let expectedWeekday = Calendar.current.component(.weekday, from: sunday) - 1
    XCTAssertTrue(RuleEngine.evaluate(.condition("weekday", "is", .string(String(expectedWeekday))), event: sundayEvent))

    // 2026-07-06 is a Monday.
    let monday = makeDate(year: 2026, month: 7, day: 6, hour: 9)
    let mondayEvent = makeEvent(startISO: isoString(from: monday), endISO: isoString(from: monday.addingTimeInterval(3600)))
    let expectedMonday = Calendar.current.component(.weekday, from: monday) - 1
    XCTAssertTrue(RuleEngine.evaluate(.condition("weekday", "is", .string(String(expectedMonday))), event: mondayEvent))
    XCTAssertNotEqual(expectedWeekday, expectedMonday)
  }

  func testAttendeeContainsAndExcludesMatchesEmailSubstringLowercased() {
    let event = makeEvent(attendees: [
      Attendee(email: "Alice@Example.com", name: "Alice", responseStatus: "accepted", selfUser: false, resource: false)
    ])
    XCTAssertTrue(RuleEngine.evaluate(.condition("attendee", "includes", .string("alice")), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("attendee", "includes", .string("EXAMPLE.COM")), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("attendee", "includes", .string("bob")), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("attendee", "excludes", .string("alice")), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("attendee", "excludes", .string("bob")), event: event))
  }

  // MARK: - Calendar field

  func testCalendarIsAndIsAnyOf() {
    let calRef = CalendarRef(id: "key-1", googleId: "google-1", primary: true, backgroundColor: "#fff")
    let event = makeEvent(calendar: calRef)
    XCTAssertTrue(RuleEngine.evaluate(.condition("calendar", "is", .string("key-1")), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("calendar", "is", .string("google-1")), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.condition("calendar", "is", .string("other")), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("calendar", "is_any_of", .strings(["other", "google-1"])), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.condition("calendar", "is_none_of", .strings(["other"])), event: event))
  }

  // MARK: - Groups

  func testGroupAndSemanticsIsAllSatisfy() {
    let event = makeEvent(title: "Sync", allDay: false)
    let rule = Rule.group(.and, [
      .condition("title", "contains", .string("sync")),
      .condition("allDay", "is_false")
    ])
    XCTAssertTrue(RuleEngine.evaluate(rule, event: event))

    let failing = Rule.group(.and, [
      .condition("title", "contains", .string("sync")),
      .condition("allDay", "is_true")
    ])
    XCTAssertFalse(RuleEngine.evaluate(failing, event: event))
  }

  func testGroupOrSemanticsIsAny() {
    let event = makeEvent(title: "Sync", allDay: false)
    let rule = Rule.group(.any, [
      .condition("title", "contains", .string("standup")),
      .condition("allDay", "is_false")
    ])
    XCTAssertTrue(RuleEngine.evaluate(rule, event: event))

    let failing = Rule.group(.any, [
      .condition("title", "contains", .string("standup")),
      .condition("allDay", "is_true")
    ])
    XCTAssertFalse(RuleEngine.evaluate(failing, event: event))
  }

  func testEmptyGroupReturnsTrue() {
    let event = makeEvent()
    XCTAssertTrue(RuleEngine.evaluate(.group(.and, []), event: event))
    XCTAssertTrue(RuleEngine.evaluate(.group(.any, []), event: event))
  }

  /// An empty group evaluates to `true`, and `negate` is applied to that
  /// result like any other rule, so a negated empty group is `false`.
  func testNegatedEmptyGroupReturnsFalse() {
    let event = makeEvent()
    XCTAssertFalse(RuleEngine.evaluate(.group(.and, [], negate: true), event: event))
    XCTAssertFalse(RuleEngine.evaluate(.group(.any, [], negate: true), event: event))
  }

  func testNegateOnGroup() {
    let event = makeEvent(title: "Sync")
    let rule = Rule.group(.and, [.condition("title", "contains", .string("sync"))], negate: true)
    XCTAssertFalse(RuleEngine.evaluate(rule, event: event))
  }

  func testNegateOnCondition() {
    let event = makeEvent(title: "Sync")
    let rule = Rule.condition("title", "contains", .string("sync"), negate: true)
    XCTAssertFalse(RuleEngine.evaluate(rule, event: event))
  }

  func testNestedGroups() {
    let attendees = (0..<3).map { index in
      Attendee(
        email: "guest\(index)@example.com",
        name: "Guest \(index)",
        responseStatus: "accepted",
        selfUser: false,
        resource: false
      )
    }
    let event = makeEvent(title: "Sync", allDay: false, attendees: attendees)
    // (title contains "sync" AND allDay is_false) OR (attendeeCount gt 100)
    let rule = Rule.group(.any, [
      .group(.and, [
        .condition("title", "contains", .string("sync")),
        .condition("allDay", "is_false")
      ]),
      .condition("attendeeCount", "gt", .number(100))
    ])
    XCTAssertTrue(RuleEngine.evaluate(rule, event: event))

    let event2 = makeEvent(title: "Other", allDay: true, attendees: attendees)
    XCTAssertFalse(RuleEngine.evaluate(rule, event: event2))
  }

  // MARK: - Unknown field / operator: fail closed

  func testUnknownFieldReturnsFalse() {
    let event = makeEvent()
    XCTAssertFalse(RuleEngine.evaluate(.condition("madeUpField", "equals", .string("x")), event: event))
  }

  func testUnknownOperatorReturnsFalse() {
    let event = makeEvent(title: "Sync")
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "made_up_operator", .string("x")), event: event))
    let numEvent = makeEvent(durationMinutes: 10)
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "made_up_operator", .number(5)), event: numEvent))
  }

  // MARK: - Rule validation

  func testInvalidRegexIsRejected() {
    XCTAssertEqual(
      RuleValidator.validate(.condition("title", "matches", .string("["))),
      .invalidRegex
    )
  }

  func testEmptyRegexMatchesEveryString() {
    let event = makeEvent(title: "Any title")
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "matches", .string("")), event: event))
  }

  func testNumberValidationRejectsNonFiniteAndInvertedRanges() {
    XCTAssertEqual(
      RuleValidator.validate(.condition("durationMinutes", "eq", .number(.infinity))),
      .nonFiniteNumber
    )
    XCTAssertEqual(
      RuleValidator.validate(.condition("durationMinutes", "between", .numbers([60, 30]))),
      .invalidNumberRange
    )
  }

  func testMalformedGroupIsRejected() {
    let malformed = Rule(
      kind: .group,
      groupOperator: nil,
      children: [.condition("title", "contains", .string("sync"))]
    )
    XCTAssertEqual(RuleValidator.validate(malformed), .malformedGroup)
  }

  func testFilterCatalogDefaultsMatchValidatorContract() {
    for field in FilterCatalog.fields {
      for filterOperator in field.operators {
        let rule = Rule.condition(
          field.id,
          filterOperator.id,
          FilterCatalog.defaultValue(for: filterOperator.value)
        )
        let validationError = RuleValidator.validate(rule)
        if field.id == "calendar", case .calendars = filterOperator.value {
          // The editor intentionally starts a single-calendar picker at its
          // incomplete "Choose calendar" placeholder.
          XCTAssertEqual(validationError, .invalidChoice, "\(field.id).\(filterOperator.id)")
        } else {
          XCTAssertNil(validationError, "\(field.id).\(filterOperator.id)")
        }
      }
    }
  }

  func testEmptySingleCalendarSelectionIsRejected() {
    XCTAssertEqual(
      RuleValidator.validate(.condition("calendar", "is", .string(""))),
      .invalidChoice
    )
    XCTAssertNil(
      RuleValidator.validate(.condition("calendar", "is", .string("calendar-id")))
    )
  }

  func testRuleEngineApplyFiltersEvents() {
    let matching = makeEvent(id: "a", title: "Sync")
    let nonMatching = makeEvent(id: "b", title: "Other")
    let rule = Rule.condition("title", "contains", .string("sync"))
    let result = RuleEngine.apply(rule, to: [matching, nonMatching])
    XCTAssertEqual(result.map(\.id), ["a"])
  }
}
