import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let model: AppModel
  private var statusController: StatusBarController?

  init(options: AppRuntimeOptions = .fromProcess()) {
    model = AppModel(options: options)
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusController = StatusBarController(model: model)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    statusController?.showSettings()
    return false
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
  private let model: AppModel
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()
  private var cancellables = Set<AnyCancellable>()
  private var settingsWindow: NSWindow?
  private var hotkeyManager: HotkeyManager?
  /// When true the menubar shows only the icon, hiding the event text. Toggled by
  /// right-clicking the status item; in-memory only (resets on relaunch).
  private var collapsed = false

  init(model: AppModel) {
    self.model = model
    super.init()
    hotkeyManager = HotkeyManager { [weak self] in
      self?.hotkeyToggle()
    }
    popover.behavior = .transient
    popover.delegate = self
    popover.contentSize = NSSize(width: 390, height: 520)
    popover.contentViewController = NSHostingController(rootView: PanelView(model: model, openSettings: { [weak self] in
      self?.showSettings()
    }))

    if let button = item.button {
      button.image = BrandIcon.menubarImage()
      button.image?.accessibilityDescription = "Until"
      button.action = #selector(togglePopover(_:))
      button.target = self
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    model.$state.combineLatest(model.$config).sink { [weak self] state, config in
      self?.updateStatus(state: state, config: config)
    }.store(in: &cancellables)
    model.$config
      .map { ($0.hotkeyEnabled, $0.hotkeyPreset) }
      .removeDuplicates { $0 == $1 }
      .sink { [weak self] enabled, preset in
        self?.applyHotkey(enabled: enabled, preset: preset)
      }
      .store(in: &cancellables)
  }

  private func applyHotkey(enabled: Bool, preset: String) {
    if enabled {
      hotkeyManager?.register(presetId: preset)
    } else {
      hotkeyManager?.unregister()
    }
  }

  @objc private func togglePopover(_ sender: NSStatusBarButton) {
    // Right-click hides/reveals the event text, leaving just the icon — a quick
    // way to reclaim menubar width when the next event's title runs long.
    if NSApp.currentEvent?.type == .rightMouseUp {
      collapsed.toggle()
      updateStatus(state: model.state, config: model.config)
      return
    }
    // ⌥-click joins the meeting shown in the menubar instead of opening the
    // popover. If it has no conference URL, shake the icon rather than silently
    // opening a different meeting or the popover.
    if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
      if !model.joinMenubarMeeting() { shakeStatusItem() }
      return
    }
    togglePopover(relativeTo: sender)
  }

  /// A quick left-right shake of the status item — feedback for an ⌥-click when
  /// the shown meeting has nothing to join.
  private func shakeStatusItem() {
    guard let button = item.button else { return }
    button.wantsLayer = true
    guard let layer = button.layer else { return }
    let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
    shake.values = [0, -4, 4, -3, 3, -2, 2, 0]
    shake.keyTimes = [0, 0.14, 0.28, 0.42, 0.56, 0.70, 0.85, 1]
    shake.duration = 0.42
    shake.isAdditive = true
    layer.add(shake, forKey: "shake")
  }

  private func togglePopover(relativeTo sender: NSStatusBarButton) {
    if popover.isShown {
      popover.performClose(sender)
    } else {
      popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  /// Toggle the popover from a source other than a mouse click (global hotkey),
  /// activating the app so the popover receives key focus.
  private func hotkeyToggle() {
    guard let button = item.button else { return }
    NSApp.activate(ignoringOtherApps: true)
    togglePopover(relativeTo: button)
  }

  nonisolated func popoverDidClose(_ notification: Notification) {
    Task { @MainActor in
      model.collapseEventDetails()
    }
  }

  private func updateStatus(state: AppState, config: AppConfig) {
    guard let button = item.button else { return }
    let now = Date()
    if let next = state.next {
      let title = next.title.count > config.maxTitleLength
        ? String(next.title.prefix(max(1, config.maxTitleLength - 1))) + "…"
        : next.title
      let when: String
      if next.allDay {
        when = loc("all-day")
      } else if next.startDate <= now && next.endDate > now {
        // Event already underway: show time remaining instead of "now".
        let remaining = max(0, Int((next.endDate.timeIntervalSince(now) / 60).rounded()))
        when = loc("%@ left", relativeWhen(remaining))
      } else {
        when = relativeWhen(next.startMinutesFromNow)
      }
      button.title = " \(when) \(title)"
    } else if state.auth.authenticated && state.events.isEmpty && state.allDayEvents.isEmpty && state.lastError == nil {
      button.title = " " + loc("No events")
    } else {
      button.title = ""
    }
    // Collapsed: drop the text, keep just the icon (dimmed so it reads as
    // "hidden" rather than "no events"). The tooltip below still reflects the
    // next event, so hovering reveals it without un-collapsing.
    if collapsed {
      button.title = ""
    }
    button.appearsDisabled = collapsed
    button.toolTip = state.lastError
      ?? state.next.map { tooltip(for: $0, state: state, now: now) }
      ?? (
        state.auth.authenticated && state.events.isEmpty && state.allDayEvents.isEmpty
          ? loc("No events to show")
          : loc("No current or imminent events")
      )
  }

  /// Tooltip for the shown event, with a count of other timed events still to
  /// come today appended when there are any.
  private func tooltip(for event: CalendarEvent, state: AppState, now: Date) -> String {
    let base = event.allDay
      ? loc("%@ - all-day", event.title)
      : loc("%1$@ - %2$@", event.title, clock(event.startDate))
    let calendar = Calendar.current
    let moreToday = state.events.filter { other in
      other.startDate > now
        && calendar.isDateInToday(other.startDate)
        && other.actionKey != event.actionKey
    }.count
    return moreToday > 0 ? loc("%1$@ (%2$d more today)", base, moreToday) : base
  }

  func showSettings() {
    if let settingsWindow {
      settingsWindow.center()
      settingsWindow.makeKeyAndOrderFront(nil)
      clearInitialTextFocus(in: settingsWindow)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let controller = NSHostingController(rootView: SettingsView(model: model))
    let window = NSWindow(contentViewController: controller)
    window.title = loc("Until Settings")
    window.setContentSize(NSSize(width: 780, height: 640))
    window.contentMinSize = NSSize(width: 720, height: 480)
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.isReleasedWhenClosed = false
    settingsWindow = window
    window.center()
    window.makeKeyAndOrderFront(nil)
    clearInitialTextFocus(in: window)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func clearInitialTextFocus(in window: NSWindow) {
    DispatchQueue.main.async {
      window.makeFirstResponder(nil)
    }
  }
}

func relativeWhen(_ minutes: Int) -> String {
  if minutes <= 0 { return loc("now") }
  if minutes < 60 { return "\(minutes)m" }
  let hours = minutes / 60
  let mins = minutes % 60
  return mins == 0 ? "\(hours)h" : "\(hours)h\(mins)m"
}

// Cached formatters: `clock` runs per visible row on every render, so a fresh
// `DateFormatter` per call is measurable overhead. Hoisted to file scope.
private let clockFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.timeStyle = .short
  formatter.dateStyle = .none
  return formatter
}()

private let dayHeaderFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
  return formatter
}()

func clock(_ date: Date) -> String {
  clockFormatter.string(from: date)
}

/// Width of the time column in the event list, measured from the widest string
/// that can actually appear there in the current locale (a 12-hour "10:00 PM"
/// is far wider than a 24-hour "22:00", and the all-day label shares the same
/// column). Sizing to the real content avoids a fixed width that leaves dead
/// space between the time and the event title in 24-hour locales.
func clockColumnWidth() -> CGFloat {
  let font = NSFont.monospacedSystemFont(
    ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize,
    weight: .regular)
  // A morning and an evening time so the widest AM/PM form is covered, plus the
  // all-day label which renders in the same column.
  var candidates = [loc("all-day")]
  var components = DateComponents()
  components.year = 2000; components.month = 1; components.day = 1; components.minute = 0
  for hour in [10, 22] {
    components.hour = hour
    if let date = Calendar.current.date(from: components) {
      candidates.append(clock(date))
    }
  }
  let widest = candidates
    .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
    .max() ?? 0
  return ceil(widest) + Theme.Spacing.xs
}

func dayHeader(_ day: Date, now: Date = Date()) -> String {
  let calendar = Calendar.current
  if calendar.isDate(day, inSameDayAs: now) { return loc("Today") }
  if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
     calendar.isDate(day, inSameDayAs: tomorrow) {
    return loc("Tomorrow")
  }
  return dayHeaderFormatter.string(from: day)
}
