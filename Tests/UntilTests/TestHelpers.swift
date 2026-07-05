import Foundation
@testable import Until

/// Builds a `CalendarEvent` for tests with sensible defaults for everything
/// not relevant to the specific test. Uses the real failable memberwise init
/// from Models.swift, force-unwrapping since our fixed inputs are always
/// valid ISO8601 strings.
func makeEvent(
  id: String = "event-1",
  title: String = "Test Event",
  description: String = "",
  location: String = "",
  startISO: String = "2026-07-05T10:00:00Z",
  endISO: String = "2026-07-05T11:00:00Z",
  allDay: Bool = false,
  status: String = "confirmed",
  startMinutesFromNow: Int = 0,
  durationMinutes: Int = 60,
  calendar: CalendarRef = CalendarRef(
    id: "cal-1", googleId: "cal-1@group.calendar.google.com", name: "Primary",
    primary: true, backgroundColor: "#888"
  ),
  account: AccountRef = AccountRef(email: "user@example.com"),
  attendees: [Attendee] = [],
  attendeeCount: Int = 0,
  organizer: String = "",
  creator: String = "",
  selfResponse: String = "accepted",
  isRecurring: Bool = false,
  hangoutLink: String = "",
  conferenceUrl: String = "",
  notesUrl: String = "",
  notesFileId: String = "",
  visibility: String = "default",
  colorId: String = "",
  transparency: String = "busy",
  htmlLink: String = ""
) -> CalendarEvent {
  guard let event = CalendarEvent(
    id: id,
    title: title,
    description: description,
    location: location,
    startISO: startISO,
    endISO: endISO,
    allDay: allDay,
    status: status,
    startMinutesFromNow: startMinutesFromNow,
    durationMinutes: durationMinutes,
    calendar: calendar,
    account: account,
    attendees: attendees,
    attendeeCount: attendeeCount,
    organizer: organizer,
    creator: creator,
    selfResponse: selfResponse,
    isRecurring: isRecurring,
    hangoutLink: hangoutLink,
    conferenceUrl: conferenceUrl,
    notesUrl: notesUrl,
    notesFileId: notesFileId,
    visibility: visibility,
    colorId: colorId,
    transparency: transparency,
    htmlLink: htmlLink
  ) else {
    fatalError("makeEvent: failed to construct test CalendarEvent (bad ISO date string?)")
  }
  return event
}

/// Builds a fixed `Date` from components in the current calendar/timezone,
/// so tests don't depend on wall-clock time.
func makeDate(
  year: Int, month: Int, day: Int,
  hour: Int = 0, minute: Int = 0, second: Int = 0
) -> Date {
  var components = DateComponents()
  components.year = year
  components.month = month
  components.day = day
  components.hour = hour
  components.minute = minute
  components.second = second
  guard let date = Calendar.current.date(from: components) else {
    fatalError("makeDate: failed to construct date from components")
  }
  return date
}

/// ISO8601 string (UTC, with fractional seconds) for a given date, matching
/// what CalendarEvent's init expects to be able to parse.
func isoString(from date: Date) -> String {
  ISO8601DateFormatter.shared.string(from: date)
}
