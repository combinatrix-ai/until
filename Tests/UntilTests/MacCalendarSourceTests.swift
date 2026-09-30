import XCTest
@testable import Until

final class MacCalendarSourceTests: XCTestCase {
  private let calendar = CalendarSummary(
    id: macCalendarKey("ek-cal-1"),
    googleId: "ek-cal-1",
    name: "Work",
    primary: false,
    backgroundColor: "#007AFF",
    selected: true,
    accountEmail: "me@example.com",
    source: .eventKit,
    sourceTitle: "me@example.com"
  )

  func testTimedEventMapsFieldsAndMarksSourceAsEventKit() throws {
    let start = makeDate(year: 2026, month: 9, day: 30, hour: 10)
    let input = MacCalendarEventInput(
      itemIdentifier: "item-1",
      eventIdentifier: "EV:1",
      title: "Design review",
      notes: "Agenda: https://docs.google.com/document/d/abc/edit\nJoin: https://meet.google.com/abc-defg-hij",
      location: "Room 4",
      startDate: start,
      endDate: start.addingTimeInterval(45 * 60),
      status: "tentative",
      isFree: true,
      isRecurring: true,
      organizerEmail: "boss@example.com",
      participants: [
        .init(email: "me@example.com", name: "Me", status: "declined", isCurrentUser: true, isResource: false),
        .init(email: "room@example.com", name: "Room 4", status: "accepted", isCurrentUser: false, isResource: true)
      ]
    )

    let event = try XCTUnwrap(input.makeEvent(calendar: calendar, now: start.addingTimeInterval(-600)))

    XCTAssertEqual(event.source, .eventKit)
    XCTAssertEqual(event.calendar.id, calendar.id)
    XCTAssertEqual(event.title, "Design review")
    XCTAssertEqual(event.durationMinutes, 45)
    XCTAssertEqual(event.startMinutesFromNow, 10)
    XCTAssertEqual(event.status, "tentative")
    XCTAssertEqual(event.transparency, "free")
    XCTAssertTrue(event.isRecurring)
    XCTAssertEqual(event.organizer, "boss@example.com")
    XCTAssertEqual(event.selfResponse, "declined")
    XCTAssertEqual(event.attendees.filter(\.resource).count, 1)
    XCTAssertEqual(event.conferenceUrl, "https://meet.google.com/abc-defg-hij")
    XCTAssertEqual(event.notesUrl, "https://docs.google.com/document/d/abc/edit")
    XCTAssertEqual(event.htmlLink, "ical://ekevent/EV:1?method=show&options=more")
    XCTAssertEqual(event.account.email, "me@example.com")
  }

  func testMeetingLinkInURLFieldWinsOverNotes() throws {
    let start = makeDate(year: 2026, month: 9, day: 30, hour: 10)
    let input = MacCalendarEventInput(
      itemIdentifier: "item-2",
      title: "Sync",
      notes: "https://zoom.us/j/111",
      url: "https://teams.microsoft.com/l/meetup-join/abc",
      startDate: start,
      endDate: start.addingTimeInterval(1800)
    )

    let event = try XCTUnwrap(input.makeEvent(calendar: calendar, now: start))

    XCTAssertEqual(event.conferenceUrl, "https://teams.microsoft.com/l/meetup-join/abc")
    XCTAssertEqual(event.selfResponse, "none")
  }

  func testAllDayEventEndingAtLastSecondBecomesExclusiveMidnight() throws {
    let day = makeDate(year: 2026, month: 9, day: 30)
    let input = MacCalendarEventInput(
      itemIdentifier: "item-3",
      title: "Offsite",
      startDate: day,
      endDate: makeDate(year: 2026, month: 10, day: 1, hour: 23, minute: 59, second: 59),
      isAllDay: true
    )

    let event = try XCTUnwrap(input.makeEvent(calendar: calendar, now: day))

    XCTAssertTrue(event.allDay)
    XCTAssertEqual(event.startDate, day)
    XCTAssertEqual(event.endDate, makeDate(year: 2026, month: 10, day: 2))
  }

  func testAllDayEventEndingAtNextMidnightKeepsItsLength() throws {
    let day = makeDate(year: 2026, month: 9, day: 30)
    let input = MacCalendarEventInput(
      itemIdentifier: "item-4",
      title: "Holiday",
      startDate: day,
      endDate: makeDate(year: 2026, month: 10, day: 1),
      isAllDay: true
    )

    let event = try XCTUnwrap(input.makeEvent(calendar: calendar, now: day))

    XCTAssertEqual(event.endDate, makeDate(year: 2026, month: 10, day: 1))
    XCTAssertEqual(event.durationMinutes, 24 * 60)
  }

  func testUntitledEventGetsPlaceholderTitle() throws {
    let start = makeDate(year: 2026, month: 9, day: 30, hour: 9)
    let input = MacCalendarEventInput(
      itemIdentifier: "item-5",
      title: "",
      startDate: start,
      endDate: start.addingTimeInterval(600)
    )

    XCTAssertEqual(try XCTUnwrap(input.makeEvent(calendar: calendar, now: start)).title, "(no title)")
  }

