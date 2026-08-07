import SwiftUI

struct HeroSlotOccupancy: Equatable {
  var heroEvent: CalendarEvent?
  var nowStripEvent: CalendarEvent?
  var freeDayNextEvent: CalendarEvent?
  var showsFreeDayHero: Bool
}

struct PanelView: View {
  @ObservedObject var model: AppModel
  var openSettings: () -> Void
  @State private var showQuitConfirm = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let now = context.date
      VStack(spacing: 0) {
        content(now: now)
        Divider()
        footer(now: now)
      }
      .frame(width: 390, height: 520)
      // Solid surface matching the List's own background, so the hero, NOW
      // strip, and footer don't show NSPopover's frosted material while the
      // list body is opaque (the popover chrome — corners and arrow — is
      // painted by `StatusBarController.popoverWillShow`).
      .background(Color(nsColor: .textBackgroundColor))
    }
  }

  @ViewBuilder
  private func content(now: Date) -> some View {
    let hasEvents = !(model.state.events.isEmpty && model.state.allDayEvents.isEmpty)
    if !model.state.auth.authenticated {
      OnboardingView(model: model)
    } else if let error = model.state.lastError, !hasEvents {
      // Full-screen error only when there's nothing cached to show.
      EmptyStateView(systemImage: "exclamationmark.triangle", title: loc("Sync Error"), detail: error)
        .frame(maxHeight: .infinity)
    } else if !hasEvents {
      EmptyStateView(
        systemImage: "calendar",
        title: loc("No Events"),
        detail: loc("No upcoming events match the selected calendars, fetch window, and filter.")
      )
      .frame(maxHeight: .infinity)
    } else {
      let occupancy = heroSlotOccupancy(at: now)

      VStack(spacing: 0) {
        // The NOW strip and hero pin the in-progress event, the menubar's
        // countdown event, or the free-day state above the list so their
        // content never requires scrolling. All-day menubar events have no
        // meaningful countdown, so they leave the timed hero slot available
        // for the free-day state. The same occupancy drives this slot and
        // the list below it, so a displaced would-be hero remains listed.
        heroSlot(occupancy: occupancy, now: now)

        // Cached events remain visible; the error rides above them as a compact
        // banner so a transient outage doesn't hide the whole panel.
        if let error = model.state.lastError {
          SyncErrorBanner(message: error)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
        }
        eventList(occupancy: occupancy, now: now)
      }
    }
  }

  private func eventList(occupancy: HeroSlotOccupancy, now: Date) -> some View {
    List {
      ForEach(
        Self.visibleSections(
          model.daySections(now: now),
          occupancy: occupancy,
          now: now,
          coverageEnd: model.state.calendarCoverageEnd
        ),
        id: \.section.id
      ) { section, items in
        Section(dayHeader(section.day, now: now)) {
          ForEach(items) { item in
            switch item {
            case .event(let dayEvent):
              EventRow(
                event: dayEvent.event,
                day: dayEvent.day,
                model: model,
                relativeTimeSuffix: dayEvent.event.actionKey == upcomingRelativeTimeRowKey(
                  occupancy: occupancy,
                  now: now
                )
                  ? loc("in %@", relativeWhen(minutesFromNow(dayEvent.event.startDate, now: now)))
                  : nil
              )
            case .gap(let gap):
              FreeGapRow(until: gap.until)
            case .freeDay:
              FreeDayRow()
            }
          }
        }
      }
    }
    .listStyle(.inset)
  }

  /// Purely computes the two pinned slots and the free-day precedence decision.
  /// Snapshot coverage through the end of the local day is required before
  /// making the free-day claim. The would-be menubar hero may be
  /// intentionally displaced in the popover: a non-imminent event on a later
  /// calendar day yields to the free-day hero, while the menubar keeps counting
  /// down to that event.
  @MainActor
  static func heroSlotOccupancy(
    menubarEvent: CalendarEvent?,
    config: AppConfig,
    timed: [CalendarEvent],
    now: Date,
    coverageEnd: Date?
  ) -> HeroSlotOccupancy {
    let nowStrip = AppModel.pickNowStripEvent(
      menubarEvent: menubarEvent,
      config: config,
      timed: timed,
      now: now
    )
    let freeDayDecision = AppModel.freeDayHeroNextEvent(timed: timed, now: now)
    // A polled `state.next` can outlive its event by a few seconds. It must not
    // keep the stale countdown pinned while the clock has already reached the
    // free-day state.
    let wouldBeHero: CalendarEvent? = menubarEvent.flatMap { event -> CalendarEvent? in
      guard !event.allDay, event.endDate > now else { return nil }
      return event
    }
    let freeDayNextEvent: CalendarEvent?
    if case .free(let nextEvent) = freeDayDecision {
      freeDayNextEvent = nextEvent
    } else {
      freeDayNextEvent = nil
    }

    let calendar = Calendar.current
    let endOfToday = calendar.date(
      byAdding: .day,
      value: 1,
      to: calendar.startOfDay(for: now)
    ) ?? now
    let imminentLead = TimeInterval(max(0, config.notifyLeadMinutes) * 60)
    let nextEventIsImminent = freeDayNextEvent.map {
      $0.startDate.timeIntervalSince(now) <= imminentLead
    } ?? false
    let coverageCoversToday = coverageEnd.map { $0 >= endOfToday } ?? false

    let freeDayWins: Bool
    if nowStrip == nil,
       coverageCoversToday,
       case .free = freeDayDecision,
       !nextEventIsImminent {
      freeDayWins = wouldBeHero.map {
        !calendar.isDate($0.startDate, inSameDayAs: now)
      } ?? true
    } else {
      freeDayWins = false
    }

    return HeroSlotOccupancy(
      heroEvent: freeDayWins ? nil : wouldBeHero,
      nowStripEvent: nowStrip,
      freeDayNextEvent: freeDayWins ? freeDayNextEvent : nil,
      showsFreeDayHero: freeDayWins
    )
  }

  private func heroSlotOccupancy(at now: Date) -> HeroSlotOccupancy {
    Self.heroSlotOccupancy(
      menubarEvent: model.menubarEvent,
      config: model.config,
      timed: model.state.events,
      now: now,
      coverageEnd: model.state.calendarCoverageEnd
    )
  }

  /// Identifies the actual occupants of the hero and NOW strip, so the slot
  /// crossfade is keyed on what is rendered rather than on the menubar's
  /// divergent would-be hero.
  private func heroStripSlots(for occupancy: HeroSlotOccupancy) -> [String?] {
    let heroSlot = occupancy.showsFreeDayHero
      ? "free-day"
      : occupancy.heroEvent?.actionKey
    return [heroSlot, occupancy.nowStripEvent?.actionKey]
  }

  @ViewBuilder
  private func heroSlot(occupancy: HeroSlotOccupancy, now: Date) -> some View {

    VStack(spacing: 0) {
      if let strip = occupancy.nowStripEvent {
        NowStripSection(event: strip, model: model, now: now)
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        Divider()
      }
      if let hero = occupancy.heroEvent {
        HeroSection(event: hero, model: model, now: now)
          .id(hero.actionKey)
          .transition(.opacity)
        Divider()
      } else if occupancy.showsFreeDayHero {
        FreeDayHeroSection(nextEvent: occupancy.freeDayNextEvent, now: now)
          .id("free-day")
          .transition(.opacity)
        Divider()
      }
    }
    .animation(.easeInOut(duration: 0.3), value: heroStripSlots(for: occupancy))
  }

  /// Neither the hero event nor the NOW strip event may also appear in the
  /// list below them; any gap large enough to earn a "free until …" divider
  /// is computed on whatever remains after that filter. A section left with
  /// no rows at all is dropped entirely — its only events are already pinned
  /// above the list, and an empty day header under them would read as a free
  /// day. Future days with no events are synthesized only when their complete
  /// local day is inside the fetched snapshot window. This marker makes the same
  /// implicit fetched-window claim as the existing "free until …" rows, so it
  /// intentionally has no extra coverage or error gate.
  static func visibleSections(
    _ sections: [DaySection],
    occupancy: HeroSlotOccupancy,
    now: Date,
    coverageEnd: Date?
  ) -> [(section: DaySection, items: [PopoverListItem])] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)

    // `groupByDay` currently guarantees one section per day, but keep this
    // helper defensive: if callers ever provide colliding sections, merge
    // their rows instead of silently losing one section's events.
    var sectionsByDay: [Date: DaySection] = [:]
    for section in sections {
      let day = calendar.startOfDay(for: section.day)
      let rows = section.rows.map { DayEvent(day: day, event: $0.event) }
      if var existing = sectionsByDay[day] {
        existing.rows.append(contentsOf: rows)
        existing.rows.sort { lhs, rhs in
          if lhs.event.allDay != rhs.event.allDay {
            return lhs.event.allDay
          }
          if lhs.event.startDate != rhs.event.startDate {
            return lhs.event.startDate < rhs.event.startDate
          }
          return lhs.event.actionKey < rhs.event.actionKey
        }
        sectionsByDay[day] = existing
      } else {
        sectionsByDay[day] = DaySection(day: day, rows: rows)
      }
    }

    func visibleItems(for section: DaySection) -> [PopoverListItem]? {
      let rows = rowsExcludingRenderedSlots(section.rows, occupancy: occupancy)
      guard !rows.isEmpty else { return nil }
      return AppModel.insertingFreeGaps(rows, now: now)
    }

    // Real sections are appended directly, including sections outside the
    // current coverage horizon. A far-future event therefore cannot make the
    // synthesis loop walk all the way to its day.
    var visible: [(section: DaySection, items: [PopoverListItem])] = []
    for day in sectionsByDay.keys.sorted() {
      guard let section = sectionsByDay[day], let items = visibleItems(for: section) else {
        continue
      }
      visible.append((section, items))
    }

    // A day is fully covered only when the next local midnight is at or before
    // the fetched snapshot's actual `timeMax`. Derive the last eligible day
    // directly so a far-future real section cannot extend this bounded walk.
    if let coverageEnd,
       let firstFutureDay = calendar.date(byAdding: .day, value: 1, to: today),
       let lastFullyCoveredDay = calendar.date(
         byAdding: .day,
         value: -1,
         to: calendar.startOfDay(for: coverageEnd)
       ) {
      // Occupancy is checked before hero/NOW-strip deduplication: pinning an
      // overnight event must not make its end day look empty. Timed intervals
      // are [start, end), so an end exactly at local midnight belongs to the
      // prior day. Testing overlap per candidate day (instead of enumerating
      // each event's full duration) keeps the work bounded by the coverage
      // horizon even for pathologically long events.
      func isOccupiedByTimedEvent(_ day: Date) -> Bool {
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: day) else {
          return false
        }
        return sectionsByDay.values.contains { section in
          section.rows.contains { row in
            !row.event.allDay
              && row.event.startDate < nextMidnight
              && row.event.endDate > day
          }
        }
      }

      var day = calendar.startOfDay(for: firstFutureDay)
      while day <= lastFullyCoveredDay {
        if sectionsByDay[day] == nil, !isOccupiedByTimedEvent(day) {
          visible.append((
            DaySection(day: day, rows: []),
            [.freeDay(day)]
          ))
        }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
          break
        }
        day = calendar.startOfDay(for: nextDay)
      }
    }

    return visible.sorted { $0.section.day < $1.section.day }
  }

  static func rowsExcludingRenderedSlots(
    _ rows: [DayEvent],
    occupancy: HeroSlotOccupancy
  ) -> [DayEvent] {
    let pinnedKeys = Set([
      occupancy.heroEvent?.actionKey,
      occupancy.nowStripEvent?.actionKey
    ].compactMap { $0 })
    return rows.filter { !pinnedKeys.contains($0.event.actionKey) }
  }

  /// When the hero event is in progress, the first still-upcoming timed row
  /// in the list (across all sections, in the order they're shown) gets a
  /// "· in 25m" suffix appended to its metadata line.
  private func upcomingRelativeTimeRowKey(
    occupancy: HeroSlotOccupancy,
    now: Date
  ) -> String? {
    guard let hero = occupancy.heroEvent else { return nil }
    guard hero.startDate <= now, hero.endDate > now else { return nil }
    for section in model.daySections(now: now) {
      for row in section.rows where row.event.actionKey != hero.actionKey {
        guard !row.event.allDay, row.event.startDate > now else { continue }
        return row.event.actionKey
      }
    }
    return nil
  }

  private func minutesFromNow(_ date: Date, now: Date) -> Int {
    max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
  }

  private func footer(now: Date) -> some View {
    HStack(spacing: Theme.Spacing.sm) {
      IconButton(systemImage: "power") {
        showQuitConfirm = true
      }
      .help(loc("Quit Until"))
      .confirmationDialog(loc("Quit Until?"), isPresented: $showQuitConfirm) {
        Button(loc("Quit"), role: .destructive) { NSApp.terminate(nil) }
        Button(loc("Cancel"), role: .cancel) {}
      }

      Text(statusText(now: now))
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      Spacer()

      IconButton(systemImage: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise") {
        Task { await model.refresh() }
      }
      .help(loc("Refresh"))

      IconButton(systemImage: "gearshape", action: openSettings)
        .help(loc("Preferences"))
    }
    .padding(.horizontal, Theme.Spacing.md)
    .padding(.vertical, Theme.Spacing.sm)
  }

  private func statusText(now: Date) -> String {
    guard let date = model.state.lastSync else { return loc("Not synced yet") }
    let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
    return minutes == 0 ? loc("Updated just now") : loc("Updated %@ ago", relativeWhen(minutes))
  }
}

