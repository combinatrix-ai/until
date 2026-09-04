import Foundation

final class CalendarClient {
  private let apiClient: GoogleAPIClient
  private let base = URL(string: "https://www.googleapis.com/calendar/v3")!

  init(auth: GoogleAuth) {
    apiClient = GoogleAPIClient(auth: auth)
  }

  func listCalendars(selectedIds: [String]) async throws -> [CalendarSummary] {
    let email = await apiClient.accountEmail
    let data: CalendarListResponse = try await get(base.appending(path: "users/me/calendarList")
      .appending(queryItems: [URLQueryItem(name: "minAccessRole", value: "reader")]))
    return data.items.map { item in
      let key = calendarKey(accountEmail: email, calendarId: item.id)
      return CalendarSummary(
        id: key,
        googleId: item.id,
        name: item.summaryOverride ?? item.summary,
        primary: item.primary ?? false,
        backgroundColor: item.backgroundColor ?? "#888",
        selected: isCalendarSelected(key, selectedIds: selectedIds),
        accountEmail: email
      )
    }
  }

  /// Fetches events for the given, already-selected calendars. The caller is
  /// responsible for fetching the calendar list once per refresh (see
  /// `AppModel.refresh`) so we don't round-trip `calendarList` twice per cycle.
  /// Per-calendar fetches run concurrently.
  func fetchEvents(
    calendars: [CalendarSummary],
    lookaheadHours: Int,
    now: Date
  ) async throws -> [CalendarEvent] {
    // Fetch from local midnight so the rail can show today's completed rows
    // above its now-line. The menubar picker and notification sync still
    // ignore events that have already ended.
    let timeMin = ISO8601DateFormatter.fallback.string(from: Calendar.current.startOfDay(for: now))
    let timeMax = ISO8601DateFormatter.fallback.string(
      from: now.addingTimeInterval(TimeInterval(lookaheadHours) * 3600)
    )

    let events = try await withThrowingTaskGroup(of: [CalendarEvent].self) { group -> [CalendarEvent] in
      for calendar in calendars {
        group.addTask {
          try await self.fetchEvents(
            calendar: calendar,
            timeMin: timeMin,
            timeMax: timeMax,
            now: now
          )
        }
      }
      var collected: [CalendarEvent] = []
      for try await calendarEvents in group {
        collected.append(contentsOf: calendarEvents)
      }
      return collected
    }
    return events.sorted { $0.startDate < $1.startDate }
  }

  /// Fetches all events for a single calendar, following `nextPageToken` until
  /// the last page. Without pagination, events beyond the first page were
  /// silently dropped.
  private func fetchEvents(
    calendar: CalendarSummary,
    timeMin: String,
    timeMax: String,
    now: Date
  ) async throws -> [CalendarEvent] {
    var events: [CalendarEvent] = []
    var pageToken: String?
    repeat {
      var queryItems = [
        URLQueryItem(name: "timeMin", value: timeMin),
        URLQueryItem(name: "timeMax", value: timeMax),
        URLQueryItem(name: "singleEvents", value: "true"),
        URLQueryItem(name: "orderBy", value: "startTime"),
        URLQueryItem(name: "maxResults", value: "250"),
        URLQueryItem(name: "conferenceDataVersion", value: "1")
      ]
      if let pageToken {
        queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
      }
      let url = base
        .appending(path: "calendars")
        .appending(path: calendar.googleId)
        .appending(path: "events")
        .appending(queryItems: queryItems)
      let response: EventsResponse = try await get(url)
      events.append(contentsOf: response.items.compactMap { normalize($0, calendar: calendar, now: now) })
      pageToken = response.nextPageToken
    } while pageToken != nil
    return events
  }

  private func get<T: Decodable>(_ url: URL) async throws -> T {
    try await apiClient.request(url, errorPrefix: "Calendar API failed")
  }

  /// Returns nil (dropping the event) when the start or end timestamp fails to
  /// parse, rather than substituting the current time — a corrupt event would
  /// otherwise surface in the menubar as "happening now".
  private func normalize(_ raw: GoogleCalendarEvent, calendar: CalendarSummary, now: Date) -> CalendarEvent? {
    let allDay = raw.start?.date != nil && raw.start?.dateTime == nil
    guard let startISO = raw.start?.dateTime ?? localStartISO(raw.start?.date),
          let endISO = raw.end?.dateTime ?? localStartISO(raw.end?.date),
          let start = ISO8601DateFormatter.shared.date(fromAnyInternetDate: startISO),
          let end = ISO8601DateFormatter.shared.date(fromAnyInternetDate: endISO) else {
      return nil
    }
    let attendees = normalizeAttendees(raw.attendees ?? [])
    let selfAttendee = attendees.first { $0.selfUser }
    let noteURL = raw.existingNoteURL

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
      organizer: raw.organizer?.email ?? "",
      selfResponse: selfAttendee?.responseStatus ?? "none",
      isRecurring: raw.recurringEventId != nil,
      conferenceUrl: conferenceURL(for: raw),
      notesUrl: noteURL ?? "",
      colorId: raw.colorId ?? "",
      transparency: raw.transparency == "transparent" ? "free" : "busy",
      htmlLink: raw.htmlLink ?? ""
    )
  }

  private func normalizeAttendees(_ rawAttendees: [GoogleCalendarAttendee]) -> [Attendee] {
    rawAttendees.map {
      Attendee(
        email: $0.email ?? "",
        name: $0.displayName ?? $0.email ?? "",
        responseStatus: $0.responseStatus ?? "needsAction",
        selfUser: $0.selfUser ?? false,
        resource: $0.resource ?? false
      )
    }
  }

  private func calendarRef(from calendar: CalendarSummary) -> CalendarRef {
    CalendarRef(
      id: calendar.id,
      googleId: calendar.googleId,
      primary: calendar.primary,
      backgroundColor: calendar.backgroundColor
    )
  }

  private func conferenceURL(for raw: GoogleCalendarEvent) -> String {
    firstNonEmpty(
      raw.videoEntryPointURL,
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
  var items: [GoogleCalendarEvent] = []
  var nextPageToken: String?
}

private func calendarKey(accountEmail: String, calendarId: String) -> String {
  "\(accountEmail)::\(calendarId)"
}

/// Returns whether a calendar is selected by the persisted selection.
///
/// A non-empty selection contains account-scoped keys (`email::calendarId`).
/// Deliberately do not accept a bare Google calendar id here: the same id (most
/// notably `primary`) can exist in multiple connected accounts.
func isCalendarSelected(_ key: String, selectedIds: [String]) -> Bool {
  selectedIds.isEmpty || selectedIds.contains(key)
}

/// Converts an all-day `date` (yyyy-MM-dd) into a full ISO timestamp at local
/// midnight. Returns nil when the input is missing or unparseable so the caller
/// can drop the event instead of inventing a bogus date.
private func localStartISO(_ date: String?) -> String? {
  guard let date else { return nil }
  let formatter = DateFormatter()
  formatter.calendar = Calendar(identifier: .gregorian)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
  guard let local = formatter.date(from: "\(date)T00:00:00") else { return nil }
  return ISO8601DateFormatter.fallback.string(from: local)
}

private func firstNonEmpty(_ values: String?...) -> String {
  values.compactMap { value in
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }.first ?? ""
}

func extractMeetingURL(_ text: String?) -> String? {
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
