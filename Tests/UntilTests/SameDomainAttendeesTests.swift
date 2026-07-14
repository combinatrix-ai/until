import XCTest

@testable import Until

/// `sameDomainAttendees(for:)` feeds the notes-creation confirmation: it must
/// name exactly the people who get automatic edit access — same-domain
/// attendees other than the user — and nobody else.
final class SameDomainAttendeesTests: XCTestCase {
  @MainActor
  private func attendees(for list: [Attendee]) -> [String] {
    let model = AppModel(options: AppRuntimeOptions(demoMode: true))
    let event = makeEvent(account: AccountRef(email: "me@acme.test"), attendees: list)
    return model.sameDomainAttendees(for: event)
  }

  private func attendee(
    _ email: String, selfUser: Bool = false, resource: Bool = false
  ) -> Attendee {
    Attendee(
      email: email, name: "", responseStatus: "accepted",
      selfUser: selfUser, organizer: false, optional: false, resource: resource
    )
  }

  @MainActor
  func testKeepsOnlySameDomainOthers() {
    let result = attendees(for: [
      attendee("me@acme.test", selfUser: true),
      attendee("colleague@acme.test"),
      attendee("outsider@other.test"),
      attendee("room@acme.test", resource: true)
    ])
    XCTAssertEqual(result, ["colleague@acme.test"])
  }

  @MainActor
  func testNormalizesCaseAndWhitespaceAndDeduplicates() {
    let result = attendees(for: [
      attendee("  Colleague@ACME.test "),
      attendee("colleague@acme.test"),
      attendee("Another@acme.test")
    ])
    XCTAssertEqual(result, ["another@acme.test", "colleague@acme.test"])
  }

  @MainActor
  func testExcludesOwnerEmailEvenWithoutSelfFlag() {
    let result = attendees(for: [attendee("me@acme.test")])
    XCTAssertEqual(result, [])
  }

  @MainActor
  func testEmptyWhenNoAttendees() {
    XCTAssertEqual(attendees(for: []), [])
  }
}