/// What Google data the app requests and how it is used. Google's API
/// user-data policy requires this disclosure in-product, immediately before
/// every "Sign in with Google" entry point — not only in the web privacy
/// policy.
struct GoogleDataDisclosureView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
      Text(
        [
          loc("Until asks Google for your calendar list and events, its own Drive files, and your account email."),
          loc("They are used to show and filter events, remind you, open meeting links, and create meeting notes."),
          loc("Events are updated only when you ask to add a Meet link or attach notes."),
          loc("Notes are shared with attendees at your email domain; Until asks before sharing outside it."),
          loc("Your sign-in tokens stay in the macOS Keychain.")
        ].joined(separator: " ")
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      Button {
        NSWorkspace.shared.open(URL(string: "https://until.combinatrix.ai/privacy.html")!)
      } label: {
        Text(loc("Privacy Policy"))
          .font(.caption.weight(.medium))
          .foregroundStyle(Color.accentColor)
          .underline()
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// First-run experience shown in the popover when no Google account is connected.
/// Lets the user sign in directly instead of digging through Preferences.
struct OnboardingView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(spacing: Theme.Spacing.xl) {
      Spacer(minLength: 0)

      VStack(spacing: Theme.Spacing.md) {
        ZStack {
          Circle()
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: 72, height: 72)
          Image(nsImage: BrandIcon.menubarImage(size: 36))
            .renderingMode(.template)
            .foregroundStyle(Color.accentColor)
        }
        VStack(spacing: Theme.Spacing.xs) {
          Text("Until")
            .font(.title2.weight(.semibold))
          Text(loc("Your next Google Calendar event, always in the menubar."))
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
        }
      }

      VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        FeatureRow(
          systemImage: "menubar.arrow.up.rectangle",
          title: loc("Glance at what's next"),
          detail: loc("Your upcoming meeting lives in the menubar.")
        )
        FeatureRow(
          systemImage: "bell.badge",
          title: loc("Never miss a join"),
          detail: loc("Native reminders before your video calls start.")
        )
        FeatureRow(
          systemImage: "doc.text",
          title: loc("One-click meeting notes"),
          detail: loc("Open or create notes straight from an event.")
        )
      }
      .frame(maxWidth: 300)

      VStack(spacing: Theme.Spacing.sm) {
        GoogleDataDisclosureView()
          .card(.inset, padding: Theme.Spacing.md)

        Button {
          model.startLogin()
        } label: {
          HStack(spacing: Theme.Spacing.sm) {
            if model.isSigningIn {
              ProgressView()
                .controlSize(.small)
            } else {
              Image(systemName: "person.crop.circle.badge.plus")
            }
            Text(model.isSigningIn ? loc("Opening Google sign-in…") : loc("Sign in with Google"))
          }
          .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .disabled(model.isSigningIn)

        if model.isSigningIn {
          Button(loc("Cancel")) {
            model.cancelSignIn()
          }
          .buttonStyle(.borderless)
        }
      }
      .frame(maxWidth: 300)

      if let error = model.signInError ?? model.state.lastError {
        InlineErrorView(message: error)
          .frame(maxWidth: 300)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(Theme.Spacing.xl)
  }
}

private struct FeatureRow: View {
  var systemImage: String
  var title: String
  var detail: String

  var body: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.md) {
      Image(systemName: systemImage)
        .font(.body)
        .foregroundStyle(Color.accentColor)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.medium))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
  }
}

/// The "Up next" hero pinned above the popover's event list: the same event
/// the menubar countdown shows (`AppModel.menubarEvent`). Flat layout — no
/// card background or rounded rect — so it reads as part of the popover's
/// top edge rather than a separate surface; `PanelView` draws the hairline
/// `Divider` below it. The containing panel timeline supplies the shared `now`
/// so its relative time and elapsed bar stay in sync with the rest of the panel.
private struct HeroSection: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  var now: Date

  var body: some View {
    HeroContent(event: event, model: model, now: now)
  }
}

/// The non-interactive hero shown when there are no remaining timed events
/// today. The containing hero slot supplies a 30-second timeline so its
/// time-dependent decision is reevaluated while the popover remains open.
private struct FreeDayHeroSection: View {
  var nextEvent: CalendarEvent?
  var now: Date

  var body: some View {
    FreeDayHeroContent(nextEvent: nextEvent, now: now)
  }
}

private struct FreeDayHeroContent: View {
  var nextEvent: CalendarEvent?
  var now: Date

  private var nextWhen: String? {
    guard let nextEvent else { return nil }
    return "\(inlineDay(nextEvent.startDate)) \(clock(nextEvent.startDate))"
  }

  private var nextSummary: String? {
    guard let nextEvent, let nextWhen else { return nil }
    return "\(nextWhen) \(nextEvent.title)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
      HStack(alignment: .firstTextBaseline) {
        Text(loc("No more events today"))
          .font(.caption.weight(.bold))
          .tracking(0.8)
          .textCase(.uppercase)
          .foregroundStyle(Color.green)
        Spacer(minLength: Theme.Spacing.sm)
        if let nextWhen {
          Text(loc("until %@", nextWhen))
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Color.green)
        }
      }

