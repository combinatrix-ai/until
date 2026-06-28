import SwiftUI

struct PanelView: View {
  @ObservedObject var model: AppModel
  var openSettings: () -> Void

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
    if !model.state.auth.authenticated {
      OnboardingView(model: model)
    } else if let error = model.state.lastError {
      EmptyStateView(systemImage: "exclamationmark.triangle", title: "Sync Error", detail: error)
        .frame(maxHeight: .infinity)
    } else if model.state.events.isEmpty && model.state.allDayEvents.isEmpty {
      EmptyStateView(
        systemImage: "calendar",
        title: "No Events",
        detail: "No upcoming events match the selected calendars, fetch window, and filter."
      )
      .frame(maxHeight: .infinity)
    } else {
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

  private var footer: some View {
    HStack(spacing: Theme.Spacing.sm) {
      Button {
        NSApp.terminate(nil)
      } label: {
        Image(systemName: "power")
          .foregroundStyle(.red)
      }
      .buttonStyle(.borderless)
      .help("Quit Until")

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
      .help("Refresh")

      Button(action: openSettings) {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.borderless)
      .help("Preferences")
    }
    .padding(.horizontal, Theme.Spacing.md)
    .padding(.vertical, Theme.Spacing.sm)
  }

  private var statusText: String {
    guard let date = model.state.lastSync else { return "Not synced yet" }
    let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
    return minutes == 0 ? "Updated just now" : "Updated \(relativeWhen(minutes)) ago"
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
          Text("Your next Google Calendar event, always in the menubar.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
        }
      }

      VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        FeatureRow(
          systemImage: "menubar.arrow.up.rectangle",
          title: "Glance at what's next",
          detail: "Your upcoming meeting lives in the menubar."
        )
        FeatureRow(
          systemImage: "bell.badge",
          title: "Never miss a join",
          detail: "Native reminders before your video calls start."
        )
        FeatureRow(
          systemImage: "doc.text",
          title: "One-click meeting notes",
          detail: "Open or create notes straight from an event."
        )
      }
      .frame(maxWidth: 300)

