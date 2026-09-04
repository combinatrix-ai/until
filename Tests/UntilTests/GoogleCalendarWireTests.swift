import XCTest
@testable import Until

final class GoogleCalendarWireTests: XCTestCase {
  func testDecodesFieldsNeededByBothCalendarClients() throws {
    let event = try decode(
      """
      {
        "id": "event-1",
        "status": "confirmed",
        "summary": "Design review",
        "description": "Agenda",
        "location": "Room 3",
        "htmlLink": "https://calendar.google.com/event?eid=1",
        "hangoutLink": "https://meet.google.com/fallback",
        "colorId": "5",
        "transparency": "transparent",
        "recurringEventId": "series-1",
        "start": { "dateTime": "2026-09-04T10:00:00+09:00" },
        "end": { "dateTime": "2026-09-04T10:30:00+09:00" },
        "organizer": { "email": "owner@example.com" },
        "conferenceData": {
          "entryPoints": [
            { "entryPointType": "phone", "uri": "tel:+81000000000" },
            { "entryPointType": "video", "uri": "https://meet.google.com/primary" }
          ]
        },
        "attendees": [
          {
            "email": "me@example.com",
            "displayName": "Me",
            "responseStatus": "accepted",
            "self": true,
            "resource": false
          }
        ],
        "attachments": [
          {
            "fileId": "doc-1",
            "fileUrl": "https://docs.google.com/document/d/doc-1/edit",
            "title": "Notes",
            "mimeType": "application/vnd.google-apps.document"
          }
        ]
      }
      """
    )

    XCTAssertEqual(event.id, "event-1")
    XCTAssertEqual(event.organizer?.email, "owner@example.com")
    XCTAssertEqual(event.attendees?.first?.displayName, "Me")
    XCTAssertEqual(event.attendees?.first?.responseStatus, "accepted")
    XCTAssertEqual(event.attendees?.first?.selfUser, true)
    XCTAssertEqual(event.attachments?.first?.fileId, "doc-1")
    XCTAssertEqual(event.videoEntryPointURL, "https://meet.google.com/primary")
  }

  func testExistingNotePrefersDocumentAttachment() throws {
    let event = try decode(
      """
      {
        "id": "event-1",
        "description": "Fallback https://docs.google.com/document/d/description/edit",
        "attachments": [
          {
            "fileUrl": "https://docs.google.com/document/d/attachment/edit",
            "mimeType": "application/vnd.google-apps.document"
          }
        ]
      }
      """
    )

    XCTAssertEqual(event.existingNoteURL, "https://docs.google.com/document/d/attachment/edit")
  }

  func testExistingNoteFallsBackToDescriptionAndIgnoresOtherAttachments() throws {
    let event = try decode(
      """
      {
        "id": "event-1",
        "description": "Notes: https://docs.google.com/document/d/description/edit.",
        "attachments": [
          {
            "fileUrl": "https://drive.google.com/file/d/pdf/view",
            "mimeType": "application/pdf"
          }
        ]
      }
      """
    )

    XCTAssertEqual(event.existingNoteURL, "https://docs.google.com/document/d/description/edit")
  }

  private func decode(_ json: String) throws -> GoogleCalendarEvent {
    try JSONDecoder.google.decode(GoogleCalendarEvent.self, from: Data(json.utf8))
  }
}
