import XCTest
@testable import Until

@MainActor
final class CalendarSelectionTests: XCTestCase {
  func testProductionSelectionRequiresAccountScopedKey() {
    let rawSelection = ["primary"]
    XCTAssertFalse(isCalendarSelected("personal@example.com::primary", selectedIds: rawSelection))
    XCTAssertFalse(isCalendarSelected("work@example.com::primary", selectedIds: rawSelection))

    XCTAssertTrue(
      isCalendarSelected(
        "personal@example.com::primary",
        selectedIds: ["personal@example.com::primary"]
      )
    )
    XCTAssertFalse(
      isCalendarSelected(
        "work@example.com::primary",
        selectedIds: ["personal@example.com::primary"]
      )
    )
    XCTAssertTrue(isCalendarSelected("work@example.com::primary", selectedIds: []))
  }

  func testDemoSelectionRequiresAccountScopedKey() {
    let rawCalendars = DemoCalendarData.calendars(selectedIds: ["primary"])
    XCTAssertTrue(rawCalendars.filter(\.selected).isEmpty)

    let scopedCalendars = DemoCalendarData.calendars(
      selectedIds: ["personal@example.com::primary"]
    )
    XCTAssertEqual(
      scopedCalendars.filter(\.selected).map(\.id),
      ["personal@example.com::primary"]
    )
  }
}
