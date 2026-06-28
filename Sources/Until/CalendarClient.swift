import Foundation

@MainActor
final class CalendarClient {
  private let auth: GoogleAuth
  private let base = URL(string: "https://www.googleapis.com/calendar/v3")!

  init(auth: GoogleAuth) {
    self.auth = auth
  }

  func listCalendars(selectedIds: [String]) async throws -> [CalendarSummary] {
    let data: CalendarListResponse = try await get(base.appending(path: "users/me/calendarList")
      .appending(queryItems: [URLQueryItem(name: "minAccessRole", value: "reader")]))
    let allSelected = selectedIds.isEmpty
    return data.items.map { item in
      let key = calendarKey(accountEmail: auth.email, calendarId: item.id)
      return CalendarSummary(
        id: key,
        googleId: item.id,
        name: item.summaryOverride ?? item.summary,
        primary: item.primary ?? false,
        backgroundColor: item.backgroundColor ?? "#888",
        selected: allSelected || selectedIds.contains(key) || selectedIds.contains(item.id),
        accountEmail: auth.email
      )
    }
  }

  func fetchEvents(selectedIds: [String], lookaheadHours: Int, now: Date) async throws -> [CalendarEvent] {
    let calendars = try await listCalendars(selectedIds: selectedIds).filter(\.selected)
    let timeMin = ISO8601DateFormatter.fallback.string(from: now)
    let timeMax = ISO8601DateFormatter.fallback.string(
      from: now.addingTimeInterval(TimeInterval(lookaheadHours) * 3600)
    )

    var events: [CalendarEvent] = []
    for calendar in calendars {
      let url = base
        .appending(path: "calendars")
        .appending(path: calendar.googleId)
        .appending(path: "events")
        .appending(queryItems: [
          URLQueryItem(name: "timeMin", value: timeMin),
          URLQueryItem(name: "timeMax", value: timeMax),
          URLQueryItem(name: "singleEvents", value: "true"),
          URLQueryItem(name: "orderBy", value: "startTime"),
          URLQueryItem(name: "maxResults", value: "50"),
          URLQueryItem(name: "conferenceDataVersion", value: "1")
        ])
      let response: EventsResponse = try await get(url)
      events.append(contentsOf: response.items.map { normalize($0, calendar: calendar, now: now) })
    }
    return events.sorted { $0.startDate < $1.startDate }
  }

  private func get<T: Decodable>(_ url: URL) async throws -> T {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "unknown error"
      throw AppError.message("Calendar API failed: \(body)")
    }
    return try JSONDecoder.google.decode(T.self, from: data)
  }

  private func normalize(_ raw: RawEvent, calendar: CalendarSummary, now: Date) -> CalendarEvent {
    let allDay = raw.start?.date != nil && raw.start?.dateTime == nil
    let startISO = raw.start?.dateTime ?? localStartISO(raw.start?.date)
    let endISO = raw.end?.dateTime ?? localStartISO(raw.end?.date)
    let start = ISO8601DateFormatter.shared.date(fromAnyInternetDate: startISO) ?? Date()
    let end = ISO8601DateFormatter.shared.date(fromAnyInternetDate: endISO) ?? start
    let attendees = normalizeAttendees(raw.attendees ?? [])
    let selfAttendee = attendees.first { $0.selfUser }
    let note = findExistingNote(raw)

    return CalendarEvent(
      id: raw.id,
      title: raw.summary ?? "(no title)",
      description: raw.description ?? "",
      location: raw.location ?? "",
      startISO: startISO,
      endISO: endISO,
      allDay: allDay,
      status: raw.status ?? "confirmed",
      startMinutesFromNow: Int((start.timeIntervalSince(now) / 60).rounded()),
      durationMinutes: max(0, Int((end.timeIntervalSince(start) / 60).rounded())),
      calendar: calendarRef(from: calendar),
      account: AccountRef(email: calendar.accountEmail),
      attendees: attendees,
      attendeeCount: attendees.count,
      organizer: raw.organizer?.email ?? "",
      creator: raw.creator?.email ?? "",
      selfResponse: selfAttendee?.responseStatus ?? "none",
      isRecurring: raw.recurringEventId != nil,
      hangoutLink: raw.hangoutLink ?? "",
      conferenceUrl: conferenceURL(for: raw),
      notesUrl: note?.url ?? "",
      notesFileId: note?.fileId ?? "",
      visibility: raw.visibility ?? "default",
      colorId: raw.colorId ?? "",
      transparency: raw.transparency == "transparent" ? "free" : "busy",
      htmlLink: raw.htmlLink ?? ""
    )
  }

  private func normalizeAttendees(_ rawAttendees: [RawAttendee]) -> [Attendee] {
    rawAttendees.map {
      Attendee(
        email: $0.email ?? "",
        name: $0.displayName ?? $0.email ?? "",
        responseStatus: $0.responseStatus ?? "needsAction",
        selfUser: $0.selfUser ?? false,
        organizer: $0.organizer ?? false,
        optional: $0.optional ?? false,
        resource: $0.resource ?? false
      )
    }
  }

  private func calendarRef(from calendar: CalendarSummary) -> CalendarRef {
    CalendarRef(
      id: calendar.id,
      googleId: calendar.googleId,
      name: calendar.name,
      primary: calendar.primary,
      backgroundColor: calendar.backgroundColor
    )
  }

  private func conferenceURL(for raw: RawEvent) -> String {
    firstNonEmpty(
      raw.conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri,
      raw.hangoutLink,
      extractMeetingURL(raw.location),
      extractMeetingURL(raw.description)
    )
  }
}

