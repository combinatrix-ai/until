import AppKit
import EventKit
import Foundation

/// Prefix for Mac calendar ids, keeping them apart from Google's
/// `email::calendarId` keys in selections and filter rules.
let macCalendarIdPrefix = "eventkit::"

func macCalendarKey(_ calendarIdentifier: String) -> String {
  macCalendarIdPrefix + calendarIdentifier
}

enum MacCalendarAccess: Equatable {
  case notDetermined
  case denied
  case restricted
  /// macOS 14+ can grant add-only access, which cannot read events.
  case writeOnly
  case authorized

  var label: String {
    switch self {
    case .notDetermined: return loc("Not Determined")
    case .denied: return loc("Denied")
    case .restricted: return loc("Restricted")
    case .writeOnly: return loc("Add-only")
    case .authorized: return loc("Authorized")
    }
  }
}

/// Reads the Calendar app's events through EventKit. Everything stays on the
/// Mac: no sign-in, no network, and read-only.
@MainActor
final class MacCalendarSource {
  private let store = EKEventStore()

  static func access() -> MacCalendarAccess {
    let status = EKEventStore.authorizationStatus(for: .event)
    switch status {
    case .notDetermined: return .notDetermined
    case .restricted: return .restricted
    case .denied: return .denied
    default: return grantedAccess(status)
    }
  }

  /// macOS 14 split the old "authorized" into full and write-only access;
  /// only full access can read events.
  private static func grantedAccess(_ status: EKAuthorizationStatus) -> MacCalendarAccess {
    if #available(macOS 14.0, *) {
      return status == .fullAccess ? .authorized : .writeOnly
    }
    return .authorized
  }

  /// Shows the system prompt when access hasn't been decided yet. Returns
  /// whether events can be read afterwards.
  func requestAccess() async -> Bool {
    do {
      if #available(macOS 14.0, *) {
        _ = try await store.requestFullAccessToEvents()
      } else {
        _ = try await store.requestAccess(to: .event)
      }
    } catch {
      return false
    }
    store.reset()
    return Self.access() == .authorized
  }

  func calendars(
    selections: [String: Bool],
    googleAccountEmails: [String]
  ) -> [CalendarSummary] {
    guard Self.access() == .authorized else { return [] }
    let googleEmails = Set(googleAccountEmails.map { $0.lowercased() })
    return store.calendars(for: .event).map { calendar in
      let key = macCalendarKey(calendar.calendarIdentifier)
      let sourceTitle = calendar.source?.title ?? ""
      let duplicate = googleEmails.contains(sourceTitle.lowercased())
      return CalendarSummary(
        id: key,
        googleId: calendar.calendarIdentifier,
        name: calendar.title,
        primary: false,
        backgroundColor: calendar.color.map(hexString(for:)) ?? "#888888",
        selected: isMacCalendarSelected(key, duplicatesGoogleAccount: duplicate, selections: selections),
        accountEmail: sourceTitle.contains("@") ? sourceTitle : "",
        source: .eventKit,
        sourceTitle: sourceTitle,
        duplicatesGoogleAccount: duplicate
      )
    }
  }

  func events(
    calendars summaries: [CalendarSummary],
    lookaheadHours: Int,
    now: Date
  ) -> [CalendarEvent] {
    guard Self.access() == .authorized else { return [] }
    let wanted = Set(summaries.map(\.googleId))
    let ekCalendars = store.calendars(for: .event).filter { wanted.contains($0.calendarIdentifier) }
    guard !ekCalendars.isEmpty else { return [] }
    let byId = Dictionary(summaries.map { ($0.googleId, $0) }, uniquingKeysWith: { first, _ in first })
    // Same window as the Google fetch: from local midnight so today's finished
    // events can sit above the now-line.
    let start = Calendar.current.startOfDay(for: now)
    let end = now.addingTimeInterval(TimeInterval(lookaheadHours) * 3600)
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: ekCalendars)
    return store.events(matching: predicate).compactMap { event in
      guard let calendar = event.calendar, let summary = byId[calendar.calendarIdentifier] else { return nil }
      return MacCalendarEventInput(event).makeEvent(calendar: summary, now: now)
    }
    .sorted { $0.startDate < $1.startDate }
  }
}

/// Calendars without an explicit choice are on, except those whose account is
/// already connected directly to Google (they would show every event twice).
func isMacCalendarSelected(
  _ key: String,
  duplicatesGoogleAccount: Bool,
  selections: [String: Bool]
) -> Bool {
  selections[key] ?? !duplicatesGoogleAccount
}

/// The EventKit fields Until uses, copied into a plain value so the mapping to
/// `CalendarEvent` is testable without a calendar database.
struct MacCalendarEventInput {
  struct Participant {
    var email: String
    var name: String
    var status: String
    var isCurrentUser: Bool
    var isResource: Bool
  }