      HStack(spacing: Theme.Spacing.sm) {
        Image(systemName: "sun.max.fill")
          .foregroundStyle(Color.green)
          .accessibilityHidden(true)
        Text(loc("Free"))
      }
      .font(.system(size: 16, weight: .semibold))

      if let nextSummary {
        Text(loc("Next: %@", nextSummary))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, Theme.Spacing.lg)
    .padding(.top, Theme.Spacing.md + 2)
    .padding(.bottom, Theme.Spacing.md + 3)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    var parts = [loc("Free"), loc("No more events today")]
    if let nextSummary {
      parts.append(loc("Next: %@", nextSummary))
    }
    let isJapanese = Locale.current.identifier.hasPrefix("ja")
    return parts.joined(separator: isJapanese ? "。" : ". ") + (isJapanese ? "。" : ".")
  }

  /// Mid-sentence day wording: "Today"/"Tomorrow" read as ordinary words and
  /// lowercase naturally, but formatter output ("Friday, Aug 14") must keep
  /// its casing.
  private func inlineDay(_ date: Date) -> String {
    let header = dayHeader(date, now: now)
    return header == loc("Today") || header == loc("Tomorrow")
      ? header.lowercased()
      : header
  }
}

private struct HeroContent: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  var now: Date

  /// Drives the hover-reveal of the "Create notes" possibility — same ghost
  /// pattern as `EventRow`'s `isHovered`, scoped to the hero's own tappable
  /// area so a neighboring section's hover can't trigger it.
  @State private var isHovered = false

  private var inProgress: Bool {
    event.startDate <= now && event.endDate > now
  }

  private var tintColor: Color {
    inProgress ? .green : .accentColor
  }

  /// Same day key `EventRow` uses for `model.toggleExpanded`/`isExpanded`, so
  /// the hero shares expansion state with the row this event would otherwise
  /// occupy.
  private var day: Date {
    Calendar.current.startOfDay(for: event.startDate)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
      VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
        HStack(alignment: .firstTextBaseline) {
          Text(kickerText)
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(tintColor)
          Spacer(minLength: Theme.Spacing.sm)
          Text(countText)
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tintColor)
        }

        if inProgress {
          HeroProgressBar(fraction: progressFraction)
        }

        Text(event.title)
          .font(.system(size: 16, weight: .semibold))
          .lineLimit(2)

        if !metadataLine.isEmpty {
          Text(metadataLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        HStack(spacing: Theme.Spacing.sm) {
          if !event.conferenceUrl.isEmpty {
            Button {
              model.join(event)
            } label: {
              Label(loc("Join"), systemImage: "video.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(tintColor)
          }
          NoteActionButton(event: event, model: model, showsLabel: true, containerHovered: isHovered)
        }
        .padding(.top, 2)
      }
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.easeInOut(duration: 0.2)) {
          model.toggleExpanded(event, on: day)
        }
      }
      .onHover { isHovered = $0 }

      if model.isExpanded(event, on: day) {
        // Unlike list rows, the hero isn't clipped by a List row, so a sliding
        // detail would overlap the buttons above it mid-animation. Instead the
        // section grows first and the text fades in only once the space is
        // there; on collapse the text vanishes before the section shrinks.
        EventDetailView(event: event, model: model)
          .transition(
            .asymmetric(
              insertion: .opacity.animation(.easeInOut(duration: 0.12).delay(0.15)),
              removal: .opacity.animation(.easeInOut(duration: 0.08))
            )
          )
      }

      if let prompt = model.externalSharePrompt, prompt.id == event.actionKey {
        ExternalShareOverlay(prompt: prompt, model: model)
      }

      if let issue = model.noteError(for: event) {
        NoteErrorOverlay(issue: issue) {
          switch issue.kind {
          case .retry:
            model.createOrOpenNote(for: event)
          case .reauthorize(let email):
            model.startReauthorize(email: email)
          }
        }
      }

      if let error = model.conferenceError(for: event) {
        NoteErrorOverlay(issue: NoteIssue(message: error, kind: .retry)) {
          model.addConference(for: event)
        }
      }
    }
    .padding(.horizontal, Theme.Spacing.lg)
    .padding(.top, Theme.Spacing.md + 2)
    .padding(.bottom, Theme.Spacing.md + 3)
    .contextMenu {
      eventContextMenuItems(event: event, model: model)
    }
  }

  private var kickerText: String {
    inProgress
      ? loc("Now · started %@ ago", relativeWhen(minutesSince(event.startDate)))
      : loc("Up next")
  }

  private var countText: String {
    inProgress
      ? loc("%@ left", relativeWhen(minutesUntil(event.endDate)))
      : loc("in %@", relativeWhen(minutesUntil(event.startDate)))
  }

  private var progressFraction: Double {
    let total = event.endDate.timeIntervalSince(event.startDate)
    guard total > 0 else { return 0 }
    return max(0, min(1, now.timeIntervalSince(event.startDate) / total))
  }

  private var metadataLine: String {
    var parts = [timeRangeText(for: event)]
    if !event.location.isEmpty {
      parts.append(event.location)
    }
    // Calendars often put the provider's own name in the location field, so
    // suppress the provider label when it would just repeat the location
    // ("Google Meet · Google Meet").
    if let provider = EventLinks.meetingProvider(for: event),
       event.location.caseInsensitiveCompare(provider.label) != .orderedSame {
      parts.append(provider.label)
    }
    let attendees = attendeeDisplayNames(for: event)
    if !attendees.isEmpty {
      parts.append(attendees.joined(separator: ", "))
    }
    return parts.joined(separator: " · ")
  }

  private func minutesUntil(_ date: Date) -> Int {
    max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
  }

  private func minutesSince(_ date: Date) -> Int {
    max(0, Int((now.timeIntervalSince(date) / 60).rounded()))
  }
}

/// Thin elapsed/duration fill bar. `fraction` is elapsed/duration, clamped to
/// 0...1. Used inline under the hero's kicker row while its event is in
/// progress (rounded, 3pt) and full-bleed along the NOW strip's bottom edge
/// (square, 2pt) — same math, different geometry per call site.
private struct HeroProgressBar: View {
  var fraction: Double
  var height: CGFloat = 3
  var cornerRadius: CGFloat = 2
  var trackOpacity: Double = 0.18

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(Color.green.opacity(trackOpacity))
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(Color.green)
          .frame(width: proxy.size.width * fraction)
      }
    }
    .frame(height: height)
  }
}

/// The compact one-line strip pinned above the hero for an event that's in
/// progress but isn't the hero (see `AppModel.nowStripEvent`) — e.g. once
/// `menubarPrefersImminentNext` has switched the hero/menubar countdown to
/// the next event while this one is still running. The containing panel
/// timeline supplies the shared `now` for its remaining time and progress.
private struct NowStripSection: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  var now: Date

  var body: some View {
    NowStripContent(event: event, model: model, now: now)
  }
}

