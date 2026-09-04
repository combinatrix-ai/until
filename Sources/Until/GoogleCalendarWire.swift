import Foundation

let googleDocumentMimeType = "application/vnd.google-apps.document"

/// Calendar API event payload shared by event-list normalization and
/// meeting-note mutations. Keeping one wire model prevents those two paths
/// from disagreeing about attachments, attendees, or conference links.
struct GoogleCalendarEvent: Decodable {
  var id: String
  var status: String?
  var summary: String?
  var description: String?
  var location: String?
  var htmlLink: String?
  var hangoutLink: String?
  var colorId: String?
  var transparency: String?
  var recurringEventId: String?
  var start: GoogleCalendarEventDate?
  var end: GoogleCalendarEventDate?
  var organizer: GoogleCalendarPerson?
  var conferenceData: GoogleCalendarConferenceData?
  var attendees: [GoogleCalendarAttendee]?
  var attachments: [GoogleCalendarAttachment]?

  var existingNoteURL: String? {
    if let attachment = attachments?.first(where: { $0.mimeType == googleDocumentMimeType }),
       let url = attachment.fileUrl {
      return url
    }
    return GoogleDocLinks.documentURL(from: description)
  }

  var videoEntryPointURL: String? {
    conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri
  }
}

struct GoogleCalendarEventDate: Decodable {
  var dateTime: String?
  var date: String?
}

struct GoogleCalendarPerson: Decodable {
  var email: String?
}

struct GoogleCalendarConferenceData: Decodable {
  var entryPoints: [GoogleCalendarConferenceEntryPoint]?
}

struct GoogleCalendarConferenceEntryPoint: Decodable {
  var entryPointType: String?
  var uri: String?
}

struct GoogleCalendarAttendee: Decodable {
  var email: String?
  var displayName: String?
  var responseStatus: String?
  var selfUser: Bool?
  var resource: Bool?

  enum CodingKeys: String, CodingKey {
    case email, displayName, responseStatus, resource
    case selfUser = "self"
  }
}

struct GoogleCalendarAttachment: Decodable {
  var fileId: String?
  var fileUrl: String?
  var title: String?
  var mimeType: String?
}

enum GoogleDocLinks {
  static func documentURL(from value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    let decoded = decodeHtmlEntities(value)
    let pattern = #"https://docs\.google\.com/document/[^\s"'<>]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(decoded.startIndex..<decoded.endIndex, in: decoded)
    guard let match = regex.firstMatch(in: decoded, range: range),
          let swiftRange = Range(match.range, in: decoded) else { return nil }
    return cleanURL(String(decoded[swiftRange]))
  }

  static func documentId(from value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if !trimmed.contains("/") {
      return trimmed
    }
    let pattern = #"/document/(?:u/\d+/)?d/([^/?#]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    guard let match = regex.firstMatch(in: trimmed, range: range),
          match.numberOfRanges > 1,
          let swiftRange = Range(match.range(at: 1), in: trimmed) else { return nil }
    return String(trimmed[swiftRange])
  }

  private static func cleanURL(_ value: String) -> String {
    value.trimmingCharacters(in: CharacterSet(charactersIn: ").,;:!?]"))
  }
}

func decodeHtmlEntities(_ value: String) -> String {
  value
    .replacingOccurrences(of: "&amp;", with: "&")
    .replacingOccurrences(of: "&lt;", with: "<")
    .replacingOccurrences(of: "&gt;", with: ">")
    .replacingOccurrences(of: "&quot;", with: "\"")
    .replacingOccurrences(of: "&#39;", with: "'")
}
