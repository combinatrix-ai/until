import XCTest
@testable import Until

final class HeroMetadataTests: XCTestCase {
  func testHeroMetadataIncludesLocationAndProvider() {
    let event = makeEvent(
      location: "Boardroom",
      conferenceUrl: "https://zoom.us/j/123456"
    )

    XCTAssertEqual(Array(heroMetadataParts(for: event).dropFirst()), ["Boardroom", "Zoom"])
  }

  func testHeroMetadataDoesNotRepeatProviderFromLocation() {
    let event = makeEvent(
      location: "zoom",
      conferenceUrl: "https://zoom.us/j/123456"
    )

    XCTAssertEqual(Array(heroMetadataParts(for: event).dropFirst()), ["zoom"])
  }

  func testHeroMetadataSkipsWhitespaceOnlyLocation() {
    let event = makeEvent(
      location: " \n ",
      conferenceUrl: "https://zoom.us/j/123456"
    )

    XCTAssertEqual(Array(heroMetadataParts(for: event).dropFirst()), ["Zoom"])
  }

  func testHeroMetadataFallsBackToTimeOnly() {
    let event = makeEvent()

    XCTAssertEqual(heroMetadataParts(for: event).count, 1)
  }
}
