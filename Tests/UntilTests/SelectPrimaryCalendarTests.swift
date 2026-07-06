import XCTest
@testable import Until

@MainActor
final class SelectPrimaryCalendarTests: XCTestCase {
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
    let result = AppModel.selectedCalendarIds([], addingPrimaryFrom: calendars, forAccountEmail: "new@example.com")
    XCTAssertNil(result)
  }

  func testNonEmptySelectionAddsNewAccountPrimary() {
    let calendars = [
      makeSummary(id: "existing@example.com::primary", primary: true, accountEmail: "existing@example.com"),
      makeSummary(id: "new@example.com::primary", primary: true, accountEmail: "new@example.com"),
      makeSummary(id: "new@example.com::secondary", primary: false, accountEmail: "new@example.com")
    ]
    let result = AppModel.selectedCalendarIds(
      ["existing@example.com::primary"],
      addingPrimaryFrom: calendars,
      forAccountEmail: "new@example.com"
    )
    XCTAssertEqual(result, ["existing@example.com::primary", "new@example.com::primary"].sorted())
  }

  func testAlreadyPresentPrimaryIsUnchanged() {
    let calendars = [makeSummary(id: "new@example.com::primary", primary: true, accountEmail: "new@example.com")]
    let result = AppModel.selectedCalendarIds(
      ["new@example.com::primary"],
      addingPrimaryFrom: calendars,
      forAccountEmail: "new@example.com"
    )
    XCTAssertNil(result)
  }

  func testNoMatchingPrimaryCalendarIsUnchanged() {
    let calendars = [makeSummary(id: "other@example.com::primary", primary: true, accountEmail: "other@example.com")]
    let result = AppModel.selectedCalendarIds(
      ["existing@example.com::primary"],
      addingPrimaryFrom: calendars,
      forAccountEmail: "new@example.com"
    )
    XCTAssertNil(result)
  }

  func testAccountEmailMatchIsCaseInsensitive() {
    let calendars = [makeSummary(id: "New@Example.com::primary", primary: true, accountEmail: "New@Example.com")]
    let result = AppModel.selectedCalendarIds(
      ["existing@example.com::primary"],
      addingPrimaryFrom: calendars,
      forAccountEmail: "new@example.com"
    )
    XCTAssertEqual(result, ["New@Example.com::primary", "existing@example.com::primary"].sorted())
  }
}