  var itemIdentifier: String
  var eventIdentifier: String?
  var title: String?
  var notes: String?
  var location: String?
  var url: String?
  var startDate: Date
  var endDate: Date
  var isAllDay: Bool
  var status: String
  var isFree: Bool
  var isRecurring: Bool
  var organizerEmail: String
  var participants: [Participant]

  init(
    itemIdentifier: String,
    eventIdentifier: String? = nil,
    title: String?,
    notes: String? = nil,
    location: String? = nil,
    url: String? = nil,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool = false,
    status: String = "confirmed",
    isFree: Bool = false,
    isRecurring: Bool = false,
    organizerEmail: String = "",
    participants: [Participant] = []
  ) {
    self.itemIdentifier = itemIdentifier
    self.eventIdentifier = eventIdentifier
    self.title = title
    self.notes = notes
    self.location = location
    self.url = url
    self.startDate = startDate
    self.endDate = endDate
    self.isAllDay = isAllDay
    self.status = status
    self.isFree = isFree
    self.isRecurring = isRecurring
    self.organizerEmail = organizerEmail
    self.participants = participants
  }

  init(_ event: EKEvent) {
    let status: String
    switch event.status {
    case .canceled: status = "cancelled"
    case .tentative: status = "tentative"
    default: status = "confirmed"
    }
    self.init(
      itemIdentifier: event.calendarItemIdentifier,
      eventIdentifier: event.eventIdentifier,
      title: event.title,
      notes: event.notes,
      location: event.location,
      url: event.url?.absoluteString,
      startDate: event.startDate,
      endDate: event.endDate,
      isAllDay: event.isAllDay,
      status: status,
      isFree: event.availability == .free,
      isRecurring: event.hasRecurrenceRules,
      organizerEmail: event.organizer.map { emailAddress(from: $0.url) } ?? "",
      participants: (event.attendees ?? []).map { participant in
        let email = emailAddress(from: participant.url)
        return Participant(
          email: email,
          name: participant.name ?? email,
          status: participantStatus(participant.participantStatus),
          isCurrentUser: participant.isCurrentUser,
          isResource: participant.participantType == .room || participant.participantType == .resource
        )
      }
    )
  }

  /// EventKit ends an all-day event either at the next midnight or at
  /// 23:59:59 of its last day; Google (and the rest of the app) use an
  /// exclusive next-midnight end.
  private var normalizedBounds: (start: Date, end: Date) {
    guard isAllDay else { return (startDate, endDate) }
    let calendar = Calendar.current
    let lastDay = calendar.startOfDay(for: max(startDate, endDate.addingTimeInterval(-1)))
    return (calendar.startOfDay(for: startDate), calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay)
  }

  private var attendees: [Attendee] {
    participants.map {
      Attendee(
        email: $0.email,
        name: $0.name,
        responseStatus: $0.status,
        selfUser: $0.isCurrentUser,
        resource: $0.isResource
      )
    }
  }

  func makeEvent(calendar: CalendarSummary, now: Date) -> CalendarEvent? {
    let (start, end) = normalizedBounds
    guard end >= start else { return nil }
    let attendees = self.attendees
    let conference = [url, location, notes]
      .lazy
      .compactMap { extractMeetingURL($0) }
      .first ?? ""
    let notesURL = GoogleDocLinks.documentURL(from: notes) ?? ""
    let links = eventLinks(description: notes, extra: [url], excluding: [conference, notesURL])
    return CalendarEvent(
      id: "\(itemIdentifier)::\(Int(start.timeIntervalSince1970))",
      title: (title?.isEmpty == false ? title : nil) ?? "(no title)",
      description: notes ?? "",
      location: location ?? "",
      startISO: ISO8601DateFormatter.fallback.string(from: start),
      endISO: ISO8601DateFormatter.fallback.string(from: end),
      allDay: isAllDay,
      status: status,
      startMinutesFromNow: Int((start.timeIntervalSince(now) / 60).rounded()),
      durationMinutes: max(0, Int((end.timeIntervalSince(start) / 60).rounded())),
      calendar: CalendarRef(
        id: calendar.id,
        googleId: calendar.googleId,
        primary: false,
        backgroundColor: calendar.backgroundColor,
        source: .eventKit
      ),
      account: AccountRef(email: calendar.accountEmail),
      attendees: attendees,
      organizer: organizerEmail,
      selfResponse: attendees.first(where: \.selfUser)?.responseStatus ?? "none",
      isRecurring: isRecurring,
      conferenceUrl: conference,
      notesUrl: notesURL,
      colorId: "",
      transparency: isFree ? "free" : "busy",
      htmlLink: calendarAppURL(eventIdentifier: eventIdentifier) ?? "",
      links: links
    )
  }
}

