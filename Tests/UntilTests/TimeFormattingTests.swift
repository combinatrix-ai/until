import XCTest
@testable import Until

final class TimeFormattingTests: XCTestCase {
  func testRoundedMinutesRoundsToNearestWholeMinute() {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    XCTAssertEqual(roundedMinutes(from: start, to: start.addingTimeInterval(29)), 0)
    XCTAssertEqual(roundedMinutes(from: start, to: start.addingTimeInterval(31)), 1)
    XCTAssertEqual(roundedMinutes(from: start, to: start.addingTimeInterval(90)), 2)
  }

  func testRoundedMinutesClampsPastTargetsAtZero() {
    let start = Date(timeIntervalSinceReferenceDate: 60)

    XCTAssertEqual(roundedMinutes(from: start, to: .init(timeIntervalSinceReferenceDate: 0)), 0)
  }
}