private struct NowStripContent: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  var now: Date

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Drives the hover-reveal of the join/notes icons — same ghost pattern as
  /// `EventRow`, tracked here so the reveal only responds to this strip's own
  /// hover, not a neighboring row's.
  @State private var isHovered = false
  @State private var dotDimmed = false

  /// Same day key `EventRow`/`HeroContent` use for `model.toggleExpanded`/
  /// `isExpanded`, so the strip shares expansion state with the row this
  /// event would otherwise occupy.
  private var day: Date {
    Calendar.current.startOfDay(for: event.startDate)
  }

  /// Whether anything renders below the strip band (expanded detail or an
  /// overlay). The band carries its own bottom padding, but content below it
  /// hangs past the progress-bar edge and would otherwise sit flush against
  /// the hairline divider under the section.
  private var showsTrailingContent: Bool {
    model.isExpanded(event, on: day)
      || model.externalSharePrompt?.id == event.actionKey
      || model.noteError(for: event) != nil
      || model.conferenceError(for: event) != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
      // Mixed type sizes on one line look misaligned when centered by frame,
      // so the row shares a text baseline — same rule as the hero's kicker
      // row. The dot has no baseline of its own; pairing it with the kicker
      // keeps it optically centered on the small text instead of sitting on
      // the baseline like a period.
      HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
        HStack(spacing: Theme.Spacing.sm) {
          dot
          Text(loc("Now"))
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Color.green)
        }

        Text(event.title)
          .font(.system(size: 12.5, weight: .medium))
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)

        HStack(spacing: Theme.Spacing.xs) {
          if !event.conferenceUrl.isEmpty {
            JoinVideoCallButton(event: event, model: model)
              .revealOnHover(isHovered)
          }
          NoteActionButton(event: event, model: model, containerHovered: nil)
            .revealOnHover(isHovered)
        }

        Text(loc("%@ left", relativeWhen(minutesUntil(event.endDate))))
          .font(.system(size: 11.5, weight: .semibold))
          .monospacedDigit()
          .foregroundStyle(Color.green)
      }
      .padding(.horizontal, Theme.Spacing.lg)
      .padding(.top, 7)
      .padding(.bottom, 9)
      .background(
        LinearGradient(
          colors: [Color.green.opacity(0.10), Color.green.opacity(0.03)],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .overlay(alignment: .bottom) {
        HeroProgressBar(fraction: progressFraction, height: 2, cornerRadius: 0, trackOpacity: 0.16)
      }
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.easeInOut(duration: 0.2)) {
          model.toggleExpanded(event, on: day)
        }
      }
      .onHover { isHovered = $0 }

      if model.isExpanded(event, on: day) {
        // Same asymmetric grow-then-fade as the hero (see `HeroContent`): the
        // strip isn't clipped by a List row, so the section grows first and
        // the text fades in only once the space is there.
        EventDetailView(event: event, model: model)
          .padding(.horizontal, Theme.Spacing.lg)
          .transition(
            .asymmetric(
              insertion: .opacity.animation(.easeInOut(duration: 0.12).delay(0.15)),
              removal: .opacity.animation(.easeInOut(duration: 0.08))
            )
          )
      }

      if let prompt = model.externalSharePrompt, prompt.id == event.actionKey {
        ExternalShareOverlay(prompt: prompt, model: model)
          .padding(.horizontal, Theme.Spacing.lg)
      }

      if let issue = model.noteError(for: event) {
        NoteErrorOverlay(issue: issue) {
          switch issue.kind {
          case .retry:
            model.createOrOpenNote(for: event)
          case .reauthorize(let email):
            model.startReauthorize(email: email)
          }
        }
        .padding(.horizontal, Theme.Spacing.lg)
      }

      if let error = model.conferenceError(for: event) {
        NoteErrorOverlay(issue: NoteIssue(message: error, kind: .retry)) {
          model.addConference(for: event)
        }
        .padding(.horizontal, Theme.Spacing.lg)
      }
    }
    .padding(.bottom, showsTrailingContent ? Theme.Spacing.md : 0)
    .contextMenu {
      eventContextMenuItems(event: event, model: model)
    }
  }

  /// Pulses 1 → 0.45 → 1 over a 2.4s cycle; static at full opacity when
  /// reduce motion is on.
  private var dot: some View {
    Circle()
      .fill(Color.green)
      .frame(width: 6, height: 6)
      .opacity(reduceMotion ? 1 : (dotDimmed ? 0.45 : 1))
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
          dotDimmed = true
        }
      }
  }

  private var progressFraction: Double {
    let total = event.endDate.timeIntervalSince(event.startDate)
    guard total > 0 else { return 0 }
    return max(0, min(1, now.timeIntervalSince(event.startDate) / total))
  }

  private func minutesUntil(_ date: Date) -> Int {
    max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
  }
}

/// Slim "free until …" divider shown in the popover list between two timed
/// rows separated by a gap of at least `AppModel.freeGapThresholdMinutes`
/// (see `AppModel.insertingFreeGaps`).
private struct FreeGapRow: View {
  var until: Date

  var body: some View {
    HStack(spacing: Theme.Spacing.sm) {
      Rectangle().fill(Theme.hairline).frame(height: 1)
      Text(loc("free until %@", clock(until)))
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize()
      Rectangle().fill(Theme.hairline).frame(height: 1)
    }
    .padding(.vertical, Theme.Spacing.xs)
    .listRowSeparator(.hidden)
  }
}

/// Slim marker for a future day with no events in the fetched window.
private struct FreeDayRow: View {
  var body: some View {
    HStack(spacing: Theme.Spacing.sm) {
      Rectangle().fill(Theme.hairline).frame(height: 1)
      HStack(spacing: Theme.Spacing.xs) {
        Image(systemName: "sun.max.fill")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Text(loc("free all day"))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .fixedSize()
      Rectangle().fill(Theme.hairline).frame(height: 1)
    }
    .padding(.vertical, Theme.Spacing.xs)
    .listRowSeparator(.hidden)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(loc("free all day"))
  }
}

/// Right-click menu content shared by `EventRow` and the "Up next" hero
/// (`HeroContent`) so both present the identical set of actions for an
/// event — join/copy link, open in Calendar, open notes, and skip/unskip in
/// the menubar.
@MainActor
@ViewBuilder
private func eventContextMenuItems(event: CalendarEvent, model: AppModel) -> some View {
  if !event.conferenceUrl.isEmpty {
    Button {
      model.join(event)
    } label: {
      Label(loc("Join video call"), systemImage: "video")
    }
    Button {
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(event.conferenceUrl, forType: .string)
    } label: {
      Label(loc("Copy meeting link"), systemImage: "link")
    }
  }
  Button {
    model.open(event)
  } label: {
    Label(loc("Open in Google Calendar"), systemImage: "calendar")
  }
  if !model.noteURL(for: event).isEmpty {
    Button {
      model.createOrOpenNote(for: event)
    } label: {
      Label(loc("Open meeting notes"), systemImage: "doc.text")
    }
  }
  Divider()
  if model.isSkippedInMenubar(event) {
    Button {
      model.unskipInMenubar(event)
    } label: {
      Label(loc("Show in menubar"), systemImage: "arrow.uturn.backward")
    }
  } else {
    Button {
      model.skipInMenubar(event)
    } label: {
      Label(loc("Skip in menubar"), systemImage: "forward.end")
    }
  }
}

struct EventRow: View {
  private static let colorBarWidth: CGFloat = 3
  private static let timeColumnWidth: CGFloat = clockColumnWidth()
  private static let detailIndent = colorBarWidth + Theme.Spacing.sm + timeColumnWidth + Theme.Spacing.sm

  var event: CalendarEvent
  var day: Date
  @ObservedObject var model: AppModel
  /// "· in 25m" appended to the metadata line — set by `PanelView` on the
  /// first upcoming timed row while the hero event is in progress.
  var relativeTimeSuffix: String?
  /// Drives the hover-reveal of "add"-type row actions (see `isHovered`
  /// below); tracked here rather than derived so the reveal only responds to
  /// this row's own hover, not a neighbor's.
  @State private var isHovered = false

  init(event: CalendarEvent, day: Date, model: AppModel, relativeTimeSuffix: String? = nil) {
    self.event = event
    self.day = day
    self.model = model
    self.relativeTimeSuffix = relativeTimeSuffix
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
      HStack(spacing: Theme.Spacing.sm) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(eventColor)
          .frame(width: Self.colorBarWidth)
          .accessibilityHidden(true)

        Text(event.allDay ? loc("all-day") : clock(event.startDate))
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .frame(width: Self.timeColumnWidth, alignment: .leading)

        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: Theme.Spacing.xs) {
            Text(event.title)
              .font(.body)
              .lineLimit(2)
            if isSkipped {
              SkippedBadge()
            }
          }
          if !metadata.isEmpty || relativeTimeSuffix != nil {
            // The relative time is its own fixed-size Text so a long
            // location/attendee list truncates instead of eating "in 25m".
            HStack(spacing: 0) {
              if !metadata.isEmpty {
                Text(metadata)
                  .lineLimit(1)
              }
              if let suffix = relativeTimeSuffix {
                Text(metadata.isEmpty ? suffix : " · " + suffix)
                  .lineLimit(1)
                  .fixedSize(horizontal: true, vertical: false)
                  .layoutPriority(1)
              }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }

        Spacer(minLength: Theme.Spacing.sm)

        HStack(spacing: Theme.Spacing.xs) {
          if isSkipped {
            IconButton(systemImage: "arrow.uturn.backward") {
              model.unskipInMenubar(event)
            }
            .help(loc("Show in menubar"))
          }

          // State (a link/note that already exists) renders as a persistent
          // IconButton; possibility (no link/note yet — an "add"-type action)
          // only fades in on row hover via `revealOnHover`, so accent color
          // is never a resting state, only a hover one. All-day rows never
          // get a "add video call" action, hover or not.
          if !event.conferenceUrl.isEmpty {
            JoinVideoCallButton(event: event, model: model)
          } else if !event.allDay {
            ConferenceActionButton(event: event, model: model)
              .revealOnHover(isHovered)
          }

          NoteActionButton(event: event, model: model, containerHovered: isHovered)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.easeInOut(duration: 0.2)) {
          model.toggleExpanded(event, on: day)
        }
      }
      .onHover { isHovered = $0 }
      // Dim just the header row (time/title/actions) to signal "hidden from
      // the menubar" without also fading expanded detail or error overlays,
      // which stay fully legible.
      .opacity(isSkipped ? 0.55 : 1)

      if model.isExpanded(event, on: day) {
        EventDetailView(event: event, model: model)
          .padding(.leading, Self.detailIndent)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }

      if let prompt = model.externalSharePrompt, prompt.id == event.actionKey {
        ExternalShareOverlay(prompt: prompt, model: model)
          .padding(.leading, Self.detailIndent)
      }

      if let issue = model.noteError(for: event) {
        NoteErrorOverlay(issue: issue) {
          switch issue.kind {
          case .retry:
            model.createOrOpenNote(for: event)
          case .reauthorize(let email):
            model.startReauthorize(email: email)
          }
        }
        .padding(.leading, Self.detailIndent)
      }

