import XCTest
@testable import Until

final class MenubarTitleTests: XCTestCase {
  func testTitleWithinLimitIsUnchanged() {
    XCTAssertEqual(truncatedMenubarTitle("Planning", maximumCharacters: 8), "Planning")
  }

  func testEllipsisCountsTowardLimit() {
    XCTAssertEqual(truncatedMenubarTitle("Planning", maximumCharacters: 5), "Plan…")
  }

  func testZeroLimitDropsTitleSoTimeCanRemain() {
    XCTAssertEqual(truncatedMenubarTitle("Planning", maximumCharacters: 0), "")
  }

  func testComposedCharactersAreNotSplit() {
    XCTAssertEqual(truncatedMenubarTitle("👨‍👩‍👧‍👦ABC", maximumCharacters: 3), "👨‍👩‍👧‍👦A…")
  }
}
