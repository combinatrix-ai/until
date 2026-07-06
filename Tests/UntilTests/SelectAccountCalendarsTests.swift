import XCTest
@testable import Until

@MainActor
final class SelectAccountCalendarsTests: XCTestCase {
  func makeSummary(
    id: String,
    primary: Bool,
    accountEmail: String
  ) -> CalendarSummary {
    CalendarSummary(
      id: id,
      googleId: id,
      name: id,
      primary: primary,
      backgroundColor: "#888",
      selected: true,
      accountEmail: accountEmail
    )
  }

  func testEmptySelectionIsUnchanged() {
    let calendars = [makeSummary(id: "new@example.com::primary", primary: true, accountEmail: "new@example.com")]
    let result = AppModel.selectedCalendarIds([], addingCalendarsFrom: calendars, forAccountEmail: "new@example.com")
    XCTAssertNil(result)
  }

  func testNonEmptySelectionAddsAllNewAccountCalendars() {
    let calendars = [
      makeSummary(id: "existing@example.com::primary", primary: true, accountEmail: "existing@example.com"),
      makeSummary(id: "new@example.com::primary", primary: true, accountEmail: "new@example.com"),
      makeSummary(id: "new@example.com::secondary", primary: false, accountEmail: "new@example.com")
    ]
    let result = AppModel.selectedCalendarIds(
      ["existing@example.com::primary"],
      addingCalendarsFrom: calendars,
      forAccountEmail: "new@example.com"
    )
    XCTAssertEqual(
      result,
      [
        "existing@example.com::primary",
        "new@example.com::primary",
        "new@example.com::secondary"
      ].sorted()
    )
  }

  func testAllAlreadyPresentIsUnchanged() {
    let calendars = [
      makeSummary(id: "new@example.com::primary", primary: true, accountEmail: "new@example.com"),
      makeSummary(id: "new@example.com::secondary", primary: false, accountEmail: "new@example.com")
    ]
    let result = AppModel.selectedCalendarIds(
      ["new@example.com::primary", "new@example.com::secondary"],
      addingCalendarsFrom: calendars,
      forAccountEmail: "new@example.com"
    )
    XCTAssertNil(result)
  }

  func testNoMatchingCalendarsIsUnchanged() {
    let calendars = [makeSummary(id: "other@example.com::primary", primary: true, accountEmail: "other@example.com")]
    let result = AppModel.selectedCalendarIds(
      ["existing@example.com::primary"],
      addingCalendarsFrom: calendars,
      forAccountEmail: "new@example.com"
    )
    XCTAssertNil(result)
  }

  func testOtherAccountsCalendarsAreUntouched() {
    let calendars = [
      makeSummary(id: "existing@example.com::primary", primary: true, accountEmail: "existing@example.com"),
      makeSummary(id: "other@example.com::primary", primary: true, accountEmail: "other@example.com"),
      makeSummary(id: "new@example.com::primary", primary: true, accountEmail: "new@example.com")
    ]
    let result = AppModel.selectedCalendarIds(
      ["existing@example.com::primary"],
      addingCalendarsFrom: calendars,
      forAccountEmail: "new@example.com"
    )
    XCTAssertEqual(
      result,
      ["existing@example.com::primary", "new@example.com::primary"].sorted()
    )
    XCTAssertFalse(result?.contains("other@example.com::primary") ?? true)
  }

  func testAccountEmailMatchIsCaseInsensitive() {
    let calendars = [
      makeSummary(id: "New@Example.com::primary", primary: true, accountEmail: "New@Example.com"),
      makeSummary(id: "New@Example.com::secondary", primary: false, accountEmail: "New@Example.com")
    ]
    let result = AppModel.selectedCalendarIds(
      ["existing@example.com::primary"],
      addingCalendarsFrom: calendars,
      forAccountEmail: "new@example.com"
    )
    XCTAssertEqual(
      result,
      [
        "New@Example.com::primary",
        "New@Example.com::secondary",
        "existing@example.com::primary"
      ].sorted()
    )
  }
}