      if let error = model.conferenceError(for: event) {
        NoteErrorOverlay(issue: NoteIssue(message: error, kind: .retry)) {
          model.addConference(for: event)
        }
        .padding(.leading, Self.detailIndent)
      }
    }
    .padding(.vertical, Theme.Spacing.xs)
    .contextMenu {
      eventContextMenuItems(event: event, model: model)
    }
  }

  /// Whether this event is currently hidden from the menubar countdown (see
  /// `AppModel.skipInMenubar`). Only affects this row's presentation — the
  /// popover list itself always shows the event.
  private var isSkipped: Bool {
    model.isSkippedInMenubar(event)
  }

  private var eventColor: Color {
    Color(hex: googleEventColor(event.colorId) ?? event.calendar.backgroundColor) ?? .accentColor
  }

  private var metadata: String {
    let attendees = attendeeDisplayNames(for: event)
    let parts: [String?] = [
      event.location.isEmpty ? nil : event.location,
      attendees.isEmpty ? nil : attendees.joined(separator: ", ")
    ]
    return parts.compactMap { $0 }.joined(separator: " · ")
  }
}

/// Attendee display names for an event's metadata line: excludes the current
/// user and resource attendees (rooms, etc.), preferring each attendee's name
/// over their bare email. Shared by `EventRow` and the "Up next" hero so both
/// draw from the same source of names.
private func attendeeDisplayNames(for event: CalendarEvent) -> [String] {
  event.attendees
    .filter { !$0.selfUser && !$0.resource }
    .map { $0.name.isEmpty ? $0.email : $0.name }
}

/// "start – end" clock times for a timed event. Shared by the hero's metadata
/// line and expanded event detail so the dash and spacing can't drift apart.
private func timeRangeText(for event: CalendarEvent) -> String {
  "\(clock(event.startDate)) – \(clock(event.endDate))"
}

/// Small inline caption chip marking an event as hidden from the menubar
/// countdown. Mirrors the subtle, no-border pill look used elsewhere for
/// inline captions (e.g. `NoteErrorOverlay`'s tinted background) but at
/// caption scale so it sits comfortably next to the event title.
private struct SkippedBadge: View {
  var body: some View {
    Text(loc("Skipped"))
      .font(.caption2.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, Theme.Spacing.xs)
      .padding(.vertical, 1)
      .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
  }
}

private struct NoteActionButton: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  /// Renders as a labeled `QuietButton` instead of the list row's icon-only
  /// `IconButton` — used by the "Up next" hero's secondary action. Same
  /// open-or-create behavior either way; only the presentation differs.
  var showsLabel: Bool = false
  /// The containing surface's hover state. The possibility/state rule lives
  /// here rather than at call sites so every surface agrees on it: an
  /// existing or in-flight note is state (always visible), a missing note is
  /// a possibility (visible only while the container is hovered). `nil` opts
  /// out for containers that manage visibility themselves — the NOW strip
  /// reveals all of its actions on hover, note or not.
  var containerHovered: Bool?
  @State private var showConfirm = false

  var body: some View {
    let notesUrl = model.noteURL(for: event)
    let isCreating = model.isCreatingNote(for: event)
    let revealed = containerHovered.map { !notesUrl.isEmpty || isCreating || $0 } ?? true

    let action = {
      if notesUrl.isEmpty {
        showConfirm = true
      } else {
        model.createOrOpenNote(for: event)
      }
    }

    Group {
      if showsLabel {
        QuietButton(
          systemImage: notesUrl.isEmpty ? "doc.badge.plus" : "doc.text",
          label: notesUrl.isEmpty ? loc("Create notes") : loc("Open notes"),
          isBusy: isCreating,
          action: action
        )
      } else {
        IconButton(
          systemImage: notesUrl.isEmpty ? "doc.badge.plus" : "doc.text",
          isBusy: isCreating,
          action: action
        )
      }
    }
    .disabled(isCreating)
    .help(notesUrl.isEmpty ? loc("Create meeting notes") : loc("Open meeting notes"))
    .confirmationDialog(loc("Create meeting notes?"), isPresented: $showConfirm) {
      Button(loc("Create notes")) { model.createOrOpenNote(for: event) }
      Button(loc("Cancel"), role: .cancel) {}
    } message: {
      Text(confirmMessage)
    }
    .revealOnHover(revealed)
  }

  /// Names the same-domain attendees who will receive edit access, so the
  /// automatic grant is visible before the user confirms. External attendees
  /// are asked about separately (ExternalShareOverlay) and not repeated here.
  private var confirmMessage: String {
    let sameDomain = model.sameDomainAttendees(for: event)
    guard !sameDomain.isEmpty else {
      return loc("Create a Google Doc for %@ and attach it to the calendar event.", event.title)
    }
    let shown = sameDomain.prefix(3).joined(separator: ", ")
    let overflow = sameDomain.count > 3 ? loc(" and %d more", sameDomain.count - 3) : ""
    return loc(
      "Create a Google Doc for %1$@, attach it to the calendar event, and give edit access to %2$@%3$@.",
      event.title, shown, overflow
    )
  }
}

/// The row/strip "join the video call" action: one home for the icon, action,
/// and help text, mirroring how `ConferenceActionButton` and
/// `NoteActionButton` wrap theirs. Joining reads nothing observable from the
/// model, so this holds a plain reference rather than an `@ObservedObject`.
private struct JoinVideoCallButton: View {
  var event: CalendarEvent
  var model: AppModel

  var body: some View {
    IconButton(systemImage: "video.fill") {
      model.join(event)
    }
    .help(loc("Join video call"))
  }
}

private struct ConferenceActionButton: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  @State private var showConfirm = false

  var body: some View {
    let isAdding = model.isAddingConference(for: event)

    IconButton(systemImage: "video.badge.plus", isBusy: isAdding) {
      showConfirm = true
    }
    .disabled(isAdding)
    .help(loc("Add Google Meet"))
    .confirmationDialog(loc("Add Google Meet?"), isPresented: $showConfirm) {
      Button(loc("Add Meet")) { model.addConference(for: event) }
      Button(loc("Cancel"), role: .cancel) {}
    } message: {
      Text(loc("Add a Google Meet video link to %@.", event.title))
    }
  }
}

private struct EventDetailView: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  @State private var copiedRecently = false

  private static let copyDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  private static let copyDateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
      // Always present, unlike the description/attendee blocks below, so an
      // event with neither (e.g. a bare "移動" placeholder) still expands to
      // a line of text instead of landing straight on a row of icon buttons.
      Text(detailMetadataLine)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      if !event.description.isEmpty {
        Text(htmlAttributedString(event.description))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(10)
          .fixedSize(horizontal: false, vertical: true)
      }

      let others = event.attendees.filter { !$0.selfUser && !$0.resource }
      if !others.isEmpty {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(others, id: \.email) { attendee in
            HStack(spacing: 4) {
              Image(systemName: responseIcon(attendee.responseStatus))
                .font(.system(size: 9))
                .foregroundStyle(responseColor(attendee.responseStatus))
                .accessibilityLabel(responseLabel(attendee.responseStatus))
              Text(attendee.name.isEmpty ? attendee.email : attendee.name)
                .font(.caption)
                .foregroundStyle(.primary)
            }
          }
        }
      }

      HStack(spacing: Theme.Spacing.sm) {
        QuietButton(
          systemImage: copiedRecently ? "checkmark" : "doc.on.doc",
          label: loc("Copy details"),
          size: .small,
          tint: copiedRecently ? Color.green : nil,
          action: copyEventDetails
        )
        .help(copiedRecently ? loc("Copied event details") : loc("Copy event details"))
        .accessibilityLabel(loc("Copy event details"))

        QuietButton(systemImage: "arrow.up.right", label: loc("Open in Calendar"), size: .small) {
          model.open(event)
        }
        .help(loc("Open in Calendar"))
        .accessibilityLabel(loc("Open in Calendar"))
      }
    }
    .padding(.vertical, Theme.Spacing.xs)
  }

  /// "<start – end> · <account email>" (all-day: `loc("all-day")` in place of
  /// the range).
  private var detailMetadataLine: String {
    let timePart = event.allDay ? loc("all-day") : timeRangeText(for: event)
    return "\(timePart) · \(event.account.email)"
  }

  private func copyEventDetails() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(copyText, forType: .string)

    withAnimation(.easeInOut(duration: 0.12)) {
      copiedRecently = true
    }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      copiedRecently = false
    }
  }

  private var copyText: String {
    var lines = [
      event.title,
      copyTimeText
    ]

    if !event.location.isEmpty {
      lines.append(loc("Location: %@", event.location))
    }

    let conferenceURL = EventLinks.conferenceURLString(for: event)
    if !conferenceURL.isEmpty {
      lines.append(loc("Meet: %@", conferenceURL))
    }

    let calendarURL = EventLinks.eventURLString(for: event)
    if !calendarURL.isEmpty {
      lines.append(loc("Calendar: %@", calendarURL))
    }

    return lines.joined(separator: "\n")
  }

  private var copyTimeText: String {
    let calendar = Calendar.current

    if event.allDay {
      let displayEnd = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate
      let start = Self.copyDateFormatter.string(from: event.startDate)
      if calendar.isDate(event.startDate, inSameDayAs: displayEnd) {
        return "\(start) \(loc("all-day"))"
      }
      let end = Self.copyDateFormatter.string(from: displayEnd)
      return "\(start) - \(end) \(loc("all-day"))"
    }

    if calendar.isDate(event.startDate, inSameDayAs: event.endDate) {
      let day = Self.copyDateFormatter.string(from: event.startDate)
      return "\(day), \(clock(event.startDate)) - \(clock(event.endDate))"
    }
    let start = Self.copyDateTimeFormatter.string(from: event.startDate)
    let end = Self.copyDateTimeFormatter.string(from: event.endDate)
    return "\(start) - \(end)"
  }

  private func responseIcon(_ status: String) -> String {
    switch status {
    case "accepted": return "checkmark.circle.fill"
    case "declined": return "xmark.circle.fill"
    case "tentative": return "questionmark.circle.fill"
    default: return "circle"
    }
  }

  private func responseColor(_ status: String) -> Color {
    switch status {
    case "accepted": return .green
    case "declined": return .red
    case "tentative": return .orange
    default: return .secondary
    }
  }

  private func responseLabel(_ status: String) -> String {
    switch status {
    case "accepted": return loc("Accepted")
    case "declined": return loc("Declined")
    case "tentative": return loc("Tentative")
    default: return loc("No response")
    }
  }

  private func htmlAttributedString(_ html: String) -> AttributedString {
    let styled = "<span style=\"font-family: -apple-system; font-size: 11px;\">\(html)</span>"
    guard let data = styled.data(using: .utf8),
          let nsAttr = try? NSAttributedString(
            data: data,
            options: [
              .documentType: NSAttributedString.DocumentType.html,
              .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
          ),
          var attr = try? AttributedString(nsAttr, including: \.appKit)
    else {
      return AttributedString(html)
    }
    for run in attr.runs where run.link != nil {
      attr[run.range].foregroundColor = NSColor.controlAccentColor
    }
    return attr
  }
}

