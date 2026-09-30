import AppKit
import SwiftUI

/// Decides which meeting the start alert is for and when it should appear.
/// Pure so the timing rules can be tested without windows.
enum StartAlertSchedule {
  /// A started meeting still gets its alert for this long, e.g. after the Mac
  /// wakes from sleep a minute late.
  static let lateGrace: TimeInterval = 5 * 60

  struct Pending: Equatable {
    var event: CalendarEvent
    var fireDate: Date
  }

  /// The user's start-alert settings.
  struct Rules: Equatable {
    var style: StartAlertStyle
    var leadMinutes: Int
    var videoOnly: Bool
  }

  static func key(for event: CalendarEvent) -> String {
    "\(event.actionKey)@\(event.startDate.timeIntervalSince1970)"
  }

  static func next(
    events: [CalendarEvent],
    rules: Rules,
    handled: Set<String>,
    snoozed: [String: Date],
    now: Date
  ) -> Pending? {
    let lead = TimeInterval(max(0, rules.leadMinutes)) * 60
    return events
      .filter { event in
        !event.allDay
          && event.endDate > now
          && now < event.startDate.addingTimeInterval(lateGrace)
          && (!rules.videoOnly || !event.conferenceUrl.isEmpty)
      }
      .compactMap { event -> Pending? in
        let key = key(for: event)
        if let until = snoozed[key] {
          return Pending(event: event, fireDate: until)
        }
        guard !handled.contains(key) else { return nil }
        return Pending(event: event, fireDate: event.startDate.addingTimeInterval(-lead))
      }
      .min { $0.fireDate < $1.fireDate }
  }
}

/// Shows an on-screen alert as a meeting starts: a small floating card at the
/// top of the screen, or a full-screen takeover on every display. It stays
/// until the user joins, snoozes, or dismisses it.
@MainActor
final class StartAlertController {
  private var timer: Timer?
  private var handled: Set<String> = []
  private var snoozed: [String: Date] = [:]
  private var panels: [NSPanel] = []
  private var shownKey: String?
  private var lastEvents: [CalendarEvent] = []
  private var lastRules: StartAlertSchedule.Rules?

  var onJoin: (CalendarEvent) -> Void = { _ in }
  var onOpen: (CalendarEvent) -> Void = { _ in }

  func sync(events: [CalendarEvent], rules: StartAlertSchedule.Rules) {
    lastEvents = events
    lastRules = rules
    timer?.invalidate()
    timer = nil
    guard rules.style != .off else {
      close()
      return
    }
    // Keep the alert that's up; the next one waits until it's handled.
    guard shownKey == nil else { return }
    let now = Date()
    guard let pending = StartAlertSchedule.next(
      events: events,
      rules: rules,
      handled: handled,
      snoozed: snoozed,
      now: now
    ) else { return }
    if pending.fireDate <= now {
      show(pending.event, style: rules.style)
    } else {
      let timer = Timer(fire: pending.fireDate, interval: 0, repeats: false) { [weak self] _ in
        Task { @MainActor in self?.resync() }
      }
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    }
  }

  /// Previews the alert for the given event right away (Settings' test button).
  func preview(_ event: CalendarEvent, style: StartAlertStyle) {
    close()
    show(event, style: style == .off ? .floating : style, isPreview: true)
  }

  private func resync() {
    guard let lastRules else { return }
    sync(events: lastEvents, rules: lastRules)
  }

  private func show(_ event: CalendarEvent, style: StartAlertStyle, isPreview: Bool = false) {
    let key = StartAlertSchedule.key(for: event)
    if !isPreview {
      snoozed.removeValue(forKey: key)
      handled.insert(key)
    }
    shownKey = key
    let actions = StartAlertActions(
      join: { [weak self] in
        self?.onJoin(event)
        self?.finish()
      },
      snooze: { [weak self] in
        if !isPreview {
          self?.snoozed[key] = Date().addingTimeInterval(60)
        }
        self?.finish()
      },
      dismiss: { [weak self] in self?.finish() },
      open: { [weak self] in
        self?.onOpen(event)
        self?.finish()
      }
    )
    switch style {
    case .off:
      return
    case .floating:
      panels = [makeFloatingPanel(event: event, actions: actions)]
      panels.forEach { $0.orderFrontRegardless() }
    case .fullScreen:
      panels = NSScreen.screens.map { makeFullScreenPanel(event: event, actions: actions, screen: $0) }
      NSApp.activate(ignoringOtherApps: true)
      panels.forEach { $0.orderFrontRegardless() }
      // The main display's panel takes the keyboard so Return joins and
      // Escape dismisses.
      panels.first?.makeKey()
    }
  }

  private func finish() {
    close()
    resync()
  }

  private func close() {
    panels.forEach { $0.orderOut(nil) }
    panels = []
    shownKey = nil
  }