      VStack(spacing: Theme.Spacing.sm) {
        Button {
          Task { await model.login() }
        } label: {
          HStack(spacing: Theme.Spacing.sm) {
            if model.isSigningIn {
              ProgressView()
                .controlSize(.small)
            } else {
              Image(systemName: "person.crop.circle.badge.plus")
            }
            Text(model.isSigningIn ? "Opening Google sign-in…" : "Sign in with Google")
          }
          .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .disabled(model.isSigningIn)
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
  var event: CalendarEvent
  var day: Date
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
      HStack(spacing: Theme.Spacing.sm) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(eventColor)
          .frame(width: 3)

        Text(event.allDay ? "all-day" : clock(event.startDate))
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
          .frame(width: 46, alignment: .leading)

        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: Theme.Spacing.xs) {
            Text(event.title)
              .font(.body)
              .lineLimit(2)
            if !model.noteURL(for: event).isEmpty {
              Image(systemName: "paperclip")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Meeting notes attached")
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
            .help("Join video call")
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
          .padding(.leading, 57)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }

      if let prompt = model.externalSharePrompt, prompt.id == event.actionKey {
        ExternalShareOverlay(prompt: prompt, model: model)
          .padding(.leading, 57)
      }

      if let error = model.noteError(for: event) {
        NoteErrorOverlay(message: error) {
          model.createOrOpenNote(for: event)
        }
        .padding(.leading, 57)
      }

      if let error = model.conferenceError(for: event) {
        NoteErrorOverlay(message: error) {
          model.addConference(for: event)
        }
        .padding(.leading, 57)
      }
    }
    .padding(.vertical, Theme.Spacing.xs)
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
    .help(notesUrl.isEmpty ? "Create meeting notes" : "Open meeting notes")
    .confirmationDialog("Create meeting notes?", isPresented: $showConfirm) {
      Button("Create notes") { model.createOrOpenNote(for: event) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Create a Google Doc for \(event.title) and attach it to the calendar event.")
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
    .help("Add Google Meet")
    .confirmationDialog("Add Google Meet?", isPresented: $showConfirm) {
      Button("Add Meet") { model.addConference(for: event) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Add a Google Meet video link to \(event.title).")
    }
  }
}

private struct EventDetailView: View {
  var event: CalendarEvent
  @ObservedObject var model: AppModel

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
              Text(attendee.name.isEmpty ? attendee.email : attendee.name)
                .font(.caption)
                .foregroundStyle(.primary)
            }
          }
        }
      }

      Button {
        model.open(event)
      } label: {
        Label("Open in Calendar", systemImage: "arrow.up.right.square")
          .font(.caption)
      }
      .buttonStyle(.borderless)
      .foregroundStyle(Color.accentColor)
    }
    .padding(.vertical, Theme.Spacing.xs)
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
          Text("External attendees")
            .font(.caption.weight(.semibold))
          Text(prompt.externalAttendees.prefix(3).joined(separator: ", ") + overflowText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      HStack(spacing: Theme.Spacing.sm) {
        Button("Internal only") {
          model.resolveExternalShare(shareExternalAttendees: false)
        }
        Button("Share externally") {
          model.resolveExternalShare(shareExternalAttendees: true)
        }
        .buttonStyle(.borderedProminent)
        Button {
          model.cancelExternalSharePrompt()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .help("Cancel")
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
    prompt.externalAttendees.count > 3 ? " and \(prompt.externalAttendees.count - 3) more" : ""
  }
}

private struct NoteErrorOverlay: View {
  var message: String
  var retry: () -> Void

  var body: some View {
    HStack(spacing: Theme.Spacing.sm) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.red)
      Text(message)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Spacer()
      Button("Retry", action: retry)
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
    (key: "168", label: "1w", hours: 168)
  ]

  /// The settings sections, shown as a sidebar instead of OS-standard tabs.
  private enum Section: String, CaseIterable, Identifiable {
    case accounts, general, filter
    var id: String { rawValue }

    var label: String {
      switch self {
      case .accounts: return "Accounts"
      case .general: return "General"
      case .filter: return "Filter"
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

  @ObservedObject var model: AppModel
  @State private var draft: AppConfig
  @State private var usesCustomFetchWindow: Bool
  @State private var saveTask: Task<Void, Never>?
  @State private var folderPickerTarget: FolderPickerTarget?
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
    .sheet(item: $folderPickerTarget) { target in
      DriveFolderPickerSheet(model: model, accountEmail: target.accountEmail)
    }
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
      ConnectedAccountsPanel(model: model, draft: $draft) { accountEmail in
        folderPickerTarget = FolderPickerTarget(accountEmail: accountEmail)
      }
    }
    .task {
      if model.calendars.isEmpty {
        await model.refreshCalendars()
      }
    }
  }

  private var generalTab: some View {
    SettingsTab {
      SettingsCard("Sync") {
        stepperRow(
          "Refresh interval",
          subtitle: "How often to check Google Calendar for changes",
          value: $draft.pollIntervalSeconds, range: 30...3600, step: 30, unit: "sec"
        )
        Divider()
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Fetch window")
              .font(.callout)
            Text("How far ahead to load events")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          fetchWindowControls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      SettingsCard("Menubar") {
        stepperRow(
          "Max title length",
          subtitle: "Longer event titles are shortened with “…”",
          value: $draft.maxTitleLength, range: 10...120, step: 1, unit: "characters"
        )
        Divider()
        stepperRow(
          "Show upcoming event",
          subtitle: "How early the next event appears in the menubar",
          value: $draft.menubarLeadMinutes, range: 0...720, step: 1, unit: "min before"
        )
      }

      SettingsCard("Notifications") {
        SettingRow("Event reminders", subtitle: "Send a notification before an event starts") {
          Toggle("", isOn: $draft.notifyEnabled)
            .labelsHidden()
        }
        Divider()
        SettingRow("Remind me about") {
          Picker("", selection: $draft.notifyVideoOnly) {
            Text("All events").tag(false)
            Text("Video only").tag(true)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 210)
        }
        .disabled(!draft.notifyEnabled)
        Divider()
        stepperRow(
          "Reminder timing",
          subtitle: "How long before an event the reminder fires",
          value: $draft.notifyLeadMinutes, range: 0...120, step: 1, unit: "min before"
        )
        .disabled(!draft.notifyEnabled)

        Divider()

        SettingRow("Notification access", subtitle: "Granted in macOS System Settings") {
          HStack(spacing: Theme.Spacing.sm) {
            Circle()
              .fill(notificationAuthorizationColor(model.notificationAuthorizationState))
              .frame(width: 8, height: 8)
            Text(model.notificationAuthorizationState.label)
            Button {
              Task { await model.refreshNotificationAuthorizationState() }
            } label: {
              Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Re-check permission")
          }
        }
        Divider()
        SettingRow("System Settings", subtitle: "Manage how reminders are delivered") {
          Button("Open") { model.openNotificationSettings() }
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
                Text("Sending test reminder")
              }
            } else {
              Label("Send test reminder", systemImage: "bell.badge")
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
      SettingsCard("Filter", subtitle: "Only matching events appear in the menubar and list", accessory: {
        Button("Reset to defaults") {
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

  private var fetchWindowControls: some View {
    HStack(spacing: Theme.Spacing.md) {
      Picker("Fetch window", selection: fetchWindowSelection) {
        ForEach(Self.fetchWindowPresets, id: \.key) { preset in
          Text(preset.label).tag(preset.key)
        }
        Text("Custom").tag("custom")
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 250)

      if usesCustomFetchWindow {
        Stepper(value: $draft.lookaheadHours, in: 1...168, step: 1) {
          Text("\(draft.lookaheadHours)h")
            .monospacedDigit()
            .frame(minWidth: 36, alignment: .trailing)
        }
      }

      Spacer()
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

private struct FolderPickerTarget: Identifiable {
  var accountEmail: String
  var id: String { accountEmail }
}

private struct ConnectedAccountsPanel: View {
  @ObservedObject var model: AppModel
  @Binding var draft: AppConfig
  var openFolderPicker: (String) -> Void

  var body: some View {
    SettingsCard("Google Accounts", accessory: {
      if !model.state.auth.accounts.isEmpty {
        HStack(spacing: Theme.Spacing.sm) {
          Button {
            Task { await model.refreshCalendars() }
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          addAccountButton
            .buttonStyle(.borderedProminent)
        }
      }
    }, content: {
      if model.state.auth.accounts.isEmpty {
        EmptyStateView(
          systemImage: "person.crop.circle.badge.plus",
          title: "No accounts connected",
          detail: "Connect a Google account to see your calendar."
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
              draft: $draft,
              openFolderPicker: openFolderPicker
            )
          }
        }
      }

      if model.isSigningIn {
        HStack(spacing: Theme.Spacing.sm) {
          ProgressView()
            .controlSize(.small)
          Text("Opening Google sign-in...")
            .foregroundStyle(.secondary)
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
      Task { await model.login() }
    } label: {
      Label("Add Account", systemImage: "plus")
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
  var openFolderPicker: (String) -> Void

  /// Meeting Notes is collapsed by default — most accounts run on the defaults.
  /// It auto-expands on first appearance for accounts that have customized any
  /// notes field, so existing configuration is visible without a click.
  @State private var notesExpanded = false
  @State private var didInitNotesExpansion = false

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
      header

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
      Button("Reauthorize") {
        model.saveConfig(draft)
        Task { await model.reauthorize(email: account.email) }
      }
      .buttonStyle(.borderless)
      .disabled(model.isSigningIn)
      Button("Remove") {
        Task { await model.logout(email: account.email) }
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.red)
    }
  }

  // MARK: Calendars (calendar-scoped — the reason to connect an account)

  private var calendarsSection: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
      Text("Calendars")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      if calendars.isEmpty {
        Text("No calendars loaded for this account.")
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
        SettingRow("Folder", subtitle: selectedFolder?.displayPath ?? "My Drive / Meeting Notes") {
          Button {
            openFolderPicker(account.email)
          } label: {
            Label(selectedFolder == nil ? "Choose" : "Change", systemImage: "folder")
          }
        }

        Divider()

        SettingRow("Note title", subtitle: "{date} and {title} are filled in automatically") {
          TextField(AppConfig.defaultNoteTitleTemplate, text: dictBinding(\.meetingNotesTitleTemplatesByAccount))
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)
        }

        Divider()

        SettingRow("Template Doc", subtitle: "Start new notes from a Google Doc (URL or ID)") {
          TextField("https://docs.google.com/document/d/...", text: dictBinding(\.meetingNotesTemplateDocsByAccount))
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)
        }

        notesFootnote
      }
      .padding(.top, Theme.Spacing.sm)
    } label: {
      HStack(spacing: Theme.Spacing.sm) {
        Image(systemName: "doc.text")
          .foregroundStyle(.secondary)
        Text("Meeting Notes")
          .font(.callout.weight(.medium))
        if !notesExpanded {
          Text("Optional — folder, title & template")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var notesFootnote: some View {
    Text(
      "Every field is optional — leave any blank to use the default. "
        + "Notes are saved to “My Drive / Meeting Notes” from a built-in template. "
        + "Notes need Drive and Docs access — reconnect Google if creation fails."
    )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var hasCustomNotes: Bool {
    selectedFolder != nil
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
        Text(calendar.primary ? "primary" : calendar.googleId)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
    }
    .padding(.vertical, Theme.Spacing.xs)
  }
}

private struct DriveFolderPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: AppModel
  var accountEmail: String

  @State private var stack: [DriveFolderRef] = []
  @State private var items: [DriveFolderRef] = []
  @State private var isLoading = false
  @State private var error: String?

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
      Divider()
      footer
    }
    .frame(width: 560, height: 440)
    .task {
      await loadRoots()
    }
  }

  private var header: some View {
    HStack(spacing: Theme.Spacing.md) {
      Image(systemName: "folder")
        .font(.title3)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text("Choose notes folder")
          .font(.headline)
        Text(accountEmail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.borderless)
      .help("Close")
    }
    .padding(Theme.Spacing.lg)
  }

  @ViewBuilder
  private var content: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
      breadcrumb

      if isLoading {
        Spacer()
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
        Spacer()
      } else if let error {
        InlineErrorView(message: error)
        Spacer()
      } else if items.isEmpty {
        EmptyStateView(systemImage: "folder", title: "No folders here")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(items) { folder in
          DriveFolderRow(folder: folder, canSelect: canSelect(folder)) {
            Task { await open(folder) }
          } select: {
            select(folder)
          }
        }
        .listStyle(.inset)
      }
    }
    .padding(Theme.Spacing.lg)
  }

  private var breadcrumb: some View {
    HStack(spacing: Theme.Spacing.sm) {
      Button {
        Task { await loadRoots() }
      } label: {
        Label("Roots", systemImage: "externaldrive")
      }
      .buttonStyle(.borderless)

      ForEach(stack) { folder in
        Image(systemName: "chevron.right")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Button(folder.name) {
          Task { await jump(to: folder) }
        }
        .buttonStyle(.borderless)
      }
      Spacer()
    }
    .font(.caption)
  }

  private var footer: some View {
    HStack(spacing: Theme.Spacing.sm) {
      if let current = stack.last, canSelect(current) {
        Button {
          select(current)
        } label: {
          Label("Choose Current Folder", systemImage: "checkmark")
        }
        .buttonStyle(.borderedProminent)
      }
      Spacer()
      Button("Cancel") {
        dismiss()
      }
    }
    .padding(Theme.Spacing.lg)
  }

  private func loadRoots() async {
    stack = []
    await load {
      try await model.driveRoots(for: accountEmail)
    }
  }

  private func open(_ folder: DriveFolderRef) async {
    stack.append(folder)
    await load {
      try await model.driveFolders(for: accountEmail, in: folder)
    }
  }

  private func jump(to folder: DriveFolderRef) async {
    guard let index = stack.firstIndex(of: folder) else { return }
    stack = Array(stack.prefix(index + 1))
    await load {
      try await model.driveFolders(for: accountEmail, in: folder)
    }
  }

  private func load(_ action: () async throws -> [DriveFolderRef]) async {
    isLoading = true
    error = nil
    do {
      items = try await action()
    } catch {
      self.error = error.localizedDescription
      items = []
    }
    isLoading = false
  }

  private func select(_ folder: DriveFolderRef) {
    model.setMeetingNotesFolder(folder, for: accountEmail)
    dismiss()
  }

  private func canSelect(_ folder: DriveFolderRef) -> Bool {
    !(folder.source == .sharedWithMe && folder.id == "shared-with-me")
  }
}

private struct DriveFolderRow: View {
  var folder: DriveFolderRef
  var canSelect: Bool
  var open: () -> Void
  var select: () -> Void

  var body: some View {
    HStack(spacing: Theme.Spacing.md) {
      Image(systemName: folder.source == .sharedDrive ? "externaldrive" : "folder")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(folder.name)
          .font(.callout.weight(.medium))
          .lineLimit(1)
        Text(sourceLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Open", action: open)
      if canSelect {
        Button("Select", action: select)
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(.vertical, Theme.Spacing.xs)
  }

  private var sourceLabel: String {
    switch folder.source {
    case .myDrive: return "My Drive"
    case .sharedDrive: return "Shared drive"
    case .sharedWithMe: return "Shared with me"
    }
  }
}

private struct FilterPreviewView: View {
  var result: FilterPreviewResult

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
      Text("\(result.matched) of \(result.total) events match")
        .foregroundStyle(result.total == 0 ? .secondary : .primary)
      if result.sample.isEmpty {
        Text("No events loaded to preview yet.")
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

  private func previewClock(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
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
