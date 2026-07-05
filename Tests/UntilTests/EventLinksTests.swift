import XCTest
@testable import Until

final class EventLinksTests: XCTestCase {

  // MARK: - meetingProvider host detection

  func testGoogleMeetDetected() {
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://meet.google.com/abc-defg-hij"), .googleMeet)
  }

  func testZoomAndSubdomainDetected() {
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://zoom.us/j/123456"), .zoom)
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://sub.zoom.us/j/123456"), .zoom)
  }

  func testTeamsAndSubdomainDetected() {
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://teams.microsoft.com/l/meetup-join/x"), .teams)
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://sub.teams.microsoft.com/l/meetup-join/x"), .teams)
  }

  func testWebexApexAndSubdomainDetected() {
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://webex.com/meet/room"), .webex)
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://company.webex.com/meet/room"), .webex)
  }

  func testBlueJeansApexAndSubdomainDetected() {
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://bluejeans.com/123"), .blueJeans)
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://company.bluejeans.com/123"), .blueJeans)
  }

  func testGoToMeetingAndGotoDomainsDetected() {
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://gotomeeting.com/join/123"), .goToMeeting)
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://global.gotomeeting.com/join/123"), .goToMeeting)
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://goto.com/meeting/123"), .goToMeeting)
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://app.goto.com/meeting/123"), .goToMeeting)
  }

  func testWherebyApexAndSubdomainDetected() {
    // whereby.com's standard meeting-link format is the bare apex domain.
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://whereby.com/room"), .whereby)
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://company.whereby.com/room"), .whereby)
  }

  func testAroundApexAndSubdomainDetected() {
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://around.co/room"), .around)
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://company.around.co/room"), .around)
  }

  func testNonMeetingHostReturnsNil() {
    XCTAssertNil(EventLinks.meetingProvider(for: "https://example.com/page"))
    XCTAssertNil(EventLinks.meetingProvider(for: ""))
  }

  // MARK: - Lookalike hosts: exact suffix-matching semantics from source

  /// Source: `host == "zoom.us" || host.hasSuffix(".zoom.us")`. A host with no
  /// dot before "zoom" (e.g. "xzoom.us") does NOT end with ".zoom.us", so it is
  /// NOT matched. Likewise "notzoom.us" is not matched (no leading dot).
  func testZoomLookalikeHostsNotMatched() {
    XCTAssertNil(EventLinks.meetingProvider(for: "https://xzoom.us/j/123"))
    XCTAssertNil(EventLinks.meetingProvider(for: "https://notzoom.us/j/123"))
  }

  /// Any subdomain, no matter how deep or "suspicious looking", still ends in
  /// ".zoom.us" and IS matched -- e.g. "evil.zoom.us" passes hasSuffix.
  func testZoomDeepSubdomainIsMatchedBySuffix() {
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://evil.zoom.us/j/123"), .zoom)
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://a.b.c.zoom.us/j/123"), .zoom)
  }

  /// All providers match either the bare apex domain or any subdomain of it.
  func testWebexApexAndSubdomainBothMatch() {
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://webex.com/meet/room"), .webex)
    XCTAssertEqual(EventLinks.meetingProvider(for: "https://x.webex.com/meet/room"), .webex)
  }

  func testGotoLookalikeHostNotMatched() {
    // "notgoto.com" does not equal "goto.com"/"gotomeeting.com" nor end with
    // ".goto.com"/".gotomeeting.com".
    XCTAssertNil(EventLinks.meetingProvider(for: "https://notgoto.com/meeting/123"))
  }

  /// A lookalike host with no dot before the domain name (e.g. "notwhereby.com")
  /// is neither equal to "whereby.com" nor a suffix-match subdomain of it, so it
  /// is NOT matched.
  func testWherebyLookalikeHostNotMatched() {
    XCTAssertNil(EventLinks.meetingProvider(for: "https://notwhereby.com/room"))
    XCTAssertNil(EventLinks.meetingProvider(for: "https://wherebyxyz.com/room"))
  }

  // MARK: - authenticatedURL

  func testAuthenticatedURLAppendsAuthuserForGoogleDomains() {
    let url = EventLinks.authenticatedURL(from: "https://meet.google.com/abc-defg-hij", accountEmail: "user@example.com")
    XCTAssertEqual(url?.absoluteString, "https://meet.google.com/abc-defg-hij?authuser=user@example.com")
  }

  func testAuthenticatedURLWorksForGoogleComAndCoJp() {
    let comURL = EventLinks.authenticatedURL(from: "https://docs.google.com/document/d/123", accountEmail: "a@b.com")
    XCTAssertTrue(comURL?.absoluteString.contains("authuser=a@b.com") ?? false)

    let coJpURL = EventLinks.authenticatedURL(from: "https://calendar.google.co.jp/event", accountEmail: "a@b.com")
    XCTAssertTrue(coJpURL?.absoluteString.contains("authuser=a@b.com") ?? false)
  }

  func testAuthenticatedURLReplacesExistingAuthuserParam() {
    let url = EventLinks.authenticatedURL(
      from: "https://meet.google.com/abc-defg-hij?authuser=old@example.com&pli=1",
      accountEmail: "new@example.com"
    )
    let absolute = url?.absoluteString ?? ""
    XCTAssertTrue(absolute.contains("authuser=new@example.com"))
    XCTAssertFalse(absolute.contains("old@example.com"))
    XCTAssertTrue(absolute.contains("pli=1"))
  }

  func testAuthenticatedURLLeavesNonGoogleURLsUntouched() {
    let url = EventLinks.authenticatedURL(from: "https://zoom.us/j/123456", accountEmail: "user@example.com")
    XCTAssertEqual(url?.absoluteString, "https://zoom.us/j/123456")
  }

  /// Source: `guard !rawValue.isEmpty, let url = URL(string: rawValue) else { return nil }`.
  /// An empty string fails the `!rawValue.isEmpty` check, so this returns nil.
  func testAuthenticatedURLReturnsNilForEmptyString() {
    XCTAssertNil(EventLinks.authenticatedURL(from: "", accountEmail: "user@example.com"))
  }

  /// `isGoogleURL` requires a non-empty accountEmail to actually append
  /// authuser (`guard isGoogleURL(url), !accountEmail.isEmpty else { return url }`).
  /// With an empty accountEmail, the original URL is returned unchanged (still
  /// non-nil, but no authuser is appended).
  func testAuthenticatedURLWithEmptyAccountEmailLeavesURLUnchanged() {
    let url = EventLinks.authenticatedURL(from: "https://meet.google.com/abc-defg-hij", accountEmail: "")
    XCTAssertEqual(url?.absoluteString, "https://meet.google.com/abc-defg-hij")
  }
}
