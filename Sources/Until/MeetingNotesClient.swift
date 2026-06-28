import Foundation

@MainActor
final class MeetingNotesClient {
  private let auth: GoogleAuth
  private let calendarBase = URL(string: "https://www.googleapis.com/calendar/v3")!
  private let driveBase = URL(string: "https://www.googleapis.com/drive/v3")!
  private let docsBase = URL(string: "https://docs.googleapis.com/v1")!

  init(auth: GoogleAuth) {
    self.auth = auth
  }

  func createNote(
    for event: CalendarEvent,
    folder: DriveFolderRef?,
    titleTemplate: String?,
    templateDocId: String?,
    shareExternalAttendees: Bool
  ) async throws -> MeetingNoteResult {
    let latest = try await fetchEvent(calendarId: event.calendar.googleId, eventId: event.id)
    if let existingNote = findExistingNote(latest) {
      return MeetingNoteResult(
        fileId: existingNote.fileId,
        fileName: existingNote.title,
        webViewLink: existingNote.url,
        folderId: "",
        sharedWith: [],
        skippedExternal: [],
        reused: true
      )
    }

    let folderId = try await resolveFolderId(folder: folder)
    let attendeeEmails = attendeeEmails(from: latest)
    let fileName = createFileName(for: latest, template: titleTemplate)

    // Copy the configured template if one is set; if it can't be accessed
    // (missing, deleted, or no permission), fall back to the built-in template
    // so note creation still succeeds.
    var usedCopiedTemplate = false
    let file: DriveFile
    if let templateId = templateDocId?.nilIfEmpty {
      if let copied = try? await createDocument(fileName: fileName, folderId: folderId, templateDocId: templateId) {
        file = copied
        usedCopiedTemplate = true
      } else {
        file = try await createDocument(fileName: fileName, folderId: folderId, templateDocId: nil)
      }
    } else {
      file = try await createDocument(fileName: fileName, folderId: folderId, templateDocId: nil)
    }

    if usedCopiedTemplate {
      try await populateCopiedTemplate(documentId: file.id, event: latest, attendeeEmails: attendeeEmails)
    } else {
      try await populateBuiltInTemplate(documentId: file.id, event: latest, attendeeEmails: attendeeEmails)
    }

    let shareResult = await shareWithAttendees(
      fileId: file.id,
      emails: attendeeEmails,
      ownerDomain: emailDomain(auth.email),
      shareExternalAttendees: shareExternalAttendees
    )
    try await attachToEvent(calendarId: event.calendar.googleId, event: latest, file: file)

    return MeetingNoteResult(
      fileId: file.id,
      fileName: file.name,
      webViewLink: file.webViewLink,
      folderId: folderId,
      sharedWith: shareResult.sharedWith,
      skippedExternal: shareResult.skippedExternal,
      reused: false
    )
  }

  func listDriveRoots() async throws -> [DriveFolderRef] {
    let url = driveBase
      .appending(path: "drives")
      .appending(queryItems: [URLQueryItem(name: "fields", value: "drives(id,name)")])
    let sharedDrives: SharedDriveList = try await api(url)
    return [
      DriveFolderRef(id: "root", name: "My Drive", source: .myDrive, driveId: nil, path: ["My Drive"]),
      DriveFolderRef(
        id: "shared-with-me",
        name: "Shared with me",
        source: .sharedWithMe,
        driveId: nil,
        path: ["Shared with me"]
      )
    ] + sharedDrives.drives.compactMap { drive in
      guard !drive.id.isEmpty, !drive.name.isEmpty else { return nil }
      return DriveFolderRef(
        id: drive.id,
        name: drive.name,
        source: .sharedDrive,
        driveId: drive.id,
        path: [drive.name]
      )
    }
  }

