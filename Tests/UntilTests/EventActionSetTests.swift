import XCTest
@testable import Until

final class EventActionSetTests: XCTestCase {
  func testFullyAttachedEventHasOnlyAttachedAndCommonActions() {
    let event = makeEvent(conferenceUrl: "https://meet.example.test/room")
    let actionSet = EventActionSet.make(
      event: event,
      noteURL: "https://docs.example.test/note",
      isSkipped: true
    )

    XCTAssertEqual(actionSet.attached, [.joinVideoCall, .copyMeetingLink, .openMeetingNotes])
    XCTAssertTrue(actionSet.addable.isEmpty)
    XCTAssertEqual(
      actionSet.common,
      [.copyDetails, .openInCalendar, .showInMenubar]
    )
  }

  func testNothingAttachedOffersBothAddableActionsForTimedEvent() {
    let actionSet = EventActionSet.make(
      event: makeEvent(),
      noteURL: nil,
      isSkipped: false
    )

    XCTAssertTrue(actionSet.attached.isEmpty)
    XCTAssertEqual(actionSet.addable, [.addGoogleMeet, .createNotes])
    XCTAssertEqual(
      actionSet.common,
      [.copyDetails, .openInCalendar, .skipInMenubar]
    )
  }

  func testPastEventUsesTheSameActionShapeAsAnyOtherTimedEvent() {
    let actionSet = EventActionSet.make(
      event: makeEvent(
        startISO: "2026-07-05T08:00:00Z",
        endISO: "2026-07-05T09:00:00Z"
      ),
      noteURL: nil,
      isSkipped: false
    )

    XCTAssertEqual(actionSet.attached, [])
    XCTAssertEqual(actionSet.addable, [.addGoogleMeet, .createNotes])
    XCTAssertEqual(actionSet.common.last, .skipInMenubar)
  }

  func testAllDayEventCannotAddGoogleMeet() {
    let actionSet = EventActionSet.make(
      event: makeEvent(allDay: true),
      noteURL: nil,
      isSkipped: false
    )

    XCTAssertTrue(actionSet.attached.isEmpty)
    XCTAssertEqual(actionSet.addable, [.createNotes])
  }

  func testNoteAttachedOnlyOffersOpenNotesAndAddMeet() {
    let actionSet = EventActionSet.make(
      event: makeEvent(),
      noteURL: "https://docs.example.test/note",
      isSkipped: false
    )

    XCTAssertEqual(actionSet.attached, [.openMeetingNotes])
    XCTAssertEqual(actionSet.addable, [.addGoogleMeet])
  }
}
