import XCTest
@testable import Until

final class ExtractMeetingURLTests: XCTestCase {

  func testExtractsGoogleMeetURLFromFreeText() {
    let text = "Join the call here: https://meet.google.com/abc-defg-hij and see you soon."
    XCTAssertEqual(extractMeetingURL(text), "https://meet.google.com/abc-defg-hij")
  }

  /// Source calls `decodeHtmlEntities(text)` BEFORE running the URL regex, so
  /// an `&amp;` in the query string is decoded to `&` prior to matching, and
  /// the extracted URL contains a real `&`, not the literal entity.
  func testExtractsFromHtmlEntityEncodedText() {
    let text = "Meeting link: https://zoom.us/j/123456?pwd=abc&amp;foo=bar"
    XCTAssertEqual(extractMeetingURL(text), "https://zoom.us/j/123456?pwd=abc&foo=bar")
  }

  func testStripsTrailingPunctuationFromExtractedURL() {
    let text = "Details at https://meet.google.com/abc-defg-hij."
    XCTAssertEqual(extractMeetingURL(text), "https://meet.google.com/abc-defg-hij")

    let text2 = "See (https://zoom.us/j/123456);"
    // Note: trailing ')' is not in the trim set (".,;:!?"), only the trailing
    // ';' after it gets stripped; the regex itself excludes ')' from the URL
    // via the `[^\s<>"')\]}]+` character class, so the URL never includes it.
    XCTAssertEqual(extractMeetingURL(text2), "https://zoom.us/j/123456")
  }

  func testReturnsNilWhenNoMeetingProviderURLPresent() {
    XCTAssertNil(extractMeetingURL("No links here, just plain text."))
    XCTAssertNil(extractMeetingURL("Visit https://example.com/page for info."))
    XCTAssertNil(extractMeetingURL(nil))
    XCTAssertNil(extractMeetingURL(""))
  }

  func testPicksFirstRecognizedProviderURLAndSkipsNonProviderURLs() {
    let text = """
    Random link: https://example.com/ignored
    Actual meeting: https://teams.microsoft.com/l/meetup-join/abc
    Backup: https://zoom.us/j/999999
    """
    XCTAssertEqual(extractMeetingURL(text), "https://teams.microsoft.com/l/meetup-join/abc")
  }

  func testDecodeHtmlEntitiesHelperDirectly() {
    XCTAssertEqual(decodeHtmlEntities("a &amp; b &lt;c&gt; &quot;d&quot; &#39;e&#39;"), "a & b <c> \"d\" 'e'")
  }
}