  func listDriveFolders(in parent: DriveFolderRef) async throws -> [DriveFolderRef] {
    let source = parent.source
    let query = buildFolderListQuery(parent: parent)
    var items = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "fields", value: "files(id,name,driveId)"),
      URLQueryItem(name: "spaces", value: "drive"),
      URLQueryItem(name: "pageSize", value: "100"),
      URLQueryItem(name: "supportsAllDrives", value: "true"),
      URLQueryItem(name: "includeItemsFromAllDrives", value: "true")
    ]
    if source == .sharedDrive, let driveId = parent.driveId {
      items.append(URLQueryItem(name: "corpora", value: "drive"))
      items.append(URLQueryItem(name: "driveId", value: driveId))
    }
    let url = driveBase.appending(path: "files").appending(queryItems: items)
    let listed: DriveFileList = try await api(url)
    return listed.files
      .filter { !$0.id.isEmpty && !$0.name.isEmpty }
      .map { file in
        DriveFolderRef(
          id: file.id,
          name: file.name,
          source: source,
          driveId: file.driveId ?? parent.driveId,
          path: parent.path + [file.name]
        )
      }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func fetchEvent(calendarId: String, eventId: String) async throws -> GoogleEvent {
    let url = calendarBase
      .appending(path: "calendars")
      .appending(path: calendarId)
      .appending(path: "events")
      .appending(path: eventId)
      .appending(queryItems: [URLQueryItem(name: "conferenceDataVersion", value: "1")])
    return try await api(url)
  }

  private func resolveFolderId(folder: DriveFolderRef?) async throws -> String {
    if let folder, folder.id != "shared-with-me" {
      return folder.id
    }
    return try await findOrCreateFolder(name: defaultMeetingNotesFolderName)
  }

  private func findOrCreateFolder(name: String) async throws -> String {
    let query = [
      "mimeType='\(folderMimeType)'",
      "name='\(escapeDriveQuery(name))'",
      "trashed=false",
      "'root' in parents"
    ].joined(separator: " and ")
    let url = driveBase
      .appending(path: "files")
      .appending(queryItems: [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "fields", value: "files(id,name)"),
        URLQueryItem(name: "spaces", value: "drive"),
        URLQueryItem(name: "pageSize", value: "1")
      ])
    let listed: DriveFileList = try await api(url)
    if let id = listed.files.first?.id {
      return id
    }

    let createURL = driveBase
      .appending(path: "files")
      .appending(queryItems: [URLQueryItem(name: "fields", value: "id")])
    let created: DriveFile = try await api(createURL, method: "POST", body: [
      "name": name,
      "mimeType": folderMimeType,
      "parents": ["root"]
    ])
    guard !created.id.isEmpty else {
      throw AppError.message("Google Drive folder was created without an id.")
    }
    return created.id
  }

  private func createDocument(fileName: String, folderId: String, templateDocId: String?) async throws -> DriveFile {
    if let templateDocId {
      let url = driveBase
        .appending(path: "files")
        .appending(path: templateDocId)
        .appending(path: "copy")
        .appending(queryItems: [
          URLQueryItem(name: "supportsAllDrives", value: "true"),
          URLQueryItem(name: "fields", value: "id,name,webViewLink")
        ])
      return try checkedDriveFile(try await api(url, method: "POST", body: [
        "name": fileName,
        "parents": [folderId]
      ]))
    }

    let url = driveBase
      .appending(path: "files")
      .appending(queryItems: [
        URLQueryItem(name: "supportsAllDrives", value: "true"),
        URLQueryItem(name: "fields", value: "id,name,webViewLink")
      ])
    return try checkedDriveFile(try await api(url, method: "POST", body: [
      "name": fileName,
      "mimeType": docMimeType,
      "parents": [folderId]
    ]))
  }

  private func checkedDriveFile(_ file: DriveFile) throws -> DriveFile {
    guard !file.id.isEmpty, !file.name.isEmpty, !file.webViewLink.isEmpty else {
      throw AppError.message("Google Docs file was created without an id or web link.")
    }
    return file
  }

  private func populateCopiedTemplate(documentId: String, event: GoogleEvent, attendeeEmails: [String]) async throws {
    let replacements: [String: String] = [
      "{{title}}": event.summary ?? "Untitled",
      "{{datetime}}": formatEventRange(event),
      "{{calendar_link}}": event.htmlLink ?? "",
      "{{calendar_url}}": event.htmlLink ?? "",
      "{{date}}": formatEventDate(event),
      "{{start_time}}": event.start?.dateTime.flatMap { formatTime($0) } ?? "",
      "{{end_time}}": event.end?.dateTime.flatMap { formatTime($0) } ?? "",
      "{{attendees}}": attendeeListText(attendeeEmails)
    ]
    try await batchUpdate(documentId: documentId, requests: replacements.map { key, value in
      [
        "replaceAllText": [
          "containsText": ["text": key, "matchCase": true],
          "replaceText": value
        ]
      ]
    })
  }

  private func populateBuiltInTemplate(documentId: String, event: GoogleEvent, attendeeEmails: [String]) async throws {
    let attendees = attendeeEmails.isEmpty ? "No attendees" : attendeeEmails.map { "- \($0)" }.joined(separator: "\n")
    let text = """
    \(event.summary ?? "Untitled")

    Time
    \(formatEventRange(event))

    Calendar
    \(event.htmlLink ?? "")

    Attendees
    \(attendees)

    Notes

    Decisions

    Action items
    - [ ]

    """
    try await batchUpdate(documentId: documentId, requests: [
      [
        "insertText": [
          "location": ["index": 1],
          "text": text
        ]
      ]
    ])
  }

  private func batchUpdate(documentId: String, requests: [[String: Any]]) async throws {
    guard let url = URL(string: "\(docsBase.absoluteString)/documents/\(documentId):batchUpdate") else {
      throw AppError.message("Failed to build Google Docs update URL.")
    }
    let _: EmptyResponse = try await api(url, method: "POST", body: ["requests": requests])
  }

  private func shareWithAttendees(
    fileId: String,
    emails: [String],
    ownerDomain: String?,
    shareExternalAttendees: Bool
  ) async -> (sharedWith: [String], skippedExternal: [String]) {
    var sharedWith: [String] = []
    var skippedExternal: [String] = []

    for email in emails {
      if isExternalEmail(email, ownerDomain: ownerDomain), !shareExternalAttendees {
        skippedExternal.append(email)
        continue
      }
      do {
        let url = driveBase
          .appending(path: "files")
          .appending(path: fileId)
          .appending(path: "permissions")
          .appending(queryItems: [
            URLQueryItem(name: "sendNotificationEmail", value: "false"),
            URLQueryItem(name: "supportsAllDrives", value: "true")
          ])
        let _: EmptyResponse = try await api(url, method: "POST", body: [
          "type": "user",
          "role": "writer",
          "emailAddress": email
        ])
        sharedWith.append(email)
      } catch {
        continue
      }
    }

    return (sharedWith, skippedExternal)
  }

  func addConference(for event: CalendarEvent) async throws -> String {
    let url = calendarBase
      .appending(path: "calendars")
      .appending(path: event.calendar.googleId)
      .appending(path: "events")
      .appending(path: event.id)
      .appending(queryItems: [URLQueryItem(name: "conferenceDataVersion", value: "1")])
    let requestId = UUID().uuidString
    let body: [String: Any] = [
      "conferenceData": [
        "createRequest": [
          "requestId": requestId,
          "conferenceSolutionKey": ["type": "hangoutsMeet"]
        ] as [String: Any]
      ] as [String: Any]
    ]
    let updated: GoogleEvent = try await api(url, method: "PATCH", body: body)
    guard let link = updated.conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri
            ?? updated.hangoutLink
    else {
      throw AppError.message("Google Meet link was not returned. The event may not support video conferencing.")
    }
    return link
  }

  private func attachToEvent(calendarId: String, event: GoogleEvent, file: DriveFile) async throws {
    let attachment: [String: Any] = [
      "fileId": file.id,
      "fileUrl": file.webViewLink,
      "title": file.name,
      "mimeType": docMimeType
    ]
    let existing = (event.attachments ?? [])
      .filter { $0.fileId != file.id }
      .map { item -> [String: Any] in
        var body: [String: Any] = [:]
        if let fileId = item.fileId { body["fileId"] = fileId }
        if let fileUrl = item.fileUrl { body["fileUrl"] = fileUrl }
        if let title = item.title { body["title"] = title }
        if let mimeType = item.mimeType { body["mimeType"] = mimeType }
        return body
      }
    let url = calendarBase
      .appending(path: "calendars")
      .appending(path: calendarId)
      .appending(path: "events")
      .appending(path: event.id)
      .appending(queryItems: [URLQueryItem(name: "supportsAttachments", value: "true")])
    let _: GoogleEvent = try await api(url, method: "PATCH", body: ["attachments": existing + [attachment]])
  }

  private func api<T: Decodable>(_ url: URL, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? "unknown error"
      throw AppError.message("Google API failed: \(message)")
    }
    return try JSONDecoder.google.decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
  }
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

  private static func decodeHtmlEntities(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
  }

  private static func cleanURL(_ value: String) -> String {
    value.trimmingCharacters(in: CharacterSet(charactersIn: ").,;:!?]"))
  }
}

