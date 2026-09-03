import SwiftUI

extension Notification.Name {
  static let untilPopoverWillShow = Notification.Name("untilPopoverWillShow")
}

private struct HeroFramePreferenceKey: PreferenceKey {
  static var defaultValue: CGRect?

  static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
    value = nextValue()
  }
}

private enum TimelineScrollSpace {
  static let name = "until.timeline.scroll"
}

struct PanelView: View {
  @ObservedObject var model: AppModel
  var openSettings: () -> Void
  @State private var showQuitConfirm = false
  @State private var scrollResetToken = 0
  @State private var heroIsVisible = true
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
      // Solid surface matching the timeline's background, so the hero, rail,
      // and footer don't show NSPopover's frosted material while the content
      // body is opaque (the popover chrome — corners and arrow — is painted
      // by `StatusBarController.popoverWillShow`).
      .background(Color(nsColor: .textBackgroundColor))
    }
    .onReceive(NotificationCenter.default.publisher(for: .untilPopoverWillShow)) { _ in
      scrollResetToken += 1
      heroIsVisible = true
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
      let presentation = AppModel.timelinePresentation(
        menubarEvent: model.menubarEvent,
        config: model.config,
        timed: model.state.events,
        now: now,
        coverageEnd: model.state.calendarCoverageEnd
      )

      VStack(spacing: 0) {
        // The timeline keeps the menubar selection inline and gives the
        // free-day fallback a prominent card in today's section. The error
        // banner remains outside the scrollable rail so cached content stays
        // usable during a transient sync failure.
        timeline(presentation: presentation, now: now)

        // Cached events remain visible; the error rides above them as a compact
        // banner so a transient outage doesn't hide the whole panel.
        if let error = model.state.lastError {
          SyncErrorBanner(message: error)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
        }
      }
    }
  }

  private func timeline(presentation: TimelinePresentation, now: Date) -> some View {
    let sections = AppModel.timelineSections(
      model.daySections(now: now),
      presentation: presentation,
      now: now,
      coverageEnd: model.state.calendarCoverageEnd
    )
    let target = initialTimelineTarget(sections: sections, presentation: presentation, now: now)

    return GeometryReader { viewport in
      ZStack(alignment: .top) {
        timelineScrollView(
          sections: sections,
          target: target,
          presentation: presentation,
          now: now,
          viewportHeight: viewport.size.height
        )

        LinearGradient(
          colors: [Color(nsColor: .textBackgroundColor).opacity(0.94), .clear],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: 40)
        .allowsHitTesting(false)

        if let hero = presentation.heroEvent, !heroIsVisible {
          CondensedHeroStrip(event: hero, model: model, now: now)
            .transition(.opacity)
            .zIndex(2)
        }
      }
      .animation(.easeInOut(duration: Theme.hoverFadeDuration), value: heroIsVisible)
    }
    .frame(maxHeight: .infinity)
  }

  private func timelineScrollView(
    sections: [(section: DaySection, items: [PopoverListItem])],
    target: String?,
    presentation: TimelinePresentation,
    now: Date,
    viewportHeight: CGFloat
  ) -> some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(sections, id: \.section.id) { entry in
            TimelineDayHeader(day: entry.section.day, now: now)
            ForEach(entry.items) { item in
              timelineItem(item, presentation: presentation, now: now)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.md)
      }
      .coordinateSpace(name: TimelineScrollSpace.name)
      .onAppear {
        scrollToInitialTarget(target, using: proxy)
      }
      .onChange(of: scrollResetToken) { _ in
        scrollToInitialTarget(target, using: proxy)
      }
      .onPreferenceChange(HeroFramePreferenceKey.self) { frame in
        guard presentation.heroEvent != nil else {
          heroIsVisible = true
          return
        }
        guard let frame else { return }
        heroIsVisible = frame.maxY > 0 && frame.minY < viewportHeight
      }
    }
  }

  @ViewBuilder
  private func timelineItem(
    _ item: PopoverListItem,
    presentation: TimelinePresentation,
    now: Date
  ) -> some View {
    switch item {
    case .event(let dayEvent):
      let event = dayEvent.event
      let isHero = presentation.heroEvent?.actionKey == event.actionKey
      let isNow = presentation.nowEmphasisEvent?.actionKey == event.actionKey
      let nextEvent = AppModel.nextTimelineEvent(
        heroEvent: presentation.heroEvent,
        timed: model.state.events,
        now: now
      )
      let isNext = nextEvent?.actionKey == event.actionKey
      if isHero {
        HeroTimelineRow(event: event, model: model, now: now)
          .background(heroFrameTracker)
          .id(item.id)
      } else {
        EventRow(
          event: event,
          day: dayEvent.day,
          model: model,
          now: now,
          isNowEmphasized: isNow,
          isNext: isNext
        )
        .id(item.id)
      }
    case .gap(let gap):
      FreeGapRow(gap: gap)
        .id(item.id)
    case .freeDay:
      FreeDayRow()
        .id(item.id)
    case .freeDayHero:
      FreeDayTimelineRow(nextEvent: presentation.freeDayNextEvent, now: now)
        .id(item.id)
    case .nowLine(let date):
      NowLineRow(now: date)
        .id(item.id)
    }
  }

  private var heroFrameTracker: some View {
    GeometryReader { proxy in
      Color.clear.preference(
        key: HeroFramePreferenceKey.self,
        value: proxy.frame(in: .named(TimelineScrollSpace.name))
      )
    }
  }

  /// The item anchored to the top when the popover opens: whatever marks the
  /// CURRENT MOMENT, never a merely-upcoming hero. Anchoring a future hero
  /// would hide the now-line and everything between now and that event, so a
  /// not-yet-started hero card simply sits below the anchor and scrolls into
  /// view naturally (it is the next chronological item).
  private func initialTimelineTarget(
    sections: [(section: DaySection, items: [PopoverListItem])],
    presentation: TimelinePresentation,
    now: Date
  ) -> String? {
    let items = sections.flatMap(\.items)
    func eventItemID(_ event: CalendarEvent) -> String? {
      items.first { item in
        guard case .event(let dayEvent) = item else { return false }
        return dayEvent.event.actionKey == event.actionKey
      }?.id
    }

    if let hero = presentation.heroEvent,
       AppModel.menubarHeroState(event: hero, now: now) == .now,
       let id = eventItemID(hero) {
      return id
    }
    if let nowEvent = presentation.nowEmphasisEvent, let id = eventItemID(nowEvent) {
      return id
    }
    // The free-day card renders above today's now-line, so it must win the
    // anchor or it would be hidden right after opening.
    if presentation.showsFreeDayHero,
       let freeDayHero = items.first(where: {
         if case .freeDayHero = $0 { return true }
         return false
       }) {
      return freeDayHero.id
    }
    if let nowLine = items.first(where: {
      if case .nowLine = $0 { return true }
      return false
    }) {
      return nowLine.id
    }
    return items.first?.id
  }

  /// Slightly below the very top, so the anchored item clears the top fade
  /// gradient and the previous row peeks above it half-faded.
  private static let initialScrollAnchor = UnitPoint(x: 0, y: 0.06)

  private func scrollToInitialTarget(_ target: String?, using proxy: ScrollViewProxy) {
    guard let target else { return }
    DispatchQueue.main.async {
      if reduceMotion {
        proxy.scrollTo(target, anchor: Self.initialScrollAnchor)
      } else {
        withAnimation(.easeOut(duration: 0.15)) {
          proxy.scrollTo(target, anchor: Self.initialScrollAnchor)
        }
      }
    }
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

private struct TimelineDayHeader: View {
  var day: Date
  var now: Date

  var body: some View {
    Text(dayHeader(day, now: now))
      .font(.caption.weight(.bold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, Theme.Spacing.lg)
      .padding(.top, Theme.Spacing.md)
      .padding(.bottom, Theme.Spacing.xs)
  }
}

private struct TimelineTimeLabel: View {
  var label: String
  var color: Color = .secondary
  var weight: Font.Weight = .regular

  var body: some View {
    Text(label)
      .font(.system(.caption2, design: .monospaced).weight(weight))
      .foregroundStyle(color)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .frame(width: clockColumnWidth(), alignment: .trailing)
      .padding(.trailing, Theme.Spacing.sm)
  }
}

private struct TimelineRailNode: View {
  var color: Color
  var emphasized = false
  /// Pins the dot beside the row's first line instead of centering it. Card
  /// rows are tall enough that a centered dot drifts away from the time label
  /// it marks; list rows are short, so centering reads fine there.
  var topAligned = false
  /// With `topAligned`, where the dot's vertical center sits, measured from
  /// the top of the rail. Lets a row line the dot up with its title regardless
  /// of dot size. `nil` keeps the dot flush with the top edge.
  var dotCenterY: CGFloat?

  private var dotSize: CGFloat {
    emphasized ? 13 : 9
  }

  private var dotTopInset: CGFloat {
    guard topAligned, let dotCenterY else { return 0 }
    return max(0, dotCenterY - dotSize / 2)
  }

  var body: some View {
    ZStack(alignment: topAligned ? .top : .center) {
      Rectangle()
        .fill(Theme.hairline)
        .frame(width: 2)
        .frame(maxHeight: .infinity)
      Circle()
        .fill(color)
        .frame(width: dotSize, height: dotSize)
        .overlay {
          Circle()
            .stroke(Color(nsColor: .textBackgroundColor), lineWidth: 3)
        }
        .padding(.top, dotTopInset)
    }
    .frame(width: 22)
  }
}

private struct TimelineDashedRail: View {
  var body: some View {
    Path { path in
      // x matches TimelineRailNode's centered 2pt rail (22pt column center).
      path.move(to: CGPoint(x: 11, y: 0))
      path.addLine(to: CGPoint(x: 11, y: 30))
    }
    .stroke(
      Theme.hairline,
      style: StrokeStyle(lineWidth: 2, dash: [4, 3], dashPhase: 0)
    )
    .frame(width: 22, height: 30)
  }
}

private struct NowLineRow: View {
  var now: Date

  var body: some View {
    HStack(spacing: 0) {
      TimelineTimeLabel(label: clock(now), color: .green, weight: .bold)
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(Color.green)
          .frame(height: 2)
          .frame(maxWidth: .infinity)
          .clipShape(Capsule())
        Circle()
          .fill(Color.green)
          .frame(width: 8, height: 8)
          .offset(x: 7)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 12)
    }
    .padding(.horizontal, Theme.Spacing.lg)
    .padding(.vertical, Theme.Spacing.xs)
    .id("now-line")
  }
}

private struct FreeGapRow: View {
  var gap: FreeGap

  var body: some View {
    HStack(spacing: 0) {
      TimelineTimeLabel(label: "")
      TimelineDashedRail()
      Text(
        loc(
          "free until %@ · %@",
          clock(gap.until),
          loc("%dm", gap.durationMinutes)
        )
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .padding(.leading, Theme.Spacing.sm)
    }
    .padding(.horizontal, Theme.Spacing.lg)
    .padding(.vertical, Theme.Spacing.xs)
  }
}

private struct FreeDayRow: View {
  var body: some View {
    HStack(spacing: 0) {
      TimelineTimeLabel(label: "")
      TimelineDashedRail()
      HStack(spacing: Theme.Spacing.xs) {
        Image(systemName: "sun.max.fill")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Text(loc("free all day"))
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: true, vertical: false)
      .padding(.leading, Theme.Spacing.sm)
    }
    .padding(.horizontal, Theme.Spacing.lg)
    .padding(.vertical, Theme.Spacing.xs)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(loc("free all day"))
  }
}

private struct FreeDayTimelineRow: View {
  var nextEvent: CalendarEvent?
  var now: Date

  private var nextWhen: String? {
    guard let nextEvent else { return nil }
    let header = dayHeader(nextEvent.startDate, now: now)
    let inlineHeader = header == loc("Today") || header == loc("Tomorrow")
      ? header.lowercased()
      : header
    return "\(inlineHeader) \(clock(nextEvent.startDate))"
  }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      TimelineTimeLabel(label: "")
      TimelineRailNode(color: .green, emphasized: true, topAligned: true)
      VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
        HStack(alignment: .firstTextBaseline) {
          Text(loc("No more events today"))
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(.green)
          Spacer(minLength: Theme.Spacing.sm)
          if let nextWhen {
            Text(loc("until %@", nextWhen))
              .font(.system(size: 12, weight: .semibold))
              .monospacedDigit()
              .foregroundStyle(.green)
          }
        }
        HStack(spacing: Theme.Spacing.sm) {
          Image(systemName: "sun.max.fill")
            .foregroundStyle(.green)
            .accessibilityHidden(true)
          Text(loc("Free"))
        }
        .font(.system(size: 16, weight: .semibold))
        if let nextEvent, let nextWhen {
          Text(loc("Next: %@", "\(nextWhen) \(nextEvent.title)"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .padding(.leading, Theme.Spacing.sm)
      .padding(.horizontal, Theme.Spacing.md)
      .padding(.vertical, Theme.Spacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color.green.opacity(0.07),
        in: RoundedRectangle(cornerRadius: Theme.Radius.md)
      )
    }
    .padding(.horizontal, Theme.Spacing.lg)
    .padding(.vertical, Theme.Spacing.xs)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(loc("Free"))
  }
}

private struct HeroProgressBar: View {
  var fraction: Double

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 2)
          .fill(Color.green.opacity(0.18))
        RoundedRectangle(cornerRadius: 2)
          .fill(Color.green)
          .frame(width: proxy.size.width * fraction)
      }
    }
    .frame(height: 3)
  }
}