/// Opens the event in the Calendar app (the scheme Calendar registers for
/// its own events).
private func calendarAppURL(eventIdentifier: String?) -> String? {
  guard let eventIdentifier, !eventIdentifier.isEmpty else { return nil }
  // Identifiers look like "UUID:UUID"; Calendar expects the colon as is.
  let allowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: ":"))
  let encoded = eventIdentifier.addingPercentEncoding(withAllowedCharacters: allowed) ?? eventIdentifier
  return "ical://ekevent/\(encoded)?method=show&options=more"
}

private func emailAddress(from url: URL) -> String {
  let raw = url.absoluteString
  guard raw.lowercased().hasPrefix("mailto:") else { return "" }
  let address = String(raw.dropFirst("mailto:".count))
  return (address.removingPercentEncoding ?? address).lowercased()
}

private func participantStatus(_ status: EKParticipantStatus) -> String {
  switch status {
  case .accepted, .delegated, .completed, .inProcess: return "accepted"
  case .declined: return "declined"
  case .tentative: return "tentative"
  default: return "needsAction"
  }
}

private func hexString(for color: NSColor) -> String {
  guard let rgb = color.usingColorSpace(.sRGB) else { return "#888888" }
  let red = Int((rgb.redComponent * 255).rounded())
  let green = Int((rgb.greenComponent * 255).rounded())
  let blue = Int((rgb.blueComponent * 255).rounded())
  return String(format: "#%02X%02X%02X", red, green, blue)
}

/// Mac calendars mirror accounts the user may also connect to Google directly,
/// and the same invitation can land in two Mac calendars. Google copies win
/// (they carry notes and Meet actions); otherwise the first copy wins.
func mergingCalendarSources(_ events: [CalendarEvent]) -> [CalendarEvent] {
  func key(_ event: CalendarEvent) -> String {
    let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return "\(title)|\(event.startDate.timeIntervalSince1970)|\(event.endDate.timeIntervalSince1970)|\(event.allDay)"
  }
  let googleKeys = Set(events.filter { $0.source == .google }.map(key))
  var seenMacKeys: Set<String> = []
  return events.filter { event in
    guard event.source == .eventKit else { return true }
    let eventKey = key(event)
    guard !googleKeys.contains(eventKey) else { return false }
    return seenMacKeys.insert(eventKey).inserted
  }
}

/// Up to three links from an event's description and attachments that are not
/// the meeting link itself — the doc, design, or PR the meeting is about.
func eventLinks(
  description: String?,
  attachments: [EventLink] = [],
  extra: [String?] = [],
  excluding excluded: [String]
) -> [EventLink] {
  var seen = Set(excluded)
  var links: [EventLink] = []
  func append(_ link: EventLink) {
    guard links.count < 3, !link.url.isEmpty, seen.insert(link.url).inserted else { return }
    guard EventLinks.meetingProvider(for: link.url) == nil else { return }
    links.append(link)
  }
  attachments.forEach(append)
  let candidates = extra.compactMap { $0 } + allURLs(in: description)
  for url in candidates {
    append(EventLink(title: linkTitle(for: url), url: url))
  }
  return links
}

private func allURLs(in text: String?) -> [String] {
  guard let text, !text.isEmpty else { return [] }
  let decoded = decodeHtmlEntities(text)
  let pattern = #"\bhttps?://[^\s<>"')\]}]+"#
  guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
  let range = NSRange(decoded.startIndex..<decoded.endIndex, in: decoded)
  return regex.matches(in: decoded, range: range).compactMap { match in
    Range(match.range, in: decoded).map {
      String(decoded[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
    }
  }
}

/// Hosts with a well-known product name, matched on the domain or any
/// subdomain of it.
private let linkProductNames: [(domain: String, name: String)] = [
  ("drive.google.com", "Google Drive"),
  ("figma.com", "Figma"),
  ("notion.so", "Notion"),
  ("notion.site", "Notion"),
  ("atlassian.net", "Jira"),
  ("linear.app", "Linear"),
  ("miro.com", "Miro")
]

private let googleDocKinds: [(path: String, name: String)] = [
  ("/document", "Google Doc"),
  ("/spreadsheets", "Google Sheet"),
  ("/presentation", "Google Slides"),
  ("/forms", "Google Form")
]

/// A short, recognizable label for a link chip.
func linkTitle(for rawURL: String) -> String {
  guard let url = URL(string: rawURL), let host = url.host?.lowercased() else { return rawURL }
  if host == "docs.google.com", let kind = googleDocKinds.first(where: { url.path.hasPrefix($0.path) }) {
    return kind.name
  }
  if host == "github.com" {
    return gitHubLinkTitle(path: url.path)
  }
  if let product = linkProductNames.first(where: { host == $0.domain || host.hasSuffix("." + $0.domain) }) {
    return product.name
  }
  return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

private func gitHubLinkTitle(path: String) -> String {
  let parts = path.split(separator: "/")
  guard parts.count >= 4 else { return "GitHub" }
  switch parts[2] {
  case "pull": return "PR #\(parts[3])"
  case "issues": return "Issue #\(parts[3])"
  default: return "GitHub"
  }
}
