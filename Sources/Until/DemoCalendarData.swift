import Foundation

struct AppRuntimeOptions: Hashable {
  var demoMode: Bool

  static func fromProcess(
    arguments: [String] = CommandLine.arguments,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> AppRuntimeOptions {
    let demoFlags = Set(["--demo-mode"])
    let hasFlag = arguments.dropFirst().contains { demoFlags.contains($0) }
    let envValue = environment["UNTIL_DEMO_MODE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let hasEnv = ["1", "true", "yes", "on"].contains(envValue ?? "")
    return AppRuntimeOptions(demoMode: hasFlag || hasEnv)
  }
}

enum DemoCalendarData {
  static let personalAccountEmail = "personal@example.com"
  static let workAccountEmail = "work@example.com"
  static let accountEmails = [personalAccountEmail, workAccountEmail]

  static func config() -> AppConfig {
    var config = AppConfig.default
    config.filterRules = Rule.group(.and, [
      .condition("selfResponse", "is_not", .string("declined")),
      .condition("status", "is_not", .string("cancelled"))
    ])
    config.selectedCalendarIds = []
    config.lookaheadHours = 48
    config.pollIntervalSeconds = 120
    config.maxTitleLength = 48
    config.menubarLeadMinutes = 45
    config.notifyEnabled = false
    config.notifyVideoOnly = false
    return config
  }

  static func accountState() -> AuthState {
    AuthState(
      authenticated: true,
      email: personalAccountEmail,
      accounts: accountEmails.map { AccountState(email: $0, authenticated: true) }
    )
  }

  static func calendars(selectedIds: [String]) -> [CalendarSummary] {
    let allSelected = selectedIds.isEmpty
    return calendarDefinitions.map { definition in
      CalendarSummary(
        id: definition.id,
        googleId: definition.googleId,
        name: definition.name,
        primary: definition.primary,
        backgroundColor: definition.backgroundColor,
        selected: allSelected || selectedIds.contains(definition.id) || selectedIds.contains(definition.googleId),
        accountEmail: definition.accountEmail
      )
    }
  }

  static func events(now: Date, selectedIds: [String]) -> [CalendarEvent] {
    let selectedCalendars = calendars(selectedIds: selectedIds).filter(\.selected)
    let selectedCalendarIds = Set(selectedCalendars.map(\.id))
    return eventDefinitions(now: now)
      .filter { selectedCalendarIds.contains($0.calendar.id) }
      .sorted { $0.startDate < $1.startDate }
  }

  static func noteResult(for event: CalendarEvent) -> MeetingNoteResult {
    MeetingNoteResult(
      fileId: "demo-note-\(event.id)",
      fileName: "Meeting notes - \(event.title)",
      webViewLink: "https://docs.google.com/document/d/demo-\(event.id)/edit",
      folderId: "demo-meeting-notes",
      sharedWith: event.attendees.filter { !$0.selfUser && !$0.resource }.map(\.email),
      skippedExternal: [],
      reused: false
    )
  }

  private static let calendarDefinitions: [CalendarDefinition] = [
    CalendarDefinition(
      accountEmail: personalAccountEmail,
      googleId: "primary",
      name: "Personal",
      primary: true,
      backgroundColor: "#5484ed"
    ),
    CalendarDefinition(
      accountEmail: personalAccountEmail,
      googleId: "family",
      name: "Family",
      primary: false,
      backgroundColor: "#f4511e"
    ),
    CalendarDefinition(
      accountEmail: workAccountEmail,
      googleId: "primary",
      name: "Acme Work",
      primary: true,
      backgroundColor: "#16a765"
    ),
    CalendarDefinition(
      accountEmail: workAccountEmail,
      googleId: "launch",
      name: "Launch Team",
      primary: false,
      backgroundColor: "#8e24aa"
    )
  ]

  private static func eventDefinitions(now: Date) -> [CalendarEvent] {
    let today = Calendar.current.startOfDay(for: now)
    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
    let context = DemoContext(
      now: now,
      nextSlot: nextHalfHour(after: now),
      personal: calendarRef(for: calendarDefinitions[0]),
      family: calendarRef(for: calendarDefinitions[1]),
      work: calendarRef(for: calendarDefinitions[2]),
      launch: calendarRef(for: calendarDefinitions[3]),
      today: today,
      tomorrow: tomorrow,
      dayAfterTomorrow: Calendar.current.date(byAdding: .day, value: 2, to: today) ?? tomorrow
    )
    let specs = runAndLaunchSpecs(context)
      + reviewAndCaptureSpecs(context)
      + syncAndFocusSpecs(context)
      + holdAndPickupSpecs(context)
      + tomorrowSpecs(context)
    return specs.compactMap { event($0, now: now) }
  }

  private static func runAndLaunchSpecs(_ ctx: DemoContext) -> [DemoEventSpec] {
    [
      DemoEventSpec(
        id: "morning-run",
        title: "Morning run",
        description: "Keep the day clear before capture work starts.",
        location: "Riverside Park",
        start: minutes(from: ctx.nextSlot, 30),
        end: minutes(from: ctx.nextSlot, 75),
        calendar: ctx.personal,
        accountEmail: personalAccountEmail,
        colorId: "9",
        transparency: "free"
      ),
      DemoEventSpec(
        id: "launch-assets-due",
        title: "Launch assets due",
        description: "Final images, tablet captures, and mobile screenshots for the website.",
        start: ctx.today,
        end: ctx.tomorrow,
        allDay: true,
        calendar: ctx.launch,
        accountEmail: workAccountEmail,
        notesUrl: "https://docs.google.com/document/d/demo-launch-assets/edit",
        colorId: "9",
        transparency: "busy"
      )
    ]
  }

  private static func reviewAndCaptureSpecs(_ ctx: DemoContext) -> [DemoEventSpec] {
    [
      DemoEventSpec(
        id: "design-review",
        title: "Design review: website screenshots",
        description: "Pick the strongest Until states for the landing page and press kit.",
        location: "Google Meet",
        start: ctx.nextSlot,
        end: minutes(from: ctx.nextSlot, 45),
        calendar: ctx.launch,
        accountEmail: workAccountEmail,
        attendees: [
          attendee("maya@acme.co", "Maya Chen", "accepted"),
          attendee("ren@acme.co", "Ren Sato", "tentative")
        ],
        conferenceUrl: "https://meet.google.com/abc-defg-hij",
        notesUrl: "https://docs.google.com/document/d/demo-design-review/edit",
        colorId: "9",
        transparency: "busy"
      ),
      DemoEventSpec(
        id: "anka-capture",
        title: "Project work block",
        description: "Protected time for focused follow-up and final details.",
        location: "Desk",
        start: minutes(from: ctx.nextSlot, 90),
        end: minutes(from: ctx.nextSlot, 150),
        calendar: ctx.work,
        accountEmail: workAccountEmail,
        attendees: [attendee(workAccountEmail, "John", "accepted", selfUser: true)],
        colorId: "6",
        transparency: "busy"
      )
    ]
  }

  private static func syncAndFocusSpecs(_ ctx: DemoContext) -> [DemoEventSpec] {
    [
      DemoEventSpec(
        id: "product-sync",
        title: "Product sync",
        description: "Review OAuth copy, notification timing, and meeting notes behavior.",
        location: "Google Meet",
        start: minutes(from: ctx.nextSlot, 180),
        end: minutes(from: ctx.nextSlot, 210),
        calendar: ctx.work,
        accountEmail: workAccountEmail,
        attendees: [
          attendee("alex@acme.co", "Alex Kim", "accepted"),
          attendee("sam@acme.co", "Sam Rivera", "needsAction"),
          attendee("room-3@example.com", "Room 3", "accepted", resource: true)
        ],
        conferenceUrl: "https://meet.google.com/jkl-mnop-qrs",
        colorId: "10",
        transparency: "busy"
      ),
      DemoEventSpec(
        id: "copy-polish",
        title: "Focus: Until copy polish",
        description: "Tighten status text, empty states, and website captions.",
        start: minutes(from: ctx.nextSlot, 270),
        end: minutes(from: ctx.nextSlot, 390),
        calendar: ctx.launch,
        accountEmail: workAccountEmail,
        colorId: "4",
        transparency: "free"
      )
    ]
  }

  private static func holdAndPickupSpecs(_ ctx: DemoContext) -> [DemoEventSpec] {
    [
      DemoEventSpec(
        id: "old-declined-hold",
        title: "Declined planning hold",
        description: "Included to exercise filter preview counts.",
        start: minutes(from: ctx.nextSlot, 420),
        end: minutes(from: ctx.nextSlot, 450),
        calendar: ctx.work,
        accountEmail: workAccountEmail,
        selfResponse: "declined",
        colorId: "8",
        transparency: "busy"
      ),
      DemoEventSpec(
        id: "school-pickup",
        title: "School pickup",
        description: "Leave ten minutes early; traffic is usually slow around the station.",
        location: "Maple Elementary",
        start: minutes(from: ctx.nextSlot, 300),
        end: minutes(from: ctx.nextSlot, 330),
        calendar: ctx.family,
        accountEmail: personalAccountEmail,
        attendees: [attendee("partner@example.com", "Avery", "accepted")],
        colorId: "4",
        transparency: "busy"
      ),
      DemoEventSpec(
        id: "website-qa-window",
        title: "Website QA window",
        description: "Check desktop, tablet, and mobile pages before publishing.",
        start: ctx.tomorrow,
        end: ctx.dayAfterTomorrow,
        allDay: true,
        calendar: ctx.launch,
        accountEmail: workAccountEmail,
        colorId: "7",
        transparency: "busy"
      )
    ]
  }

  private static func tomorrowSpecs(_ ctx: DemoContext) -> [DemoEventSpec] {
    [
      DemoEventSpec(
        id: "customer-interview",
        title: "Customer interview: onboarding",
        description: "Observe first-run flow and calendar filtering setup.",
        location: "Zoom",
        start: date(on: ctx.tomorrow, hour: 10, minute: 30),
        end: date(on: ctx.tomorrow, hour: 11, minute: 15),
        calendar: ctx.work,
        accountEmail: workAccountEmail,
        attendees: [
          attendee("nora@acme.example", "Nora Patel", "accepted"),
          attendee("maya@acme.co", "Maya Chen", "accepted")
        ],
        conferenceUrl: "https://acme.zoom.us/j/123456789",
        notesUrl: "https://docs.google.com/document/d/demo-customer-interview/edit",
        colorId: "3",
        transparency: "busy"
      ),
      DemoEventSpec(
        id: "dinner-reservation",
        title: "Dinner reservation",
        description: "Table for four.",
        location: "Little Finch",
        start: date(on: ctx.tomorrow, hour: 19, minute: 0),
        end: date(on: ctx.tomorrow, hour: 20, minute: 30),
        calendar: ctx.family,
        accountEmail: personalAccountEmail,
        attendees: [
          attendee("partner@example.com", "Avery", "accepted"),
          attendee("mom@example.com", "Mom", "accepted")
        ],
        colorId: "6",
        transparency: "busy"
      )
    ]
  }

  private static func event(_ spec: DemoEventSpec, now: Date) -> CalendarEvent? {
    CalendarEvent(
      id: spec.id,
      title: spec.title,
      description: spec.description,
      location: spec.location,
      startISO: ISO8601DateFormatter.fallback.string(from: spec.start),
      endISO: ISO8601DateFormatter.fallback.string(from: spec.end),
      allDay: spec.allDay,
      status: "confirmed",
      startMinutesFromNow: Int((spec.start.timeIntervalSince(now) / 60).rounded()),
      durationMinutes: max(0, Int((spec.end.timeIntervalSince(spec.start) / 60).rounded())),
      calendar: spec.calendar,
      account: AccountRef(email: spec.accountEmail),
      attendees: normalizedAttendees(spec.attendees, accountEmail: spec.accountEmail),
      attendeeCount: spec.attendees.filter { !$0.resource }.count,
      organizer: spec.accountEmail,
      creator: spec.accountEmail,
      selfResponse: spec.selfResponse,
      isRecurring: spec.id == "product-sync",
      hangoutLink: spec.conferenceUrl,
      conferenceUrl: spec.conferenceUrl,
      notesUrl: spec.notesUrl,
      notesFileId: spec.notesUrl.isEmpty ? "" : "demo-\(spec.id)",
      visibility: "default",
      colorId: spec.colorId,
      transparency: spec.transparency,
      htmlLink: "https://calendar.google.com/calendar/event?eid=demo-\(spec.id)"
    )
  }

  private static func normalizedAttendees(_ attendees: [Attendee], accountEmail: String) -> [Attendee] {
    if attendees.contains(where: \.selfUser) { return attendees }
    return [attendee(accountEmail, "You", "accepted", selfUser: true)] + attendees
  }

  private static func attendee(
    _ email: String,
    _ name: String,
    _ responseStatus: String,
    selfUser: Bool = false,
    organizer: Bool = false,
    optional: Bool = false,
    resource: Bool = false
  ) -> Attendee {
    Attendee(
      email: email,
      name: name,
      responseStatus: responseStatus,
      selfUser: selfUser,
      organizer: organizer,
      optional: optional,
      resource: resource
    )
  }

  private static func calendarRef(for definition: CalendarDefinition) -> CalendarRef {
    CalendarRef(
      id: definition.id,
      googleId: definition.googleId,
      name: definition.name,
      primary: definition.primary,
      backgroundColor: definition.backgroundColor
    )
  }

  private static func minutes(from date: Date, _ minutes: Int) -> Date {
    date.addingTimeInterval(TimeInterval(minutes * 60))
  }

  private static func nextHalfHour(after date: Date) -> Date {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    let minute = components.minute ?? 0
    let minutesToAdd = minute < 30 ? 30 - minute : 60 - minute
    let withoutSeconds = calendar.date(from: components) ?? date
    return calendar.date(byAdding: .minute, value: minutesToAdd, to: withoutSeconds) ?? date
  }

  private static func date(on day: Date, hour: Int, minute: Int) -> Date {
    var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
    components.hour = hour
    components.minute = minute
    return Calendar.current.date(from: components) ?? day
  }
}

private struct CalendarDefinition {
  var accountEmail: String
  var googleId: String
  var name: String
  var primary: Bool
  var backgroundColor: String

  var id: String { "\(accountEmail)::\(googleId)" }
}

private struct DemoContext {
  var now: Date
  var nextSlot: Date
  var personal: CalendarRef
  var family: CalendarRef
  var work: CalendarRef
  var launch: CalendarRef
  var today: Date
  var tomorrow: Date
  var dayAfterTomorrow: Date
}

private struct DemoEventSpec {
  var id: String
  var title: String
  var description: String = ""
  var location: String = ""
  var start: Date
  var end: Date
  var allDay: Bool = false
  var calendar: CalendarRef
  var accountEmail: String
  var attendees: [Attendee] = []
  var selfResponse: String = "accepted"
  var conferenceUrl: String = ""
  var notesUrl: String = ""
  var colorId: String
  var transparency: String
}