private struct ExternalShareOverlay: View {
  var prompt: ExternalSharePrompt
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
      HStack(alignment: .top, spacing: Theme.Spacing.sm) {
        Image(systemName: "person.2.badge.gearshape")
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text(loc("External attendees"))
            .font(.caption.weight(.semibold))
          Text(prompt.externalAttendees.prefix(3).joined(separator: ", ") + overflowText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      HStack(spacing: Theme.Spacing.sm) {
        Button(loc("Internal only")) {
          model.resolveExternalShare(shareExternalAttendees: false)
        }
        Button(loc("Share externally")) {
          model.resolveExternalShare(shareExternalAttendees: true)
        }
        .buttonStyle(.borderedProminent)
        IconButton(systemImage: "xmark") {
          model.cancelExternalSharePrompt()
        }
        .help(loc("Cancel"))
      }
      .font(.caption)
    }
    .padding(Theme.Spacing.sm)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.Radius.sm)
        .strokeBorder(Color.orange.opacity(0.3))
    )
  }

  private var overflowText: String {
    prompt.externalAttendees.count > 3 ? loc(" and %d more", prompt.externalAttendees.count - 3) : ""
  }
}

/// Compact inline banner shown above the cached event list when a sync fails but
/// events are still available. Mirrors `NoteErrorOverlay`'s visual language.
private struct SyncErrorBanner: View {
  var message: String

  var body: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(message)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(Theme.Spacing.sm)
    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.Radius.sm)
        .strokeBorder(Color.orange.opacity(0.22))
    )
  }
}

private struct NoteErrorOverlay: View {
  var issue: NoteIssue
  /// Invoked when the action button is tapped; the label depends on `issue.kind`.
  var action: () -> Void

  private var buttonLabel: String {
    switch issue.kind {
    case .retry: return loc("Retry")
    case .reauthorize: return loc("Reauthorize")
    }
  }

  var body: some View {
    HStack(spacing: Theme.Spacing.sm) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.red)
      Text(issue.message)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Spacer()
      Button(buttonLabel, action: action)
        .font(.caption)
    }
    .padding(Theme.Spacing.sm)
    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.Radius.sm)
        .strokeBorder(Color.red.opacity(0.18))
    )
  }
}

struct SettingsView: View {
  private static let fetchWindowPresets = [
    (key: "12", label: "12h", hours: 12),
    (key: "24", label: "24h", hours: 24),
    (key: "48", label: "48h", hours: 48),
    (key: "168", label: "1w", hours: 168),
    (key: "336", label: "2w", hours: 336)
  ]

  private static let menubarWindowPresets = [
    (key: "60", label: loc("Within 1 hour"), minutes: 60),
    (key: "180", label: loc("Within 3 hours"), minutes: 180),
    (key: "360", label: loc("Within 6 hours"), minutes: 360),
    (key: "720", label: loc("Within 12 hours"), minutes: 720),
    (key: "1440", label: loc("Within 24 hours"), minutes: 1440)
  ]

  /// The settings sections, shown as a sidebar instead of OS-standard tabs.
  private enum Section: String, CaseIterable, Identifiable {
    case accounts, general, filter
    var id: String { rawValue }

    var label: String {
      switch self {
      case .accounts: return loc("Accounts")
      case .general: return loc("General")
      case .filter: return loc("Filter")
      }
    }

    var systemImage: String {
      switch self {
      case .accounts: return "person.crop.circle"
      case .general: return "gearshape"
      case .filter: return "line.3.horizontal.decrease.circle"
      }
    }
  }

  /// "Version 1.0.2" from the bundle's marketing version, or "Version dev" for
  /// the plain `swift run` executable (no Info.plist). The internal build number
  /// (CFBundleVersion) is deliberately omitted — it's just the CI run counter
  /// and means nothing to users.
  private static let appVersionLabel: String = {
    let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    return loc("Version %@", short)
  }()

  @ObservedObject var model: AppModel
  @State private var draft: AppConfig
  @State private var usesCustomFetchWindow: Bool
  @State private var saveTask: Task<Void, Never>?
  @State private var selection: Section? = .accounts

  init(model: AppModel) {
    self.model = model
    _draft = State(initialValue: model.config)
    _usesCustomFetchWindow = State(initialValue: !Self.isPresetFetchWindow(model.config.lookaheadHours))
    _selection = State(
      initialValue: RuleValidator.isValid(model.config.filterRules) ? .accounts : .filter
    )
  }