private struct CalendarListResponse: Decodable {
  var items: [RawCalendarListEntry] = []
}

private struct RawCalendarListEntry: Decodable {
  var id: String
  var summary: String
  var summaryOverride: String?
  var primary: Bool?
  var backgroundColor: String?
}

private struct EventsResponse: Decodable {
  var items: [RawEvent] = []
}

private struct RawEvent: Decodable {
  var id: String
  var status: String?
  var summary: String?
  var description: String?
  var location: String?
  var htmlLink: String?
  var hangoutLink: String?
  var colorId: String?
  var visibility: String?
  var transparency: String?
  var recurringEventId: String?
  var start: RawEventDate?
  var end: RawEventDate?
  var organizer: RawPerson?
  var creator: RawPerson?
  var conferenceData: RawConferenceData?
  var attendees: [RawAttendee]?
  var attachments: [RawAttachment]?
}

private struct RawEventDate: Decodable {
  var dateTime: String?
  var date: String?
}

private struct RawPerson: Decodable {
  var email: String?
  var displayName: String?
}

private struct RawConferenceData: Decodable {
  var entryPoints: [RawEntryPoint]?
}

private struct RawEntryPoint: Decodable {
  var entryPointType: String?
  var uri: String?
}

private struct RawAttendee: Decodable {
  var email: String?
  var displayName: String?
  var responseStatus: String?
  var selfUser: Bool?
  var organizer: Bool?
  var optional: Bool?
  var resource: Bool?

  enum CodingKeys: String, CodingKey {
    case email, displayName, responseStatus, organizer, optional, resource
    case selfUser = "self"
  }
}

private struct RawAttachment: Decodable {
  var fileId: String?
  var fileUrl: String?
  var title: String?
  var mimeType: String?
}

private let googleDocMimeType = "application/vnd.google-apps.document"

private func findExistingNote(_ event: RawEvent) -> (fileId: String, url: String)? {
  if let attachment = event.attachments?.first(where: isNotesAttachment), let url = attachment.fileUrl {
    return (attachment.fileId ?? GoogleDocLinks.documentId(from: url) ?? "", url)
  }
  if let descriptionUrl = GoogleDocLinks.documentURL(from: event.description) {
    return (GoogleDocLinks.documentId(from: descriptionUrl) ?? "", descriptionUrl)
  }
  return nil
}

private func isNotesAttachment(_ attachment: RawAttachment) -> Bool {
  let mimeType = attachment.mimeType ?? ""
  return mimeType == googleDocMimeType
}

private func calendarKey(accountEmail: String, calendarId: String) -> String {
  "\(accountEmail)::\(calendarId)"
}

private func localStartISO(_ date: String?) -> String {
  guard let date else { return ISO8601DateFormatter.fallback.string(from: Date()) }
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
  let local = formatter.date(from: "\(date)T00:00:00") ?? Date()
  return ISO8601DateFormatter.fallback.string(from: local)
}

private func firstNonEmpty(_ values: String?...) -> String {
  values.compactMap { value in
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }.first ?? ""
}

private func extractMeetingURL(_ text: String?) -> String? {
  guard let text, !text.isEmpty else { return nil }
  let decoded = decodeHtmlEntities(text)
  let pattern = #"\bhttps?://[^\s<>"')\]}]+"#
  let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
  let range = NSRange(decoded.startIndex..<decoded.endIndex, in: decoded)
  return regex?.matches(in: decoded, range: range).compactMap { match in
    Range(match.range, in: decoded).map {
      String(decoded[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
    }
  }.first { EventLinks.meetingProvider(for: $0) != nil }
}

private func decodeHtmlEntities(_ value: String) -> String {
  value
    .replacingOccurrences(of: "&amp;", with: "&")
    .replacingOccurrences(of: "&lt;", with: "<")
    .replacingOccurrences(of: "&gt;", with: ">")
    .replacingOccurrences(of: "&quot;", with: "\"")
    .replacingOccurrences(of: "&#39;", with: "'")
}

extension URL {
  func appending(queryItems: [URLQueryItem]) -> URL {
    var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
    components.queryItems = (components.queryItems ?? []) + queryItems
    return components.url!
  }
}