private struct HeroTimelineRow: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  var now: Date

  @State private var isHovered = false
  @State private var showAddConferenceConfirmation = false
  @State private var showCreateNotesConfirmation = false

  private var inProgress: Bool {
    AppModel.menubarHeroState(event: event, now: now) == .now
  }

  private var tintColor: Color {
    inProgress ? .green : .accentColor
  }

  private var day: Date {
    Calendar.current.startOfDay(for: event.startDate)
  }

  private var hasAttachedActions: Bool {
    !event.conferenceUrl.isEmpty || !model.noteURL(for: event).isEmpty
  }

  private var actionMenuButton: some View {
    EventActionMenuButton(
      event: event,
      model: model,
      isVisible: isHovered,
      requestAddConference: { showAddConferenceConfirmation = true },
      requestCreateNotes: { showCreateNotesConfirmation = true }
    )
  }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      TimelineTimeLabel(
        label: event.allDay ? loc("all-day") : clock(event.startDate),
        color: tintColor,
        weight: .bold
      )
      TimelineRailNode(color: tintColor, emphasized: true, topAligned: true)
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
          .font(.system(size: 15, weight: .bold))
          .lineLimit(2)

        // The ellipsis needs a home even when the metadata line is empty.
        if !metadataLine.isEmpty || !hasAttachedActions {
          HStack(spacing: Theme.Spacing.xs) {
            if !metadataLine.isEmpty {
              metadataSummary
            }
            if !hasAttachedActions {
              Spacer(minLength: 0)
              actionMenuButton
            }
          }
        }

        // Without an attached action the row would hold nothing but the
        // hover-revealed ellipsis, stretching the card for no content.
        if hasAttachedActions {
          HStack(spacing: Theme.Spacing.xs) {
            if !event.conferenceUrl.isEmpty {
              Button {
                model.join(event)
              } label: {
                Label(loc("Join"), systemImage: "video.fill")
              }
              .buttonStyle(.borderedProminent)
              .tint(tintColor)
            }
            // Attached-only, like the rows: an existing note earns a direct
            // button; creating one lives in the ellipsis menu.
            if !model.noteURL(for: event).isEmpty {
              QuietButton(systemImage: "doc.text", label: loc("Open notes")) {
                model.createOrOpenNote(for: event)
              }
              .help(loc("Open meeting notes"))
            }
            Spacer(minLength: 0)
            actionMenuButton
          }
          .padding(.top, Theme.Spacing.xs)
        }

        if model.isExpanded(event, on: day) {
          EventDetailView(event: event)
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
      .padding(.horizontal, Theme.Spacing.md)
      .padding(.vertical, Theme.Spacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      // One flat, borderless tint (S2): the rail has no hairlines, so the
      // card reads as a quiet raised surface rather than an outlined box.
      .background(
        tintColor.opacity(inProgress ? 0.08 : 0.07),
        in: RoundedRectangle(cornerRadius: Theme.Radius.md)
      )
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.easeInOut(duration: 0.2)) {
          model.toggleExpanded(event, on: day)
        }
      }
      .onHover { isHovered = $0 }
      .contextMenu {
        eventActionMenu(
          event: event,
          model: model,
          requestAddConference: { showAddConferenceConfirmation = true },
          requestCreateNotes: { showCreateNotesConfirmation = true }
        )
      }
      .padding(.leading, Theme.Spacing.sm)
    }
    .padding(.horizontal, Theme.Spacing.lg)
    .padding(.vertical, Theme.Spacing.xs)
    .modifier(
      EventActionConfirmationDialogs(
        event: event,
        model: model,
        showAddConferenceConfirmation: $showAddConferenceConfirmation,
        showCreateNotesConfirmation: $showCreateNotesConfirmation
      )
    )
  }

  private var kickerText: String {
    inProgress
      ? loc("Now · started %@ ago", relativeWhen(minutesSince(event.startDate)))
      : loc("Next")
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
    heroMetadataParts(for: event).joined(separator: " · ")
  }

  /// The collapsed hero keeps the summary to one line; once expanded, this
  /// same text is allowed to wrap in place so the action row simply moves down
  /// with it. The tooltip is only useful while the line is truncated.
  @ViewBuilder
  private var metadataSummary: some View {
    if model.isExpanded(event, on: day) {
      Text(metadataLine)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      Text(metadataLine)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help(metadataLine)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func minutesUntil(_ date: Date) -> Int {
    max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
  }

  private func minutesSince(_ date: Date) -> Int {
    max(0, Int((now.timeIntervalSince(date) / 60).rounded()))
  }
}

private struct CondensedHeroStrip: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  var now: Date

  private var heroState: AppModel.MenubarHeroState {
    AppModel.menubarHeroState(event: event, now: now) ?? .next
  }

  private var tintColor: Color {
    heroState == .now ? .green : .accentColor
  }

  private var countText: String {
    heroState == .now
      ? loc("%@ left", relativeWhen(minutesUntil(event.endDate)))
      : loc("in %@", relativeWhen(minutesUntil(event.startDate)))
  }

  var body: some View {
    HStack(spacing: Theme.Spacing.sm) {
      Text(heroState == .now ? loc("NOW") : loc("NEXT"))
        .font(.caption2.weight(.bold))
        .tracking(0.6)
        .foregroundStyle(tintColor)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 2)
        .overlay {
          Capsule().stroke(tintColor, lineWidth: 1.5)
        }
      Text(event.title)
        .font(.system(size: 12, weight: .bold))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(countText)
        .font(.system(size: 11, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(tintColor)
        .fixedSize(horizontal: true, vertical: false)
      if !event.conferenceUrl.isEmpty {
        Button {
          model.join(event)
        } label: {
          Label(loc("Join"), systemImage: "video.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(tintColor)
      }
    }
    .padding(.horizontal, Theme.Spacing.md)
    .padding(.vertical, Theme.Spacing.sm)
    .background(
      tintColor.opacity(heroState == .now ? 0.10 : 0.07)
    )
    // Opaque base behind the tint: the strip overlays the scrolled rail, so
    // the tint alone would let the rows underneath bleed through.
    .background(Color(nsColor: .textBackgroundColor))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(tintColor.opacity(0.22))
        .frame(height: 1)
    }
    .transition(.opacity)
  }

  private func minutesUntil(_ date: Date) -> Int {
    max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
  }
}

/// One menu content builder is used by both the ellipsis `Menu` and the row or
/// card context menu. Confirmation-producing actions stay at the surface so
/// the same action can be presented from either entry point.
private struct EventActionMenuContext {
  var event: CalendarEvent
  var model: AppModel
  var requestAddConference: () -> Void
  var requestCreateNotes: () -> Void
}

@MainActor
@ViewBuilder
private func eventActionMenu(
  event: CalendarEvent,
  model: AppModel,
  requestAddConference: @escaping () -> Void,
  requestCreateNotes: @escaping () -> Void
) -> some View {
  let actionSet = EventActionSet.make(
    event: event,
    noteURL: model.noteURL(for: event),
    isSkipped: model.isSkippedInMenubar(event)
  )
  let context = EventActionMenuContext(
    event: event,
    model: model,
    requestAddConference: requestAddConference,
    requestCreateNotes: requestCreateNotes
  )

  if !actionSet.attached.isEmpty {
    eventActionSection(
      title: loc("Already attached"),
      items: actionSet.attached,
      context: context
    )
  }

  if !actionSet.addable.isEmpty {
    eventActionSection(
      title: loc("Add more"),
      items: actionSet.addable,
      context: context
    )
  }

  eventCommonActionSection(
    items: actionSet.common,
    context: context
  )
}

@MainActor
@ViewBuilder
private func eventActionSection(
  title: String,
  items: [EventActionSet.Item],
  context: EventActionMenuContext
) -> some View {
  Section {
    eventActionMenuItems(
      items: items,
      context: context
    )
  } header: {
    Text(title)
  }
}

@MainActor
@ViewBuilder
private func eventCommonActionSection(
  items: [EventActionSet.Item],
  context: EventActionMenuContext
) -> some View {
  Section {
    eventActionMenuItems(
      items: Array(items.prefix(2)),
      context: context
    )
    Divider()
    eventActionMenuItems(
      items: Array(items.dropFirst(2)),
      context: context
    )
  }
}

@MainActor
@ViewBuilder
private func eventActionMenuItems(
  items: [EventActionSet.Item],
  context: EventActionMenuContext
) -> some View {
  ForEach(items, id: \.self) { item in
    eventActionMenuItem(item, context: context)
  }
}

@MainActor
@ViewBuilder
private func eventActionMenuItem(
  _ item: EventActionSet.Item,
  context: EventActionMenuContext
) -> some View {
  switch item {
  case .joinVideoCall, .copyMeetingLink, .openMeetingNotes:
    eventAttachedActionMenuItem(item, context: context)
  case .addGoogleMeet, .createNotes:
    eventAddableActionMenuItem(item, context: context)
  case .copyDetails, .openInCalendar, .skipInMenubar, .showInMenubar:
    eventCommonActionMenuItem(item, context: context)
  }
}

@MainActor
@ViewBuilder
private func eventAttachedActionMenuItem(
  _ item: EventActionSet.Item,
  context: EventActionMenuContext
) -> some View {
  switch item {
  case .joinVideoCall:
    Button {
      context.model.join(context.event)
    } label: {
      Label(loc("Join video call"), systemImage: "video")
    }
  case .copyMeetingLink:
    Button {
      copyStringToPasteboard(context.event.conferenceUrl)
    } label: {
      Label(loc("Copy meeting link"), systemImage: "link")
    }
  case .openMeetingNotes:
    Button {
      context.model.createOrOpenNote(for: context.event)
    } label: {
      Label(loc("Open meeting notes"), systemImage: "doc.text")
    }
  default:
    EmptyView()
  }
}

@MainActor
@ViewBuilder
private func eventAddableActionMenuItem(
  _ item: EventActionSet.Item,
  context: EventActionMenuContext
) -> some View {
  switch item {
  case .addGoogleMeet:
    Button {
      context.requestAddConference()
    } label: {
      Label(loc("Add Google Meet"), systemImage: "video.badge.plus")
    }
    .disabled(context.model.isAddingConference(for: context.event))
  case .createNotes:
    Button {
      context.requestCreateNotes()
    } label: {
      Label(loc("Create notes"), systemImage: "doc.badge.plus")
    }
    .disabled(context.model.isCreatingNote(for: context.event))
  default:
    EmptyView()
  }
}

@MainActor
@ViewBuilder
private func eventCommonActionMenuItem(
  _ item: EventActionSet.Item,
  context: EventActionMenuContext
) -> some View {
  switch item {
  case .copyDetails:
    Button {
      copyEventDetailsToPasteboard(context.event)
    } label: {
      Label(loc("Copy details"), systemImage: "doc.on.doc")
    }
  case .openInCalendar:
    Button {
      context.model.open(context.event)
    } label: {
      Label(loc("Open in Calendar"), systemImage: "calendar")
    }
  case .skipInMenubar:
    Button {
      context.model.skipInMenubar(context.event)
    } label: {
      Label(loc("Skip in menubar"), systemImage: "forward.end")
    }
  case .showInMenubar:
    Button {
      context.model.unskipInMenubar(context.event)
    } label: {
      Label(loc("Show in menubar"), systemImage: "arrow.uturn.backward")
    }
  default:
    EmptyView()
  }
}

private struct EventActionMenuButton: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  var isVisible: Bool
  var requestAddConference: () -> Void
  var requestCreateNotes: () -> Void

  @State private var isHovered = false

  var body: some View {
    Menu {
      eventActionMenu(
        event: event,
        model: model,
        requestAddConference: requestAddConference,
        requestCreateNotes: requestCreateNotes
      )
    } label: {
      ZStack {
        Circle()
          .fill(isHovered ? Theme.hoverFill : Color.clear)
        Image(systemName: "ellipsis")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
      }
      .frame(width: 22, height: 22)
      .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .buttonStyle(.borderless)
    // The label is a fixed 22pt circle; without this the borderless menu
    // style stretches the hit area to fill the row's trailing space.
    .fixedSize()
    .accessibilityLabel(loc("More actions"))
    .help(loc("More actions"))
    .animation(.easeInOut(duration: Theme.hoverFadeDuration), value: isHovered)
    .onHover { isHovered = $0 }
    .revealOnHover(isVisible)
  }
}

/// Spacing for a regular timeline row's secondary lines. The collapsed summary
/// and every expanded detail line share one icon gutter so their text starts
/// at a common left edge under the title.
private enum TimelineRowMetrics {
  static let iconWidth: CGFloat = 16
  static let iconGap: CGFloat = 6
  static let iconPointSize: CGFloat = 11
  /// Distance from the summary line's bottom to the first detail line.
  static let detailTopGap: CGFloat = 10
  /// Between the time range and the account line.
  static let metaGap: CGFloat = 4
  /// Between description and attendee lines.
  static let contentGap: CGFloat = 6
  /// Between the when/who-from group and the what/who group.
  static let groupGap: CGFloat = 10
  /// Half the title's line height (13pt body): where the dot centers.
  static let titleCenterY: CGFloat = 8
}

struct EventRow: View {
  var event: CalendarEvent
  var day: Date
  @ObservedObject var model: AppModel
  var now: Date
  var isNowEmphasized: Bool
  var isNext: Bool

  @State private var isHovered = false
  @State private var showAddConferenceConfirmation = false
  @State private var showCreateNotesConfirmation = false

  init(
    event: CalendarEvent,
    day: Date,
    model: AppModel,
    now: Date = Date(),
    isNowEmphasized: Bool = false,
    isNext: Bool = false
  ) {
    self.event = event
    self.day = day
    self.model = model
    self.now = now
    self.isNowEmphasized = isNowEmphasized
    self.isNext = isNext
  }

  var body: some View {
    // Time | rail | content. The rail sits beside a column holding both the
    // header and the expanded detail, so it runs the row's full height by
    // construction rather than being patched in with an overlay.
    HStack(alignment: .top, spacing: 0) {
      TimelineTimeLabel(
        label: event.allDay ? loc("all-day") : clock(event.startDate),
        color: isNowEmphasized ? .green : .secondary,
        weight: isNowEmphasized ? .bold : .regular
      )
      .padding(.top, Theme.Spacing.xs)
      TimelineRailNode(
        color: isNowEmphasized ? .green : eventColor,
        emphasized: isNowEmphasized,
        topAligned: true,
        dotCenterY: Theme.Spacing.xs + TimelineRowMetrics.titleCenterY
      )
      VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
        header
          .padding(.vertical, Theme.Spacing.xs)
          .contentShape(Rectangle())
          .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
              model.toggleExpanded(event, on: day)
            }
          }
          .onHover { isHovered = $0 }
          .opacity(rowOpacity)

        if model.isExpanded(event, on: day) {
          TimelineEventDetail(event: event)
            // Header bottom padding + stack spacing already contribute 8pt.
            .padding(.top, TimelineRowMetrics.detailTopGap - Theme.Spacing.xs * 2)
            .padding(.bottom, Theme.Spacing.sm)
            .transition(.opacity.combined(with: .move(edge: .top)))
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
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, Theme.Spacing.lg)
    .background {
      if isNowEmphasized {
        RoundedRectangle(cornerRadius: Theme.Radius.sm)
          .fill(Color.green.opacity(0.07))
          .padding(.horizontal, Theme.Spacing.sm)
      }
    }
    .contextMenu {
      eventActionMenu(
        event: event,
        model: model,
        requestAddConference: { showAddConferenceConfirmation = true },
        requestCreateNotes: { showCreateNotesConfirmation = true }
      )
    }
    .modifier(
      EventActionConfirmationDialogs(
        event: event,
        model: model,
        showAddConferenceConfirmation: $showAddConferenceConfirmation,
        showCreateNotesConfirmation: $showCreateNotesConfirmation
      )
    )
  }

  private var header: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: Theme.Spacing.xs) {
          Text(event.title)
            .font((isNowEmphasized || isNext) ? .body.weight(.bold) : .body)
            .lineLimit(2)
            .strikethrough(isPast, color: .secondary)
          if isNowEmphasized {
            StateChip(label: loc("NOW"), color: .green)
          }
          if isNext {
            StateChip(
              label: loc("NEXT · in %@", relativeWhen(minutesUntil(event.startDate))),
              color: .accentColor
            )
          }
          if isSkipped {
            SkippedBadge()
          }
        }

        summaryLine
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Spacer(minLength: Theme.Spacing.sm)

      HStack(spacing: Theme.Spacing.xs) {
        if !event.conferenceUrl.isEmpty {
          JoinVideoCallButton(event: event, model: model)
            .revealOnHover(isHovered)
        }

        if !model.noteURL(for: event).isEmpty {
          IconButton(systemImage: "doc.text") {
            model.createOrOpenNote(for: event)
          }
          .help(loc("Open meeting notes"))
          .revealOnHover(isHovered)
        }

        EventActionMenuButton(
          event: event,
          model: model,
          isVisible: isHovered,
          requestAddConference: { showAddConferenceConfirmation = true },
          requestCreateNotes: { showCreateNotesConfirmation = true }
        )
      }
    }
  }

  /// The collapsed row's one secondary line: where the event is (location,
  /// else the meeting provider). Attendees are never shown here; they belong
  /// to the expanded detail. A NOW row also carries its end time, set apart
  /// in the emphasis color rather than run into the place text.
  @ViewBuilder
  private var summaryLine: some View {
    let summary = timelineSummary(for: event)
    if summary != nil || isNowEmphasized {
      HStack(spacing: Theme.Spacing.sm) {
        if let summary {
          TimelineGutterRow(
            systemImage: summary.kind.systemImage,
            accessibilityLabel: summary.kind.accessibilityLabel
          ) {
            Text(summary.text)
              .lineLimit(1)
              .truncationMode(.tail)
          }
        }
        if isNowEmphasized {
          Text(loc("ends %@", clock(event.endDate)))
            .fontWeight(.medium)
            .monospacedDigit()
            .foregroundStyle(.green)
            .fixedSize()
        }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
    }
  }

  private var isPast: Bool {
    !event.allDay && event.endDate <= now
  }

  private var isSkipped: Bool {
    model.isSkippedInMenubar(event)
  }

  private var rowOpacity: Double {
    if isPast { return 0.5 }
    return isSkipped ? 0.55 : 1
  }

  private var eventColor: Color {
    Color(hex: googleEventColor(event.colorId) ?? event.calendar.backgroundColor) ?? .accentColor
  }

  private func minutesUntil(_ date: Date) -> Int {
    max(0, Int((date.timeIntervalSince(now) / 60).rounded()))
  }
}