  var body: some View {
    NavigationSplitView {
      List(Section.allCases, selection: $selection) { section in
        Label(section.label, systemImage: section.systemImage)
          .tag(section)
      }
      .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
      .safeAreaInset(edge: .bottom) {
        Text(Self.appVersionLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
      }
    } detail: {
      switch selection ?? .accounts {
      case .accounts: accountTab
      case .general: generalTab
      case .filter: filtersTab
      }
    }
    .onReceive(model.$config) {
      draft = $0
      if !Self.isPresetFetchWindow($0.lookaheadHours) {
        usesCustomFetchWindow = true
      }
    }
    .onChange(of: draft) { scheduleSave($0) }
  }

  // MARK: Auto-save

  /// All tabs save automatically. Edits are debounced so steppers and text
  /// fields don't trigger a network refresh on every keystroke.
  private func scheduleSave(_ config: AppConfig) {
    guard config != model.config else { return }
    guard RuleValidator.validate(config.filterRules) == nil else { return }
    saveTask?.cancel()
    saveTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 500_000_000)
      guard !Task.isCancelled, config != model.config else { return }
      model.saveConfig(config)
    }
  }

  // MARK: Tabs

  private var accountTab: some View {
    SettingsTab {
      ConnectedAccountsPanel(model: model, draft: $draft)
    }
    .task {
      if model.calendars.isEmpty {
        await model.refreshCalendars()
      }
    }
  }

  private var generalTab: some View {
    SettingsTab {
      SettingsCard(loc("App")) {
        SettingRow(
          loc("Launch at login"),
          subtitle: model.launchAtLoginAvailable
            ? loc("Start Until automatically when you log in")
            : loc("Available when running as an app bundle")
        ) {
          Toggle("", isOn: Binding(
            get: { model.launchAtLoginEnabled },
            set: { model.setLaunchAtLogin($0) }
          ))
          .labelsHidden()
          .disabled(!model.launchAtLoginAvailable)
        }
        if let error = model.launchAtLoginError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }
        Divider()
        SettingRow(loc("Global shortcut"), subtitle: loc("Toggle the Until popover from anywhere")) {
          HStack(spacing: Theme.Spacing.sm) {
            Picker("", selection: $draft.hotkeyPreset) {
              ForEach(HotkeyManager.presets) { preset in
                Text(preset.label).tag(preset.id)
              }
            }
            .labelsHidden()
            .frame(width: 130)
            .disabled(!draft.hotkeyEnabled)
            Toggle("", isOn: $draft.hotkeyEnabled)
              .labelsHidden()
          }
        }
        Divider()
        SettingRow(
          loc("Software updates"),
          subtitle: loc("Until updates automatically; check now to update sooner")
        ) {
          Button(loc("Check for Updates...")) { model.updater.checkForUpdates() }
            .disabled(!model.updater.canCheckForUpdates)
        }
      }
      .task {
        model.refreshLaunchAtLoginState()
      }

      SettingsCard(loc("Sync")) {
        stepperRow(
          loc("Refresh interval"),
          subtitle: loc("How often to check Google Calendar for changes"),
          value: $draft.pollIntervalSeconds, range: 30...3600, step: 30, unit: loc("sec")
        )
        Divider()
        SettingRow(loc("Fetch window"), subtitle: loc("How far ahead to load events")) {
          HStack(spacing: Theme.Spacing.md) {
            Picker("", selection: fetchWindowSelection) {
              ForEach(Self.fetchWindowPresets, id: \.key) { preset in
                Text(preset.label).tag(preset.key)
              }
              Text(loc("Custom")).tag("custom")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 300)

            if usesCustomFetchWindow {
              Stepper(value: $draft.lookaheadHours, in: 1...336, step: 1) {
                Text("\(draft.lookaheadHours)h")
                  .monospacedDigit()
                  .frame(minWidth: 36, alignment: .trailing)
              }
            }
          }
        }
      }

      SettingsCard(loc("Menubar")) {
        stepperRow(
          loc("Max title length"),
          subtitle: loc("Longer event titles are shortened with “…”"),
          value: $draft.maxTitleLength, range: 10...120, step: 1, unit: loc("characters")
        )
        Divider()
        SettingRow(loc("Show upcoming event"), subtitle: loc("When the next event appears in the menubar")) {
          Picker("", selection: menubarWindowSelection) {
            ForEach(Self.menubarWindowPresets, id: \.key) { preset in
              Text(preset.label).tag(preset.key)
            }
            Text(loc("Same as fetch window")).tag("always")
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .frame(width: 210)
        }
        Divider()
        SettingRow(
          loc("Switch to next event early"),
          subtitle: loc("Show the next event instead of the current one once its reminder time is reached")
        ) {
          Toggle("", isOn: $draft.menubarPrefersImminentNext)
            .labelsHidden()
        }
        Divider()
        Text(loc("Right-click the icon to hide the event text; ⌥-click to join the meeting shown in the menubar."))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      SettingsCard(loc("Notifications")) {
        SettingRow(loc("Event reminders"), subtitle: loc("Send a notification before an event starts")) {
          Toggle("", isOn: $draft.notifyEnabled)
            .labelsHidden()
        }
        Divider()
        SettingRow(loc("Remind me about")) {
          Picker("", selection: $draft.notifyVideoOnly) {
            Text(loc("All events")).tag(false)
            Text(loc("Video only")).tag(true)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 210)
        }
        .disabled(!draft.notifyEnabled)
        Divider()
        stepperRow(
          loc("Reminder timing"),
          subtitle: loc("How long before an event the reminder fires"),
          value: $draft.notifyLeadMinutes, range: 0...120, step: 1, unit: loc("min before")
        )
        .disabled(!draft.notifyEnabled)

        Divider()

        SettingRow(loc("Notification access"), subtitle: loc("Granted in macOS System Settings")) {
          HStack(spacing: Theme.Spacing.sm) {
            Circle()
              .fill(notificationAuthorizationColor(model.notificationAuthorizationState))
              .frame(width: 8, height: 8)
              .accessibilityLabel(model.notificationAuthorizationState.label)
            Text(model.notificationAuthorizationState.label)
            Button {
              Task { await model.refreshNotificationAuthorizationState() }
            } label: {
              Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(loc("Re-check permission"))
          }
        }
        Divider()
        SettingRow(loc("System Settings"), subtitle: loc("Manage how reminders are delivered")) {
          Button(loc("Open")) { model.openNotificationSettings() }
        }
        Divider()
        HStack {
          Button {
            Task { await model.sendTestNotification() }
          } label: {
            if model.isSendingTestNotification {
              HStack(spacing: Theme.Spacing.xs) {
                ProgressView()
                  .controlSize(.small)
                Text(loc("Sending test reminder"))
              }
            } else {
              Label(loc("Send test reminder"), systemImage: "bell.badge")
            }
          }
          .disabled(model.isSendingTestNotification)
          Spacer()
        }
        if let error = model.testNotificationError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }
      }
    }
    .task {
      await model.refreshNotificationAuthorizationState()
    }
  }

  private var filtersTab: some View {
    let preview = model.filterPreview(for: draft.filterRules)
    return SettingsTab(maxColumnWidth: .infinity) {
      SettingsCard(loc("Filter"), subtitle: loc("Only matching events appear in the menubar and list"), accessory: {
        Button(loc("Reset to defaults")) {
          draft.filterRules = AppConfig.default.filterRules
        }
      }, content: {
        // The builder lays out at its natural width and lets the settings
        // window grow to fit a deep filter. An earlier version wrapped this in
        // a horizontal ScrollView with a GeometryReader width-feedback loop;
        // profiling showed that combination drove the tab's layout pass to
        // several seconds, so it was removed.
        QueryBuilderView(rule: $draft.filterRules, calendars: model.calendars)
          .padding(.bottom, 4)
        if let validationError = RuleValidator.validate(draft.filterRules) {
          Text(validationError.message)
            .font(.caption)
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
        FilterPreviewView(result: preview)
      })
    }
    .task {
      // Calendars rarely change, and the rule editor's calendar pickers only
      // need them once. Refetching on every tab open made the Filter tab feel
      // slow (a Google API round-trip, plus a possible token refresh, each
      // time). Fetch only when we don't already have them; the Refresh button
      // and the background poll keep them current otherwise.
      if model.calendars.isEmpty {
        await model.refreshCalendars()
      }
    }
  }

  // MARK: Helpers

  private func stepperRow(
    _ title: String,
    subtitle: String? = nil,
    value: Binding<Int>,
    range: ClosedRange<Int>,
    step: Int,
    unit: String
  ) -> some View {
    SettingRow(title, subtitle: subtitle) {
      HStack(spacing: Theme.Spacing.sm) {
        Text("\(value.wrappedValue) \(unit)")
          .monospacedDigit()
          .foregroundStyle(.secondary)
        Stepper("", value: value, in: range, step: step)
          .labelsHidden()
      }
    }
  }

  private var fetchWindowSelection: Binding<String> {
    Binding(
      get: {
        if !usesCustomFetchWindow,
           let preset = Self.fetchWindowPresets.first(where: { $0.hours == draft.lookaheadHours }) {
          return preset.key
        }
        return "custom"
      },
      set: { key in
        guard key != "custom" else {
          usesCustomFetchWindow = true
          return
        }
        guard let preset = Self.fetchWindowPresets.first(where: { $0.key == key }) else { return }
        usesCustomFetchWindow = false
        draft.lookaheadHours = preset.hours
      }
    )
  }

  private static func isPresetFetchWindow(_ hours: Int) -> Bool {
    fetchWindowPresets.contains { $0.hours == hours }
  }

  private var menubarWindowSelection: Binding<String> {
    Binding(
      get: {
        guard !draft.menubarShowsNextAlways else { return "always" }
        // Snap to the nearest preset (same rule as AppConfig.snappedMenubarLead)
        // so legacy/arbitrary minute values still resolve to a sensible menu
        // selection.
        let snapped = AppConfig.snappedMenubarLead(draft.menubarLeadMinutes)
        return Self.menubarWindowPresets.first { $0.minutes == snapped }?.key
          ?? Self.menubarWindowPresets.last!.key
      },
      set: { key in
        guard key != "always" else {
          draft.menubarShowsNextAlways = true
          return
        }
        guard let preset = Self.menubarWindowPresets.first(where: { $0.key == key }) else { return }
        draft.menubarShowsNextAlways = false
        draft.menubarLeadMinutes = preset.minutes
      }
    )
  }
}

/// Shared scrollable container for every settings tab: consistent width,
/// padding, and inter-card spacing.
private struct SettingsTab<Content: View>: View {
  /// Most tabs cap their column at 720 for readable line lengths. The filter
  /// tab passes `.infinity` so the query builder can use the full window width
  /// and grow as the window widens.
  var maxColumnWidth: CGFloat = 720
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView {
      // Flat sections have no card chrome, so separation comes from this
      // generous inter-section spacing plus each section's bold header.
      VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
        content()
      }
      // Cap the column and center it so every section lines up and the query
      // builder has room to breathe.
      .frame(maxWidth: maxColumnWidth)
      .frame(maxWidth: .infinity)
      .padding(Theme.Spacing.xl)
    }
  }
}

private struct ConnectedAccountsPanel: View {
  @ObservedObject var model: AppModel
  @Binding var draft: AppConfig

  var body: some View {
    SettingsCard(loc("Google Accounts"), accessory: {
      if !model.state.auth.accounts.isEmpty {
        HStack(spacing: Theme.Spacing.sm) {
          Button {
            Task { await model.refreshCalendars() }
          } label: {
            Label(loc("Refresh"), systemImage: "arrow.clockwise")
          }
          addAccountButton
            .buttonStyle(.borderedProminent)
        }
      }
    }, content: {
      if model.state.auth.accounts.isEmpty {
        EmptyStateView(
          systemImage: "person.crop.circle.badge.plus",
          title: loc("No accounts connected"),
          detail: loc("Connect a Google account to see your calendar.")
        ) {
          addAccountButton
            .buttonStyle(.borderedProminent)
        }
        .card(.inset)
      } else {
        VStack(spacing: Theme.Spacing.sm) {
          ForEach(model.state.auth.accounts) { account in
            AccountConfigurationCard(
              account: account,
              calendars: model.calendars.filter { $0.accountEmail == account.email },
              selectedFolder: model.meetingNotesFolder(for: account.email),
              model: model,
              draft: $draft
            )
          }
        }
      }

      GoogleDataDisclosureView()

      if model.isSigningIn {
        HStack(spacing: Theme.Spacing.sm) {
          ProgressView()
            .controlSize(.small)
          Text(loc("Opening Google sign-in..."))
            .foregroundStyle(.secondary)
          Button(loc("Cancel")) {
            model.cancelSignIn()
          }
          .buttonStyle(.borderless)
        }
        .font(.callout)
      }

      if let error = model.signInError ?? model.state.lastError {
        InlineErrorView(message: error)
      }
    })
  }