  private func makeFloatingPanel(event: CalendarEvent, actions: StartAlertActions) -> NSPanel {
    let size = NSSize(width: 380, height: 132)
    let screen = NSScreen.main ?? NSScreen.screens.first
    let visible = screen?.visibleFrame ?? .zero
    let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 10)
    let panel = StartAlertPanel(
      contentRect: NSRect(origin: origin, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .statusBar
    configure(panel)
    panel.contentView = NSHostingView(rootView: StartAlertView(event: event, style: .floating, actions: actions))
    return panel
  }

  private func makeFullScreenPanel(event: CalendarEvent, actions: StartAlertActions, screen: NSScreen) -> NSPanel {
    let panel = StartAlertPanel(
      contentRect: screen.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    // Above full-screen apps and the menubar, like a screen saver would be.
    panel.level = .screenSaver
    configure(panel)
    panel.setFrame(screen.frame, display: false)
    panel.contentView = NSHostingView(rootView: StartAlertView(event: event, style: .fullScreen, actions: actions))
    return panel
  }

  private func configure(_ panel: NSPanel) {
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
  }
}

/// A borderless panel that can still take the keyboard.
private final class StartAlertPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

struct StartAlertActions {
  var join: () -> Void
  var snooze: () -> Void
  var dismiss: () -> Void
  var open: () -> Void
}

struct StartAlertView: View {
  var event: CalendarEvent
  var style: StartAlertStyle
  var actions: StartAlertActions

  var body: some View {
    switch style {
    case .fullScreen:
      ZStack {
        Color.black.opacity(0.55)
          .ignoresSafeArea()
          .onTapGesture {}
        card
          .frame(width: 420)
          .padding(Theme.Spacing.xl)
          .background(
            Color(nsColor: .windowBackgroundColor),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
          )
          .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
      }
    default:
      card
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
          Color(nsColor: .windowBackgroundColor),
          in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08))
        )
        .padding(6)
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
    }
  }

  private var card: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let started = context.date >= event.startDate
      let tint: Color = started ? .green : .accentColor
      VStack(alignment: style == .fullScreen ? .center : .leading, spacing: Theme.Spacing.xs) {
        HStack(alignment: .firstTextBaseline) {
          Text(kicker(now: context.date))
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
          if style != .fullScreen {
            Spacer(minLength: Theme.Spacing.sm)
            Text(clock(event.startDate))
              .font(.caption.weight(.semibold))
              .monospacedDigit()
              .foregroundStyle(tint)
          }
        }
        Text(event.title)
          .font(.system(size: style == .fullScreen ? 22 : 15, weight: .bold))
          .lineLimit(2)
          .multilineTextAlignment(style == .fullScreen ? .center : .leading)
        if !detail.isEmpty {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        buttons(tint: tint)
          .padding(.top, Theme.Spacing.sm)
      }
      .frame(maxWidth: .infinity, alignment: style == .fullScreen ? .center : .leading)
    }
  }

  @ViewBuilder
  private func buttons(tint: Color) -> some View {
    let large = style == .fullScreen
    HStack(spacing: Theme.Spacing.sm) {
      if !event.conferenceUrl.isEmpty {
        Button(action: actions.join) {
          Label(loc("Join"), systemImage: "video.fill")
        }
        .buttonStyle(StartAlertButtonStyle(fill: tint, large: large))
        .keyboardShortcut(.defaultAction)
      } else {
        Button(loc("Open Event"), action: actions.open)
          .buttonStyle(StartAlertButtonStyle(fill: tint, large: large))
          .keyboardShortcut(.defaultAction)
      }
      Button(loc("Snooze 1 min"), action: actions.snooze)
        .buttonStyle(StartAlertButtonStyle(fill: nil, large: large))
      Button(loc("Dismiss"), action: actions.dismiss)
        .buttonStyle(StartAlertButtonStyle(fill: nil, large: large))
        .keyboardShortcut(.cancelAction)
    }
  }

  private func kicker(now: Date) -> String {
    if now >= event.startDate {
      return loc("Starting now")
    }
    return loc("Starts in %@", relativeWhen(max(1, roundedMinutes(from: now, to: event.startDate))))
  }

  private var detail: String {
    heroMetadataParts(for: event).joined(separator: " · ")
  }
}

/// The floating alert never becomes the key window, where system bordered
/// buttons lose their accent color, so the alert draws its own.
private struct StartAlertButtonStyle: ButtonStyle {
  var fill: Color?
  var large: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(large ? .body.weight(.semibold) : .callout.weight(.semibold))
      .foregroundStyle(fill == nil ? Color.primary : Color.white)
      .padding(.horizontal, large ? 18 : 12)
      .padding(.vertical, large ? 8 : 5)
      .background(
        (fill ?? Color.primary.opacity(0.08)).opacity(configuration.isPressed ? 0.75 : 1),
        in: RoundedRectangle(cornerRadius: large ? 9 : 7, style: .continuous)
      )
      .contentShape(Rectangle())
  }
}