/// One secondary line of a timeline row: a fixed-width icon slot, a small
/// gap, then the content, so every line's text shares the same left edge.
/// The icon is decorative for sighted users but names the line for
/// VoiceOver and on hover.
private struct TimelineGutterRow<Content: View>: View {
  var systemImage: String
  var accessibilityLabel: String
  var iconColor: Color = .secondary
  /// `.top` keeps the icon beside the first line of multi-line content.
  var iconAlignment: VerticalAlignment = .center
  @ViewBuilder var content: () -> Content

  var body: some View {
    HStack(alignment: iconAlignment, spacing: TimelineRowMetrics.iconGap) {
      Image(systemName: systemImage)
        .font(.system(size: TimelineRowMetrics.iconPointSize))
        .foregroundStyle(iconColor)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
        .frame(width: TimelineRowMetrics.iconWidth, height: TimelineRowMetrics.iconWidth)
      content()
    }
  }
}

/// The expanded body of a regular timeline row: when and from which account,
/// then what it is about and who is coming. Two quiet groups, no separators.
private struct TimelineEventDetail: View {
  var event: CalendarEvent

  private var others: [Attendee] {
    event.attendees.filter { !$0.selfUser && !$0.resource }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: TimelineRowMetrics.groupGap) {
      VStack(alignment: .leading, spacing: TimelineRowMetrics.metaGap) {
        TimelineGutterRow(systemImage: "clock", accessibilityLabel: loc("Time")) {
          Text(event.allDay ? loc("all-day") : timeRangeText(for: event))
            .monospacedDigit()
        }
        if !event.account.email.isEmpty {
          TimelineGutterRow(systemImage: "calendar", accessibilityLabel: loc("Calendar account")) {
            Text(event.account.email)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }
      }
      .foregroundStyle(.secondary)

      if !event.description.isEmpty || !others.isEmpty {
        VStack(alignment: .leading, spacing: TimelineRowMetrics.contentGap) {
          if !event.description.isEmpty {
            TimelineGutterRow(
              systemImage: "text.alignleft",
              accessibilityLabel: loc("Description"),
              iconAlignment: .top
            ) {
              Text(descriptionAttributedString(event.description))
                .foregroundStyle(.secondary)
                .lineLimit(isBareLink(event.description) ? 2 : 10)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          ForEach(others, id: \.email) { attendee in
            TimelineGutterRow(
              systemImage: attendeeResponseIcon(attendee.responseStatus),
              accessibilityLabel: attendeeResponseLabel(attendee.responseStatus),
              iconColor: attendeeResponseColor(attendee.responseStatus)
            ) {
              Text(attendee.name.isEmpty ? attendee.email : attendee.name)
                .lineLimit(1)
                .truncationMode(.tail)
            }
          }
        }
      }
    }
    .font(.subheadline)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// What a collapsed timeline row says under its title.
struct TimelineSummary: Equatable {
  enum Kind: Equatable {
    case location
    case meetingProvider

    var systemImage: String {
      switch self {
      case .location: return "mappin"
      case .meetingProvider: return "video"
      }
    }

    var accessibilityLabel: String {
      switch self {
      case .location: return loc("Location")
      case .meetingProvider: return loc("Video call")
      }
    }
  }

  var kind: Kind
  var text: String
}

/// The collapsed row's summary: the location, or the meeting provider when
/// there is no location, or nothing. Attendees are deliberately excluded so
/// the collapsed list stays one quiet line per event. Whitespace-only
/// locations count as absent, matching the hero's metadata.
func timelineSummary(for event: CalendarEvent) -> TimelineSummary? {
  let location = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
  if !location.isEmpty {
    return TimelineSummary(kind: .location, text: location)
  }
  if let provider = EventLinks.meetingProvider(for: event) {
    return TimelineSummary(kind: .meetingProvider, text: provider.label)
  }
  return nil
}

/// True when a description is nothing but a single web URL, so a row can show
/// it as a link clamped to two lines instead of treating it like prose.
func isBareLink(_ description: String) -> Bool {
  let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty,
        trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
        let scheme = URL(string: trimmed)?.scheme?.lowercased()
  else {
    return false
  }
  return scheme == "http" || scheme == "https"
}

private struct StateChip: View {
  var label: String
  var color: Color

  var body: some View {
    Text(label)
      .font(.system(size: 9.5, weight: .bold))
      .tracking(0.05)
      .foregroundStyle(color)
      .padding(.horizontal, Theme.Spacing.xs)
      .padding(.vertical, 1)
      .overlay {
        Capsule().stroke(color, lineWidth: 1)
      }
      .fixedSize(horizontal: true, vertical: false)
  }
}

/// "start – end" clock times for a timed event. Shared by the hero's metadata
/// line and timeline detail so the dash and spacing can't drift apart.
private func timeRangeText(for event: CalendarEvent) -> String {
  "\(clock(event.startDate)) – \(clock(event.endDate))"
}

/// Returns the hero's compact metadata in display order. Location and the
/// meeting provider are intentionally deduplicated: calendar data often puts
/// the provider name in both the location field and the conference link.
/// Whitespace-only values are treated as empty so an absent location/provider
/// never creates a blank separator in the summary.
func heroMetadataParts(for event: CalendarEvent) -> [String] {
  var parts: [String] = []
  let time = timeRangeText(for: event).trimmingCharacters(in: .whitespacesAndNewlines)
  if !time.isEmpty {
    parts.append(time)
  }

  let location = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
  if !location.isEmpty {
    parts.append(location)
  }

  if let provider = EventLinks.meetingProvider(for: event),
     location.caseInsensitiveCompare(provider.label) != .orderedSame {
    parts.append(provider.label)
  }

  return parts
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

/// Names the same-domain attendees who will receive edit access, so the
/// automatic grant is visible before the user confirms. External attendees
/// are asked about separately (ExternalShareOverlay) and not repeated here.
@MainActor
private func noteCreationConfirmationMessage(for event: CalendarEvent, model: AppModel) -> String {
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

/// The row "join the video call" shortcut: one home for the icon, action, and
/// help text. Joining reads nothing observable from the model, so this holds a
/// plain reference rather than an `@ObservedObject`.
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

private struct EventActionConfirmationDialogs: ViewModifier {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  @Binding var showAddConferenceConfirmation: Bool
  @Binding var showCreateNotesConfirmation: Bool

  func body(content: Content) -> some View {
    content
      .confirmationDialog(loc("Add Google Meet?"), isPresented: $showAddConferenceConfirmation) {
        Button(loc("Add Meet")) { model.addConference(for: event) }
        Button(loc("Cancel"), role: .cancel) {}
      } message: {
        Text(loc("Add a Google Meet video link to %@.", event.title))
      }
      .confirmationDialog(loc("Create meeting notes?"), isPresented: $showCreateNotesConfirmation) {
        Button(loc("Create notes")) { model.createOrOpenNote(for: event) }
        Button(loc("Cancel"), role: .cancel) {}
      } message: {
        Text(noteCreationConfirmationMessage(for: event, model: model))
      }
  }
}

/// The hero's expanded detail: account, description, attendees. Regular
/// timeline rows use `TimelineEventDetail` instead.
private struct EventDetailView: View {
  var event: CalendarEvent

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
      if !event.account.email.isEmpty {
        Text(event.account.email)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if !event.description.isEmpty {
        Text(descriptionAttributedString(event.description))
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
              Image(systemName: attendeeResponseIcon(attendee.responseStatus))
                .font(.system(size: 9))
                .foregroundStyle(attendeeResponseColor(attendee.responseStatus))
                .accessibilityLabel(attendeeResponseLabel(attendee.responseStatus))
              Text(attendee.name.isEmpty ? attendee.email : attendee.name)
                .font(.caption)
                .foregroundStyle(.primary)
            }
          }
        }
      }
    }
    .padding(.vertical, Theme.Spacing.xs)
  }
}

private func attendeeResponseIcon(_ status: String) -> String {
  switch status {
  case "accepted": return "checkmark.circle.fill"
  case "declined": return "xmark.circle.fill"
  case "tentative": return "questionmark.circle.fill"
  default: return "circle"
  }
}

private func attendeeResponseColor(_ status: String) -> Color {
  switch status {
  case "accepted": return .green
  case "declined": return .red
  case "tentative": return .orange
  default: return .secondary
  }
}

private func attendeeResponseLabel(_ status: String) -> String {
  switch status {
  case "accepted": return loc("Accepted")
  case "declined": return loc("Declined")
  case "tentative": return loc("Tentative")
  default: return loc("No response")
  }
}

/// Renders an event description (Google delivers HTML) as attributed text at
/// the detail size, tinting links with the accent color.
private func descriptionAttributedString(_ html: String) -> AttributedString {
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

private enum EventCopyFormatters {
  static let date: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  static let dateTime: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()
}

/// The text copied by the event action menu. Kept independent of the detail
/// view so the menu remains the single home for the copy action.
func eventCopyDetailsText(for event: CalendarEvent) -> String {
  var lines = [
    event.title,
    eventCopyTimeText(for: event)
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

private func eventCopyTimeText(for event: CalendarEvent) -> String {
  let calendar = Calendar.current

  if event.allDay {
    let displayEnd = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate
    let start = EventCopyFormatters.date.string(from: event.startDate)
    if calendar.isDate(event.startDate, inSameDayAs: displayEnd) {
      return "\(start) \(loc("all-day"))"
    }
    let end = EventCopyFormatters.date.string(from: displayEnd)
    return "\(start) - \(end) \(loc("all-day"))"
  }

  if calendar.isDate(event.startDate, inSameDayAs: event.endDate) {
    let day = EventCopyFormatters.date.string(from: event.startDate)
    return "\(day), \(clock(event.startDate)) - \(clock(event.endDate))"
  }
  let start = EventCopyFormatters.dateTime.string(from: event.startDate)
  let end = EventCopyFormatters.dateTime.string(from: event.endDate)
  return "\(start) - \(end)"
}

private func copyStringToPasteboard(_ string: String) {
  let pasteboard = NSPasteboard.general
  pasteboard.clearContents()
  pasteboard.setString(string, forType: .string)
}

private func copyEventDetailsToPasteboard(_ event: CalendarEvent) {
  copyStringToPasteboard(eventCopyDetailsText(for: event))
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
#if SPARKLE
        Divider()
        SettingRow(
          loc("Software updates"),
          subtitle: loc("Until updates automatically; check now to update sooner")
        ) {
          Button(loc("Check for Updates...")) { model.updater.checkForUpdates() }
            .disabled(!model.updater.canCheckForUpdates)
        }
#endif
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