private struct EmptyResponse: Decodable {}

private struct GoogleEvent: Decodable {
  var id: String
  var summary: String?
  var description: String?
  var htmlLink: String?
  var hangoutLink: String?
  var start: GoogleEventDate?
  var end: GoogleEventDate?
  var attendees: [GoogleAttendee]?
  var attachments: [GoogleAttachment]?
  var conferenceData: GoogleConferenceData?
}

private struct GoogleConferenceData: Decodable {
  var entryPoints: [GoogleConferenceEntryPoint]?
}

private struct GoogleConferenceEntryPoint: Decodable {
  var entryPointType: String?
  var uri: String?
}

private struct GoogleEventDate: Decodable {
  var dateTime: String?
  var date: String?
}

private struct GoogleAttendee: Decodable {
  var email: String?
  var resource: Bool?
}

private struct GoogleAttachment: Decodable {
  var fileId: String?
  var fileUrl: String?
  var title: String?
  var mimeType: String?
}

private struct DriveFileList: Decodable {
  var files: [DriveFile] = []
}

private struct DriveFile: Decodable {
  var id: String
  var name: String
  var webViewLink: String
  var driveId: String?

  enum CodingKeys: String, CodingKey {
    case id, name, webViewLink, driveId
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    webViewLink = try container.decodeIfPresent(String.self, forKey: .webViewLink) ?? ""
    driveId = try container.decodeIfPresent(String.self, forKey: .driveId)
  }
}