  private var addAccountButton: some View {
    Button {
      model.saveConfig(draft)
      model.startLogin()
    } label: {
      Label(loc("Add Account"), systemImage: "plus")
    }
    .disabled(model.isSigningIn)
  }
}

private struct AccountConfigurationCard: View {
  var account: AccountState
  var calendars: [CalendarSummary]
  var selectedFolder: DriveFolderRef?
  @ObservedObject var model: AppModel
  @Binding var draft: AppConfig

  /// Meeting Notes is collapsed by default — most accounts run on the defaults.
  /// It auto-expands on first appearance for accounts that have customized any
  /// notes field, so existing configuration is visible without a click.
  @State private var notesExpanded = false
  @State private var didInitNotesExpansion = false

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
      header

      if model.lacksDriveScope(for: account.email) {
        driveScopeWarning
      }

      Divider()

      calendarsSection

      Divider()

      notesSection
    }
    .card(.inset, padding: Theme.Spacing.md)
    .onAppear {
      guard !didInitNotesExpansion else { return }
      notesExpanded = hasCustomNotes
      didInitNotesExpansion = true
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: Theme.Spacing.md) {
      Text(avatarInitial)
        .font(.callout.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background(avatarColor, in: Circle())
      Text(account.email)
        .font(.callout.weight(.semibold))
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      Button(loc("Reauthorize")) {
        model.saveConfig(draft)
        model.startReauthorize(email: account.email)
      }
      .buttonStyle(.borderless)
      .disabled(model.isSigningIn)
      Button(loc("Remove")) {
        Task { await model.logout(email: account.email) }
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.red)
    }
  }

  /// Caption warning shown when the account's grant is known to lack Drive
  /// access. The Reauthorize button in the header is the fix, so no extra
  /// button is needed here.
  private var driveScopeWarning: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(loc("Drive permission not granted — notes creation is unavailable."))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.caption)
  }

  // MARK: Calendars (calendar-scoped — the reason to connect an account)

  private var calendarsSection: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
      Text(loc("Calendars"))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      if calendars.isEmpty {
        Text(loc("No calendars loaded for this account."))
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, Theme.Spacing.xs)
      } else {
        ForEach(calendars) { calendar in
          CalendarSelectionRow(calendar: calendar, model: model)
        }
      }
    }
  }

  // MARK: Meeting Notes (account-scoped — secondary, collapsed by default)

  private var notesSection: some View {
    DisclosureGroup(isExpanded: $notesExpanded) {
      VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        folderRow

        Divider()

        SettingRow(loc("Note title"), subtitle: loc("{date} and {title} are filled in automatically")) {
          TextField(AppConfig.defaultNoteTitleTemplate, text: dictBinding(\.meetingNotesTitleTemplatesByAccount))
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)
        }

        Divider()

        templateRow

        if let error = model.templateError(for: account.email) {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }

        notesFootnote
      }
      .padding(.top, Theme.Spacing.sm)
    } label: {
      HStack(spacing: Theme.Spacing.sm) {
        Image(systemName: "doc.text")
          .foregroundStyle(.secondary)
        Text(loc("Meeting Notes"))
          .font(.callout.weight(.medium))
        if !notesExpanded {
          Text(loc("Optional — title & template"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  // App-managed folder row. The folder is created (or renamed) automatically
  // the next time a note is created; "Open in Drive" appears once an id is
  // stored.
  private var folderRow: some View {
    SettingRow(
      loc("Folder name"),
      subtitle: loc("Created in My Drive; renamed when you change this")
    ) {
      HStack(spacing: Theme.Spacing.sm) {
        TextField("Meeting Notes", text: dictBinding(\.meetingNotesFolderNamesByAccount))
          .textFieldStyle(.roundedBorder)
          .frame(width: 280)
        if selectedFolder != nil {
          Button {
            model.openNotesFolder(for: account.email)
          } label: {
            Label(loc("Open in Drive"), systemImage: "arrow.up.right.square")
          }
        }
      }
    }
  }

  private var templateRow: some View {
    let hasTemplate = model.meetingNotesTemplateDocId(for: account.email) != nil
    let isCreating = model.isCreatingTemplate(for: account.email)
    return SettingRow(loc("Template"), subtitle: loc("Start notes from an editable Google Doc")) {
      HStack(spacing: Theme.Spacing.sm) {
        if hasTemplate {
          Button {
            model.editTemplateDoc(for: account.email)
          } label: {
            Label(loc("Edit template"), systemImage: "square.and.pencil")
          }
          Button(loc("Reset")) {
            model.removeTemplateDoc(for: account.email)
          }
          .foregroundStyle(.red)
        } else if isCreating {
          HStack(spacing: Theme.Spacing.xs) {
            ProgressView()
              .controlSize(.small)
            Text(loc("Creating template…"))
              .foregroundStyle(.secondary)
          }
        } else {
          Button {
            model.createTemplateDoc(for: account.email)
          } label: {
            Label(loc("Create template"), systemImage: "doc.badge.plus")
          }
        }
      }
      .disabled(isCreating)
    }
  }

  private var notesFootnote: some View {
    let key = "The notes folder is created automatically in your Drive. Notes use a built-in template unless " +
      "you create your own, which you can edit in Google Docs. Notes need Drive and Docs access — " +
      "reconnect Google if creation fails."
    return Text(loc(key))
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var hasCustomNotes: Bool {
    selectedFolder != nil
      || !(draft.meetingNotesFolderNamesByAccount[account.email] ?? "").isEmpty
      || !(draft.meetingNotesTitleTemplatesByAccount[account.email] ?? "").isEmpty
      || !(draft.meetingNotesTemplateDocsByAccount[account.email] ?? "").isEmpty
  }

  // MARK: Account identity

  private var avatarInitial: String {
    account.email.first.map { String($0).uppercased() } ?? "?"
  }

  /// Stable color derived from the email so each account is visually
  /// distinguishable across launches (String.hashValue is seeded per run).
  private var avatarColor: Color {
    let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green]
    let sum = account.email.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[sum % palette.count]
  }

  /// Two-way binding into a per-account string dictionary on the draft config,
  /// treating a missing entry as an empty string.
  private func dictBinding(_ keyPath: WritableKeyPath<AppConfig, [String: String]>) -> Binding<String> {
    Binding(
      get: { draft[keyPath: keyPath][account.email] ?? "" },
      set: { newValue in
        if newValue.isEmpty {
          draft[keyPath: keyPath].removeValue(forKey: account.email)
        } else {
          draft[keyPath: keyPath][account.email] = newValue
        }
      }
    )
  }
}

private struct CalendarSelectionRow: View {
  var calendar: CalendarSummary
  @ObservedObject var model: AppModel

  var body: some View {
    HStack(spacing: Theme.Spacing.md) {
      Toggle("", isOn: Binding(
        get: { calendar.selected },
        set: { model.setCalendar(calendar.id, selected: $0) }
      ))
      .labelsHidden()

      Circle()
        .fill(Color(hex: calendar.backgroundColor) ?? .accentColor)
        .frame(width: 10, height: 10)

      VStack(alignment: .leading, spacing: 2) {
        Text(calendar.name)
          .font(.callout.weight(.medium))
          .lineLimit(1)
        Text(calendar.primary ? loc("primary") : calendar.googleId)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
    }
    .padding(.vertical, Theme.Spacing.xs)
  }
}

private struct FilterPreviewView: View {
  var result: FilterPreviewResult

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
      Text(loc("%1$d of %2$d events match", result.matched, result.total))
        .foregroundStyle(result.total == 0 ? .secondary : .primary)
      if result.sample.isEmpty {
        Text(loc("No events loaded to preview yet."))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
          ForEach(result.sample) { sample in
            HStack(spacing: Theme.Spacing.sm) {
              Image(systemName: sample.passed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(sample.passed ? .green : .secondary)
              Text(sample.title)
                .lineLimit(1)
              Spacer()
              Text(previewClock(sample.startDate))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .font(.callout)
          }
        }
      }
    }
    .card(.inset, padding: Theme.Spacing.md)
  }

  private static let previewClockFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
  }()

  private func previewClock(_ date: Date) -> String {
    Self.previewClockFormatter.string(from: date)
  }
}

private func googleEventColor(_ colorId: String) -> String? {
  [
    "1": "#a4bdfc",
    "2": "#7ae7bf",
    "3": "#dbadff",
    "4": "#ff887c",
    "5": "#fbd75b",
    "6": "#ffb878",
    "7": "#46d6db",
    "8": "#e1e1e1",
    "9": "#5484ed",
    "10": "#51b749",
    "11": "#dc2127"
  ][colorId]
}

private func notificationAuthorizationColor(_ state: NotificationAuthorizationState) -> Color {
  switch state {
  case .authorized, .provisional:
    return .green
  case .notDetermined:
    return .yellow
  case .denied:
    return .red
  case .unavailable, .unknown:
    return .secondary
  }
}
