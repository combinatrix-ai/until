import SwiftUI

struct PanelView: View {
  @ObservedObject var model: AppModel
  var openSettings: () -> Void
  @State private var showQuitConfirm = false

  var body: some View {
    VStack(spacing: 0) {
      content
      Divider()
      footer
    }
    .frame(width: 390, height: 520)
  }

  @ViewBuilder
  private var content: some View {
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
      VStack(spacing: 0) {
        // Cached events remain visible; the error rides above them as a compact
        // banner so a transient outage doesn't hide the whole panel.
        if let error = model.state.lastError {
          SyncErrorBanner(message: error)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
        }
        List {
          ForEach(model.daySections) { section in
            Section(dayHeader(section.day)) {
              ForEach(section.rows) { row in
                EventRow(event: row.event, day: row.day, model: model)
              }
            }
          }
        }
        .listStyle(.inset)
      }
    }
  }

  private var footer: some View {
    HStack(spacing: Theme.Spacing.sm) {
      Button {
        showQuitConfirm = true
      } label: {
        Image(systemName: "power")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
      .help(loc("Quit Until"))
      .confirmationDialog(loc("Quit Until?"), isPresented: $showQuitConfirm) {
        Button(loc("Quit"), role: .destructive) { NSApp.terminate(nil) }
        Button(loc("Cancel"), role: .cancel) {}
      }

      Text(statusText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      Spacer()

      Button {
        Task { await model.refresh() }
      } label: {
        Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
      }
      .buttonStyle(.borderless)
      .help(loc("Refresh"))

      Button(action: openSettings) {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.borderless)
      .help(loc("Preferences"))
    }
    .padding(.horizontal, Theme.Spacing.md)
    .padding(.vertical, Theme.Spacing.sm)
  }

  private var statusText: String {
    guard let date = model.state.lastSync else { return loc("Not synced yet") }
    let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
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

struct EventRow: View {
  private static let colorBarWidth: CGFloat = 3
  private static let timeColumnWidth: CGFloat = clockColumnWidth()
  private static let detailIndent = colorBarWidth + Theme.Spacing.sm + timeColumnWidth + Theme.Spacing.sm

  var event: CalendarEvent
  var day: Date
  @ObservedObject var model: AppModel

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
            if !model.noteURL(for: event).isEmpty {
              Image(systemName: "paperclip")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(loc("Meeting notes attached"))
            }
          }
          if !metadata.isEmpty {
            Text(metadata)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        Spacer(minLength: Theme.Spacing.sm)

        HStack(spacing: Theme.Spacing.xs) {
          if !event.conferenceUrl.isEmpty {
            Button {
              model.join(event)
            } label: {
              Image(systemName: "video")
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)
            .help(loc("Join video call"))
          } else {
            ConferenceActionButton(event: event, model: model)
          }

          NoteActionButton(event: event, model: model)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.easeInOut(duration: 0.2)) {
          model.toggleExpanded(event, on: day)
        }
      }

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
    }
  }

  private var eventColor: Color {
    Color(hex: googleEventColor(event.colorId) ?? event.calendar.backgroundColor) ?? .accentColor
  }

  private var metadata: String {
    let attendees = event.attendees
      .filter { !$0.selfUser && !$0.resource }
      .map { $0.name.isEmpty ? $0.email : $0.name }
    let parts: [String?] = [
      event.location.isEmpty ? nil : event.location,
      attendees.isEmpty ? nil : attendees.joined(separator: ", ")
    ]
    return parts.compactMap { $0 }.joined(separator: " · ")
  }
}

private struct NoteActionButton: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  @State private var showConfirm = false

  var body: some View {
    let notesUrl = model.noteURL(for: event)
    let isCreating = model.isCreatingNote(for: event)

    Button {
      if notesUrl.isEmpty {
        showConfirm = true
      } else {
        model.createOrOpenNote(for: event)
      }
    } label: {
      Group {
        if isCreating {
          ProgressView()
            .controlSize(.small)
            .frame(width: 14, height: 14)
        } else {
          Image(systemName: notesUrl.isEmpty ? "doc.badge.plus" : "doc.text")
            .foregroundStyle(notesUrl.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
        }
      }
    }
    .buttonStyle(.borderless)
    .disabled(isCreating)
    .help(notesUrl.isEmpty ? loc("Create meeting notes") : loc("Open meeting notes"))
    .confirmationDialog(loc("Create meeting notes?"), isPresented: $showConfirm) {
      Button(loc("Create notes")) { model.createOrOpenNote(for: event) }
      Button(loc("Cancel"), role: .cancel) {}
    } message: {
      Text(loc("Create a Google Doc for %@ and attach it to the calendar event.", event.title))
    }
  }
}

private struct ConferenceActionButton: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel
  @State private var showConfirm = false

  var body: some View {
    let isAdding = model.isAddingConference(for: event)

    Button {
      showConfirm = true
    } label: {
      Group {
        if isAdding {
          ProgressView()
            .controlSize(.small)
            .frame(width: 14, height: 14)
        } else {
          Image(systemName: "video.badge.plus")
            .foregroundStyle(.primary)
        }
      }
    }
    .buttonStyle(.borderless)
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
        Button {
          copyEventDetails()
        } label: {
          Image(systemName: copiedRecently ? "checkmark" : "doc.on.doc")
            .font(.caption)
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(copiedRecently ? Color.green : Color.accentColor)
        .help(copiedRecently ? loc("Copied event details") : loc("Copy event details"))
        .accessibilityLabel(loc("Copy event details"))

        Button {
          model.open(event)
        } label: {
          Image(systemName: "arrow.up.right.square")
            .font(.caption)
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.accentColor)
        .help(loc("Open in Calendar"))
        .accessibilityLabel(loc("Open in Calendar"))
      }
    }
    .padding(.vertical, Theme.Spacing.xs)
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
        Button {
          model.cancelExternalSharePrompt()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
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
