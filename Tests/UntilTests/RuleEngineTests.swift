import XCTest
@testable import Until

final class RuleEngineTests: XCTestCase {
  let now = makeDate(year: 2026, month: 7, day: 5, hour: 12, minute: 0)

  // MARK: - String operators

  func testContainsIsCaseInsensitive() {
    let event = makeEvent(title: "Weekly SYNC Meeting")
    let rule = Rule.condition("title", "contains", .string("sync"))
    XCTAssertTrue(RuleEngine.evaluate(rule, event: event, now: now))
  }

  func testNotContains() {
    let event = makeEvent(title: "Weekly Sync")
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "not_contains", .string("sync")), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "not_contains", .string("standup")), event: event, now: now))
  }

  func testStartsWith() {
    let event = makeEvent(title: "Daily Standup")
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "starts_with", .string("daily")), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "starts_with", .string("weekly")), event: event, now: now))
  }

  func testEndsWith() {
    let event = makeEvent(title: "Daily Standup")
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "ends_with", .string("STANDUP")), event: event, now: now))
  }

  func testEqualsIsCaseInsensitive() {
    let event = makeEvent(title: "Standup")
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "equals", .string("Standup")), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "equals", .string("standup")), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "equals", .string("other")), event: event, now: now))
  }

  func testNotEquals() {
    let event = makeEvent(title: "Standup")
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "not_equals", .string("Standup")), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "not_equals", .string("standup")), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "not_equals", .string("Other")), event: event, now: now))
  }

  func testMatchesRegexIsCaseInsensitive() {
    let event = makeEvent(title: "Q3 Planning Review")
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "matches", .string("^q3.*review$")), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("title", "matches", .string("^q4")), event: event, now: now))
  }

  func testIsEmptyAndIsNotEmptyString() {
    let empty = makeEvent(description: "")
    let filled = makeEvent(description: "notes here")
    XCTAssertTrue(RuleEngine.evaluate(.condition("description", "is_empty"), event: empty, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("description", "is_empty"), event: filled, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("description", "is_not_empty"), event: filled, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("description", "is_not_empty"), event: empty, now: now))
  }

  // MARK: - Enum operators (selfResponse/status/transparency)

  func testEnumIsAndIsNot() {
    let event = makeEvent(selfResponse: "accepted")
    XCTAssertTrue(RuleEngine.evaluate(.condition("selfResponse", "is", .string("accepted")), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("selfResponse", "is", .string("declined")), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("selfResponse", "is_not", .string("declined")), event: event, now: now))
  }

  func testEnumIsAnyOfAndIsNoneOf() {
    let event = makeEvent(status: "confirmed")
    XCTAssertTrue(RuleEngine.evaluate(.condition("status", "is_any_of", .strings(["confirmed", "tentative"])), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("status", "is_any_of", .strings(["cancelled"])), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("status", "is_none_of", .strings(["cancelled"])), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("status", "is_none_of", .strings(["confirmed"])), event: event, now: now))
  }

  func testEnumIsEmptyAndIsSet() {
    let event = makeEvent(transparency: "busy")
    XCTAssertFalse(RuleEngine.evaluate(.condition("transparency", "is_empty"), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("transparency", "is_set"), event: event, now: now))
  }

  // MARK: - Bool fields

  func testAllDayIsTrueIsFalse() {
    let allDay = makeEvent(allDay: true)
    let timed = makeEvent(allDay: false)
    XCTAssertTrue(RuleEngine.evaluate(.condition("allDay", "is_true"), event: allDay, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("allDay", "is_true"), event: timed, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("allDay", "is_false"), event: timed, now: now))
  }

  func testIsRecurring() {
    let recurring = makeEvent(isRecurring: true)
    let single = makeEvent(isRecurring: false)
    XCTAssertTrue(RuleEngine.evaluate(.condition("isRecurring", "is_true"), event: recurring, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("isRecurring", "is_false"), event: single, now: now))
  }

  func testHasVideoDerivedFromConferenceUrl() {
    let withVideo = makeEvent(conferenceUrl: "https://meet.google.com/abc-defg-hij")
    let withoutVideo = makeEvent(conferenceUrl: "")
    XCTAssertTrue(RuleEngine.evaluate(.condition("hasVideo", "is_true"), event: withVideo, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("hasVideo", "is_true"), event: withoutVideo, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("hasVideo", "is_false"), event: withoutVideo, now: now))
  }

  // MARK: - Number operators

  func testNumberComparisons() {
    let event = makeEvent(durationMinutes: 30)
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "lt", .number(60)), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "lt", .number(30)), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "lte", .number(30)), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "gt", .number(10)), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "gt", .number(30)), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "gte", .number(30)), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "eq", .number(30)), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "neq", .number(31)), event: event, now: now))
  }

  func testAttendeeCountNumberField() {
    let event = makeEvent(attendeeCount: 5)
    XCTAssertTrue(RuleEngine.evaluate(.condition("attendeeCount", "gte", .number(5)), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("attendeeCount", "gt", .number(5)), event: event, now: now))
  }

  func testBetweenAndNotBetween() {
    let event = makeEvent(durationMinutes: 45)
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "between", .numbers([30, 60])), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "between", .numbers([50, 60])), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "not_between", .numbers([30, 60])), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "not_between", .numbers([50, 60])), event: event, now: now))
  }

  /// `compareRange` does `guard bounds.count == 2 else { return true }`. With
  /// min > max (e.g. [60, 30]) there are still exactly 2 bounds, so it proceeds
  /// to the actual inequality check: `actual >= 60 && actual <= 30`, which is
  /// never satisfiable -> `isInside` is always false -> "between" is always
  /// false and "not_between" is always true, regardless of `actual`.
  func testBetweenWithInvertedBoundsIsAlwaysFalse() {
    let event = makeEvent(durationMinutes: 45)
    XCTAssertFalse(RuleEngine.evaluate(.condition("durationMinutes", "between", .numbers([60, 30])), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "not_between", .numbers([60, 30])), event: event, now: now))
  }

  /// With a missing bound (only 1 number, or none), `bounds.count != 2`, so the
  /// guard fires and `compareRange` returns `true` unconditionally -- for BOTH
  /// "between" and "not_between".
  func testBetweenWithMissingBoundReturnsTrue() {
    let event = makeEvent(durationMinutes: 999)
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "between", .number(30)), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "not_between", .number(30)), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "between", .numbers([])), event: event, now: now))
  }

  // MARK: - Special fields

  func testStartsWithinRequiresNonNegativeAndWithinValue() {
    // startMinutesFromNow >= 0 && <= value.number
    let soon = makeEvent(startMinutesFromNow: 10)
    let past = makeEvent(startMinutesFromNow: -5)
    let far = makeEvent(startMinutesFromNow: 120)
    XCTAssertTrue(RuleEngine.evaluate(.condition("startsWithin", "", .number(30)), event: soon, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("startsWithin", "", .number(30)), event: past, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("startsWithin", "", .number(30)), event: far, now: now))
    // Boundary: exactly equal to value passes (<=).
    let boundary = makeEvent(startMinutesFromNow: 30)
    XCTAssertTrue(RuleEngine.evaluate(.condition("startsWithin", "", .number(30)), event: boundary, now: now))
  }

  func testHourFieldUsesEventStartDateComponent() {
    // 2026-07-05T15:30:00Z in whatever local calendar; derive the expected
    // hour the same way the source does, so this test is timezone-agnostic.
    let start = makeDate(year: 2026, month: 7, day: 5, hour: 15, minute: 30)
    let event = makeEvent(startISO: isoString(from: start), endISO: isoString(from: start.addingTimeInterval(3600)))
    let expectedHour = Calendar.current.component(.hour, from: start)
    XCTAssertTrue(RuleEngine.evaluate(.condition("hour", "eq", .number(Double(expectedHour))), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("hour", "eq", .number(Double((expectedHour + 1) % 24))), event: event, now: now))
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
    XCTAssertTrue(RuleEngine.evaluate(.condition("weekday", "is", .string(String(expectedWeekday))), event: sundayEvent, now: now))

    // 2026-07-06 is a Monday.
    let monday = makeDate(year: 2026, month: 7, day: 6, hour: 9)
    let mondayEvent = makeEvent(startISO: isoString(from: monday), endISO: isoString(from: monday.addingTimeInterval(3600)))
    let expectedMonday = Calendar.current.component(.weekday, from: monday) - 1
    XCTAssertTrue(RuleEngine.evaluate(.condition("weekday", "is", .string(String(expectedMonday))), event: mondayEvent, now: now))
    XCTAssertNotEqual(expectedWeekday, expectedMonday)
  }

  func testAttendeeContainsAndExcludesMatchesEmailSubstringLowercased() {
    let event = makeEvent(attendees: [
      Attendee(email: "Alice@Example.com", name: "Alice", responseStatus: "accepted", selfUser: false, organizer: false, optional: false, resource: false)
    ])
    XCTAssertTrue(RuleEngine.evaluate(.condition("attendee", "contains", .string("alice")), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("attendee", "contains", .string("EXAMPLE.COM")), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("attendee", "contains", .string("bob")), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("attendee", "excludes", .string("alice")), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("attendee", "excludes", .string("bob")), event: event, now: now))
  }

  // MARK: - Calendar field

  func testCalendarIsAndIsAnyOf() {
    let calRef = CalendarRef(id: "key-1", googleId: "google-1", name: "Work", primary: true, backgroundColor: "#fff")
    let event = makeEvent(calendar: calRef)
    XCTAssertTrue(RuleEngine.evaluate(.condition("calendar", "is", .string("key-1")), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("calendar", "is", .string("google-1")), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.condition("calendar", "is", .string("other")), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("calendar", "is_any_of", .strings(["other", "google-1"])), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.condition("calendar", "is_none_of", .strings(["other"])), event: event, now: now))
  }

  // MARK: - Groups

  func testGroupAndSemanticsIsAllSatisfy() {
    let event = makeEvent(title: "Sync", allDay: false)
    let rule = Rule.group(.and, [
      .condition("title", "contains", .string("sync")),
      .condition("allDay", "is_false")
    ])
    XCTAssertTrue(RuleEngine.evaluate(rule, event: event, now: now))

    let failing = Rule.group(.and, [
      .condition("title", "contains", .string("sync")),
      .condition("allDay", "is_true")
    ])
    XCTAssertFalse(RuleEngine.evaluate(failing, event: event, now: now))
  }

  func testGroupOrSemanticsIsAny() {
    let event = makeEvent(title: "Sync", allDay: false)
    let rule = Rule.group(.any, [
      .condition("title", "contains", .string("standup")),
      .condition("allDay", "is_false")
    ])
    XCTAssertTrue(RuleEngine.evaluate(rule, event: event, now: now))

    let failing = Rule.group(.any, [
      .condition("title", "contains", .string("standup")),
      .condition("allDay", "is_true")
    ])
    XCTAssertFalse(RuleEngine.evaluate(failing, event: event, now: now))
  }

  func testEmptyGroupReturnsTrue() {
    let event = makeEvent()
    XCTAssertTrue(RuleEngine.evaluate(.group(.and, []), event: event, now: now))
    XCTAssertTrue(RuleEngine.evaluate(.group(.any, []), event: event, now: now))
  }

  /// An empty group evaluates to `true`, and `negate` is applied to that
  /// result like any other rule, so a negated empty group is `false`.
  func testNegatedEmptyGroupReturnsFalse() {
    let event = makeEvent()
    XCTAssertFalse(RuleEngine.evaluate(.group(.and, [], negate: true), event: event, now: now))
    XCTAssertFalse(RuleEngine.evaluate(.group(.any, [], negate: true), event: event, now: now))
  }

  func testNegateOnGroup() {
    let event = makeEvent(title: "Sync")
    let rule = Rule.group(.and, [.condition("title", "contains", .string("sync"))], negate: true)
    XCTAssertFalse(RuleEngine.evaluate(rule, event: event, now: now))
  }

  func testNegateOnCondition() {
    let event = makeEvent(title: "Sync")
    let rule = Rule.condition("title", "contains", .string("sync"), negate: true)
    XCTAssertFalse(RuleEngine.evaluate(rule, event: event, now: now))
  }

  func testNestedGroups() {
    let event = makeEvent(title: "Sync", allDay: false, attendeeCount: 3)
    // (title contains "sync" AND allDay is_false) OR (attendeeCount gt 100)
    let rule = Rule.group(.any, [
      .group(.and, [
        .condition("title", "contains", .string("sync")),
        .condition("allDay", "is_false")
      ]),
      .condition("attendeeCount", "gt", .number(100))
    ])
    XCTAssertTrue(RuleEngine.evaluate(rule, event: event, now: now))

    let event2 = makeEvent(title: "Other", allDay: true, attendeeCount: 3)
    XCTAssertFalse(RuleEngine.evaluate(rule, event: event2, now: now))
  }

  // MARK: - Unknown field / operator: permissive default

  /// `evaluateCondition` falls through string/enum/bool/number lookups (all
  /// return nil for an unrecognized field) and hits the `switch field` with a
  /// `default: return true`.
  func testUnknownFieldReturnsTrue() {
    let event = makeEvent()
    XCTAssertTrue(RuleEngine.evaluate(.condition("madeUpField", "equals", .string("x")), event: event, now: now))
  }

  /// Each `compareX` helper has `default: return true` for an unrecognized
  /// operator id, so a known field with a bogus operator is also permissive.
  func testUnknownOperatorReturnsTrue() {
    let event = makeEvent(title: "Sync")
    XCTAssertTrue(RuleEngine.evaluate(.condition("title", "made_up_operator", .string("x")), event: event, now: now))
    let numEvent = makeEvent(durationMinutes: 10)
    XCTAssertTrue(RuleEngine.evaluate(.condition("durationMinutes", "made_up_operator", .number(5)), event: numEvent, now: now))
  }

  func testRuleEngineApplyFiltersEvents() {
    let matching = makeEvent(id: "a", title: "Sync")
    let nonMatching = makeEvent(id: "b", title: "Other")
    let rule = Rule.condition("title", "contains", .string("sync"))
    let result = RuleEngine.apply(rule, to: [matching, nonMatching], now: now)
    XCTAssertEqual(result.map(\.id), ["a"])
  }
}