  func testMacCalendarDefaultsOnUnlessItDuplicatesAGoogleAccount() {
    let key = macCalendarKey("abc")
    XCTAssertTrue(isMacCalendarSelected(key, duplicatesGoogleAccount: false, selections: [:]))
    XCTAssertFalse(isMacCalendarSelected(key, duplicatesGoogleAccount: true, selections: [:]))
    XCTAssertTrue(isMacCalendarSelected(key, duplicatesGoogleAccount: true, selections: [key: true]))
    XCTAssertFalse(isMacCalendarSelected(key, duplicatesGoogleAccount: false, selections: [key: false]))
  }

  func testMergingDropsMacCopiesOfGoogleEventsAndRepeatedMacCopies() {
    let macRef = CalendarRef(id: "eventkit::a", googleId: "a", primary: false, backgroundColor: "#888", source: .eventKit)
    let otherMacRef = CalendarRef(id: "eventkit::b", googleId: "b", primary: false, backgroundColor: "#888", source: .eventKit)
    let google = makeEvent(id: "g1", title: "Standup")
    let macCopy = makeEvent(id: "m1", title: " standup ", calendar: macRef)
    let macOnly = makeEvent(id: "m2", title: "Dentist", calendar: macRef)
    let macOnlyAgain = makeEvent(id: "m3", title: "Dentist", calendar: otherMacRef)
    let laterMac = makeEvent(
      id: "m4",
      title: "Standup",
      startISO: "2026-07-06T10:00:00Z",
      endISO: "2026-07-06T11:00:00Z",
      calendar: macRef
    )

    let merged = mergingCalendarSources([google, macCopy, macOnly, macOnlyAgain, laterMac])

    XCTAssertEqual(merged.map(\.id), ["g1", "m2", "m4"])
  }

  func testMacEventsOfferNoGoogleOnlyActions() {
    let macRef = CalendarRef(id: "eventkit::a", googleId: "a", primary: false, backgroundColor: "#888", source: .eventKit)
    let actions = EventActionSet.make(event: makeEvent(calendar: macRef), noteURL: nil, isSkipped: false)

    XCTAssertTrue(actions.addable.isEmpty)
    XCTAssertEqual(actions.common, [.copyDetails, .openInCalendar, .skipInMenubar])
  }

  func testEventLinksSkipMeetingAndNotesLinksAndCapAtThree() {
    let description = """
    Spec https://docs.google.com/document/d/spec/edit
    Design https://www.figma.com/file/xyz
    PR https://github.com/acme/app/pull/847
    Board https://linear.app/acme/issue/ACME-1
    Call https://zoom.us/j/123
    """
    let links = eventLinks(
      description: description,
      excluding: ["https://docs.google.com/document/d/spec/edit"]
    )

    XCTAssertEqual(links.map(\.title), ["Figma", "PR #847", "Linear"])
  }

  func testLinkTitlesAreRecognizable() {
    XCTAssertEqual(linkTitle(for: "https://docs.google.com/spreadsheets/d/1"), "Google Sheet")
    XCTAssertEqual(linkTitle(for: "https://github.com/acme/app/issues/12"), "Issue #12")
    XCTAssertEqual(linkTitle(for: "https://acme.atlassian.net/browse/X-1"), "Jira")
    XCTAssertEqual(linkTitle(for: "https://www.example.com/page"), "example.com")
  }

  func testLegacyConfigDecodesNewSettingsWithDefaults() throws {
    let json = #"{"oauth":{"clientId":"x"},"filterRules":{"kind":"group","op":"and","children":[]}}"#
    let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))

    XCTAssertFalse(config.macCalendarsEnabled)
    XCTAssertTrue(config.macCalendarSelections.isEmpty)
    XCTAssertFalse(config.joinHotkeyEnabled)
    XCTAssertEqual(config.joinHotkeyPreset, "ctrl-opt-j")
    XCTAssertFalse(config.openMeetingsInApps)
    XCTAssertEqual(config.startAlertStyle, StartAlertStyle.off.rawValue)
    XCTAssertTrue(config.menubarShowsTitle)
  }

  func testNewSettingsRoundTrip() throws {
    var config = AppConfig.default
    config.macCalendarsEnabled = true
    config.macCalendarSelections = [macCalendarKey("a"): false]
    config.startAlertStyle = StartAlertStyle.fullScreen.rawValue
    config.menubarShowsTitle = false

    let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))

    XCTAssertTrue(decoded.macCalendarsEnabled)
    XCTAssertEqual(decoded.macCalendarSelections, [macCalendarKey("a"): false])
    XCTAssertEqual(decoded.startAlertStyle, StartAlertStyle.fullScreen.rawValue)
    XCTAssertFalse(decoded.menubarShowsTitle)
  }
}
