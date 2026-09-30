import XCTest
@testable import Until

final class MeetingWorkflowTests: XCTestCase {
  // MARK: - Meeting services

  func testAddedServicesAreDetected() {
    let cases: [(String, EventLinks.MeetingProvider)] = [
      ("https://app.slack.com/huddle/T123/C456", .slackHuddle),
      ("https://discord.gg/abc", .discord),
      ("https://discord.com/channels/1/2", .discord),
      ("https://meet.jit.si/Room", .jitsi),
      ("https://facetime.apple.com/join#v=1", .faceTime),
      ("https://app.chime.aws/meetings/123", .chime),
      ("https://app.gather.town/app/x", .gather),
      ("https://zoomgov.com/j/123", .zoom),
      ("https://teams.live.com/meet/123", .teams),
      ("https://vc.larksuite.com/j/123", .larkMeetings),
      ("https://meeting.tencent.com/dm/abc", .tencentMeeting),
      ("https://app.cal.com/video/abc", .calVideo),
      ("https://signal.link/call/#key=abc", .signal)
    ]
    for (url, provider) in cases {
      XCTAssertEqual(EventLinks.meetingProvider(for: url), provider, url)
    }
    XCTAssertGreaterThanOrEqual(EventLinks.MeetingProvider.allCases.count, 30)
  }

  func testOrdinaryPagesOnCallHostsAreNotMeetings() {
    XCTAssertNil(EventLinks.meetingProvider(for: "https://acme.slack.com/archives/C123"))
    XCTAssertNil(EventLinks.meetingProvider(for: "https://discord.com/developers"))
    XCTAssertNil(EventLinks.meetingProvider(for: "https://app.cal.com/team/acme"))
    XCTAssertNil(EventLinks.meetingProvider(for: "https://signal.link/"))
  }

  func testZoomLinkBecomesAppJoinURLWithPassword() {
    let url = URL(string: "https://acme.zoom.us/j/123456789?pwd=secret")!
    XCTAssertEqual(
      EventLinks.desktopAppURL(for: url)?.absoluteString,
      "zoommtg://acme.zoom.us/join?action=join&confno=123456789&pwd=secret"
    )
  }

  func testTeamsLinkUsesTeamsScheme() {
    let url = URL(string: "https://teams.microsoft.com/l/meetup-join/abc")!
    XCTAssertEqual(EventLinks.desktopAppURL(for: url)?.absoluteString, "msteams://teams.microsoft.com/l/meetup-join/abc")
  }

  func testOtherLinksStayInTheBrowser() {
    XCTAssertNil(EventLinks.desktopAppURL(for: URL(string: "https://meet.google.com/abc-defg-hij")!))
    XCTAssertNil(EventLinks.desktopAppURL(for: URL(string: "https://zoom.us/my/vanity")!))
  }

  // MARK: - Join shortcut

  func testJoinPrefersTheMenubarMeetingWhenItHasALink() {
    let now = makeDate(year: 2026, month: 9, day: 30, hour: 10)
    let menubar = event("menubar", now: now, startOffset: 20, link: true)
    let running = event("running", now: now, startOffset: -5, link: true)

    XCTAssertEqual(AppModel.joinTarget(menubarEvent: menubar, timed: [running, menubar], now: now)?.id, "menubar")
  }

  func testJoinFallsBackToTheRunningMeeting() {
    let now = makeDate(year: 2026, month: 9, day: 30, hour: 10)
    let menubar = event("menubar", now: now, startOffset: 3, link: false)
    let older = event("older", now: now, startOffset: -40, link: true)
    let recent = event("recent", now: now, startOffset: -5, link: true)
    let soon = event("soon", now: now, startOffset: 5, link: true)

    XCTAssertEqual(
      AppModel.joinTarget(menubarEvent: menubar, timed: [older, recent, soon, menubar], now: now)?.id,
      "recent"
    )
  }

  func testJoinTakesTheSoonestUpcomingMeetingWithinFifteenMinutes() {
    let now = makeDate(year: 2026, month: 9, day: 30, hour: 10)
    let soon = event("soon", now: now, startOffset: 10, link: true)
    let later = event("later", now: now, startOffset: 30, link: true)

    XCTAssertEqual(AppModel.joinTarget(menubarEvent: nil, timed: [later, soon], now: now)?.id, "soon")
    XCTAssertNil(AppModel.joinTarget(menubarEvent: nil, timed: [later], now: now))
  }

  // MARK: - Start alert

