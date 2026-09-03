import XCTest
@testable import Until

final class TimelineSummaryTests: XCTestCase {
  private let zoom = "https://zoom.us/j/123456"

  func testSummaryPrefersLocationOverProvider() {
    let event = makeEvent(location: "Boardroom", conferenceUrl: zoom)

    XCTAssertEqual(timelineSummary(for: event), TimelineSummary(kind: .location, text: "Boardroom"))
  }

  func testSummaryFallsBackToMeetingProvider() {
    let event = makeEvent(conferenceUrl: zoom)

    XCTAssertEqual(timelineSummary(for: event), TimelineSummary(kind: .meetingProvider, text: "Zoom"))
  }

  func testSummaryTreatsWhitespaceLocationAsAbsent() {
    let event = makeEvent(location: " \n ", conferenceUrl: zoom)

    XCTAssertEqual(timelineSummary(for: event)?.kind, .meetingProvider)
  }

  func testSummaryIsOmittedWithoutLocationOrProvider() {
    XCTAssertNil(timelineSummary(for: makeEvent()))
  }

  func testSummaryNeverShowsAttendees() {
    let event = makeEvent(attendees: [
      Attendee(email: "guest@example.com", name: "Guest", responseStatus: "accepted", selfUser: false, resource: false)
    ])

    XCTAssertNil(timelineSummary(for: event))
  }

  func testSummaryKindsMapToDistinctIcons() {
    XCTAssertEqual(TimelineSummary.Kind.location.systemImage, "mappin.and.ellipse")
    XCTAssertEqual(TimelineSummary.Kind.meetingProvider.systemImage, "video")
  }

  func testBareLinkAcceptsSingleWebURL() {
    XCTAssertTrue(isBareLink("https://docs.google.com/document/d/abc/edit?tab=t.0"))
    XCTAssertTrue(isBareLink("  http://example.com/notes \n"))
  }

  func testBareLinkRejectsProseMarkupAndOtherSchemes() {
    XCTAssertFalse(isBareLink(""))
    XCTAssertFalse(isBareLink("Agenda: https://example.com/notes"))
    XCTAssertFalse(isBareLink("<a href=\"https://example.com\">notes</a>"))
    XCTAssertFalse(isBareLink("ftp://example.com/file"))
    XCTAssertFalse(isBareLink("mailto:someone@example.com"))
  }
}