private struct SharedDriveList: Decodable {
  var drives: [SharedDrive] = []
}

private struct SharedDrive: Decodable {
  var id: String
  var name: String

  enum CodingKeys: String, CodingKey {
    case id, name
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
  }
}

private let docMimeType = "application/vnd.google-apps.document"
private let folderMimeType = "application/vnd.google-apps.folder"
private let defaultMeetingNotesFolderName = "Meeting Notes"

private struct ExistingNote {
  var fileId: String
  var title: String
  var url: String
}

private func findExistingNote(_ event: GoogleEvent) -> ExistingNote? {
  if let attachment = event.attachments?.first(where: isNotesAttachment), let url = attachment.fileUrl {
    return ExistingNote(
      fileId: attachment.fileId ?? GoogleDocLinks.documentId(from: url) ?? "",
      title: attachment.title ?? "Existing notes",
      url: url
    )
  }
  if let descriptionUrl = GoogleDocLinks.documentURL(from: event.description) {
    return ExistingNote(
      fileId: GoogleDocLinks.documentId(from: descriptionUrl) ?? "",
      title: "Description notes",
      url: descriptionUrl
    )
  }
  return nil
}

private func isNotesAttachment(_ attachment: GoogleAttachment) -> Bool {
  let mimeType = attachment.mimeType ?? ""
  return mimeType == docMimeType
}

private func attendeeEmails(from event: GoogleEvent) -> [String] {
  let emails = Set((event.attendees ?? []).compactMap { attendee -> String? in
    guard attendee.resource != true else { return nil }
    let email = attendee.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return email.isEmpty ? nil : email
  })
  return emails.sorted()
}

private func createFileName(for event: GoogleEvent, template: String?) -> String {
  let title = event.summary ?? "Untitled"
  let fallbackDate = ISO8601DateFormatter.fallback.string(from: Date())
  let date = String((event.start?.dateTime ?? event.start?.date ?? fallbackDate).prefix(10))
  let pattern = template?
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .nilIfEmpty ?? AppConfig.defaultNoteTitleTemplate
  let rendered = pattern
    .replacingOccurrences(of: "{date}", with: date)
    .replacingOccurrences(of: "{title}", with: title)
  return sanitizeFileName(rendered)
}

private func sanitizeFileName(_ value: String) -> String {
  let invalid = CharacterSet(charactersIn: "/\\?%*:|\"<>")
  let cleaned = value
    .components(separatedBy: invalid)
    .joined(separator: " ")
    .trimmingCharacters(in: .whitespacesAndNewlines)
  return cleaned.isEmpty ? "Untitled" : cleaned
}

private func attendeeListText(_ emails: [String]) -> String {
  emails.isEmpty ? "No attendees" : emails.map { "- \($0)" }.joined(separator: "\n")
}

private func formatEventRange(_ event: GoogleEvent) -> String {
  let start = event.start?.dateTime ?? event.start?.date ?? ""
  let end = event.end?.dateTime ?? event.end?.date ?? ""
  let startText = formatDateTime(start)
  let endText = formatDateTime(end)
  if startText.isEmpty { return endText }
  if endText.isEmpty { return startText }
  return "\(startText) - \(endText)"
}

private func formatEventDate(_ event: GoogleEvent) -> String {
  let value = event.start?.dateTime ?? event.start?.date ?? ""
  if let date = ISO8601DateFormatter.shared.date(fromAnyInternetDate: value) {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
  }
  return String(value.prefix(10))
}

private func formatDateTime(_ value: String) -> String {
  if let date = ISO8601DateFormatter.shared.date(fromAnyInternetDate: value) {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
  return value
}

private func formatTime(_ value: String) -> String {
  guard let date = ISO8601DateFormatter.shared.date(fromAnyInternetDate: value) else { return "" }
  let formatter = DateFormatter()
  formatter.dateStyle = .none
  formatter.timeStyle = .short
  return formatter.string(from: date)
}

private func emailDomain(_ email: String?) -> String? {
  email?.split(separator: "@").last.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}

private func isExternalEmail(_ email: String, ownerDomain: String?) -> Bool {
  guard let ownerDomain, !ownerDomain.isEmpty else { return true }
  return emailDomain(email) != ownerDomain
}

private func escapeDriveQuery(_ value: String) -> String {
  value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
}

private func buildFolderListQuery(parent: DriveFolderRef) -> String {
  let base = "mimeType='\(folderMimeType)' and trashed=false"
  if parent.source == .sharedWithMe, parent.id == "shared-with-me" {
    return "\(base) and sharedWithMe=true"
  }
  return "\(base) and '\(escapeDriveQuery(parent.id))' in parents"
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