  func testStartAlertFiresLeadMinutesBeforeTheMeeting() {
    let now = makeDate(year: 2026, month: 9, day: 30, hour: 10)
    let meeting = event("m", now: now, startOffset: 10, link: true)

    let pending = StartAlertSchedule.next(
      events: [meeting], rules: .init(style: .floating, leadMinutes: 2, videoOnly: true), handled: [], snoozed: [:], now: now
    )

    XCTAssertEqual(pending?.event.id, "m")
    XCTAssertEqual(pending?.fireDate, meeting.startDate.addingTimeInterval(-120))
  }

  func testStartAlertSkipsHandledLinklessAndLongStartedMeetings() {
    let now = makeDate(year: 2026, month: 9, day: 30, hour: 10)
    let handled = event("handled", now: now, startOffset: 5, link: true)
    let noLink = event("no-link", now: now, startOffset: 6, link: false)
    let longStarted = event("long-started", now: now, startOffset: -10, link: true)

    let pending = StartAlertSchedule.next(
      events: [handled, noLink, longStarted],
      rules: .init(style: .floating, leadMinutes: 1, videoOnly: true),
      handled: [StartAlertSchedule.key(for: handled)],
      snoozed: [:],
      now: now
    )
    XCTAssertNil(pending)

    let allEvents = StartAlertSchedule.next(
      events: [noLink], rules: .init(style: .floating, leadMinutes: 1, videoOnly: false), handled: [], snoozed: [:], now: now
    )
    XCTAssertEqual(allEvents?.event.id, "no-link")
  }

  func testSnoozedAlertReturnsAtTheSnoozeTime() {
    let now = makeDate(year: 2026, month: 9, day: 30, hour: 10)
    let meeting = event("m", now: now, startOffset: 0, link: true)
    let key = StartAlertSchedule.key(for: meeting)
    let until = now.addingTimeInterval(60)

    let pending = StartAlertSchedule.next(
      events: [meeting], rules: .init(style: .floating, leadMinutes: 1, videoOnly: true), handled: [key], snoozed: [key: until], now: now
    )

    XCTAssertEqual(pending?.fireDate, until)
  }

  // MARK: - Day summary

  func testDaySummaryMergesOverlapsAndFindsTheLongestRemainingGap() throws {
    let day = makeDate(year: 2026, month: 9, day: 30)
    let now = makeDate(year: 2026, month: 9, day: 30, hour: 9)
    let events = [
      timed("a", day: day, from: (9, 0), to: (10, 0)),
      timed("b", day: day, from: (9, 30), to: (10, 30)),
      timed("c", day: day, from: (12, 0), to: (13, 0)),
      timed("d", day: day, from: (13, 30), to: (14, 0)),
      timed("free", day: day, from: (15, 0), to: (16, 0), transparency: "free")
    ]

    let summary = try XCTUnwrap(AppModel.daySummary(timed: events, day: day, now: now))

    XCTAssertEqual(summary.eventCount, 4)
    XCTAssertEqual(summary.bookedMinutes, 180)
    XCTAssertEqual(summary.longestFreeMinutes, 90)
  }

  func testDaySummaryHasNoFreeTimeOnceTheDayIsDone() throws {
    let day = makeDate(year: 2026, month: 9, day: 30)
    let now = makeDate(year: 2026, month: 9, day: 30, hour: 18)
    let summary = try XCTUnwrap(
      AppModel.daySummary(timed: [timed("a", day: day, from: (9, 0), to: (10, 0))], day: day, now: now)
    )

    XCTAssertNil(summary.longestFreeMinutes)
    XCTAssertNil(AppModel.daySummary(timed: [], day: day, now: now))
  }

  // MARK: - Helpers

  private func event(_ id: String, now: Date, startOffset minutes: Int, link: Bool) -> CalendarEvent {
    let start = now.addingTimeInterval(TimeInterval(minutes) * 60)
    return makeEvent(
      id: id,
      title: id,
      startISO: isoString(from: start),
      endISO: isoString(from: start.addingTimeInterval(30 * 60)),
      conferenceUrl: link ? "https://meet.google.com/\(id)" : ""
    )
  }

  private func timed(
    _ id: String,
    day: Date,
    from start: (Int, Int),
    to end: (Int, Int),
    transparency: String = "busy"
  ) -> CalendarEvent {
    let calendar = Calendar.current
    let startDate = calendar.date(bySettingHour: start.0, minute: start.1, second: 0, of: day)!
    let endDate = calendar.date(bySettingHour: end.0, minute: end.1, second: 0, of: day)!
    return makeEvent(
      id: id,
      title: id,
      startISO: isoString(from: startDate),
      endISO: isoString(from: endDate),
      transparency: transparency
    )
  }
}
