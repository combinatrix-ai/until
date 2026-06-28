import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let model = AppModel()
  private var statusController: StatusBarController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusController = StatusBarController(model: model)
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

  init(model: AppModel) {
    self.model = model
    super.init()
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
  }

  @objc private func togglePopover(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showMenu()
      return
    }
    if popover.isShown {
      popover.performClose(sender)
    } else {
      popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  nonisolated func popoverDidClose(_ notification: Notification) {
    Task { @MainActor in
      model.collapseEventDetails()
    }
  }

  private func showMenu() {
    let menu = NSMenu()
    menu.addItem(withTitle: "Refresh Now", action: #selector(refresh), keyEquivalent: "")
    menu.addItem(withTitle: "Preferences...", action: #selector(showSettingsAction), keyEquivalent: ",")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
    menu.items.forEach { $0.target = self }
    item.menu = menu
    item.button?.performClick(nil)
    item.menu = nil
  }

  private func updateStatus(state: AppState, config: AppConfig) {
    guard let button = item.button else { return }
    if let next = state.next {
      let title = next.title.count > config.maxTitleLength
        ? String(next.title.prefix(max(1, config.maxTitleLength - 1))) + "..."
        : next.title
      let when = next.allDay ? "all-day" : relativeWhen(next.startMinutesFromNow)
      button.title = " \(when) \(title)"
    } else if state.auth.authenticated && state.events.isEmpty && state.allDayEvents.isEmpty && state.lastError == nil {
      button.title = " No events"
    } else {
      button.title = ""
    }
    button.toolTip = state.lastError
      ?? state.next.map { $0.allDay ? "\($0.title) - all-day" : "\($0.title) - \(clock($0.startDate))" }
      ?? (
        state.auth.authenticated && state.events.isEmpty && state.allDayEvents.isEmpty
          ? "No events to show"
          : "No current or imminent events"
      )
  }

  @objc private func refresh() {
    Task { await model.refresh() }
  }

  @objc private func showSettingsAction() {
    showSettings()
  }

  private func showSettings() {
    if let settingsWindow {
      settingsWindow.center()
      settingsWindow.makeKeyAndOrderFront(nil)
      clearInitialTextFocus(in: settingsWindow)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let controller = NSHostingController(rootView: SettingsView(model: model))
    let window = NSWindow(contentViewController: controller)
    window.title = "Until Settings"
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

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}

func relativeWhen(_ minutes: Int) -> String {
  if minutes <= 0 { return "now" }
  if minutes < 60 { return "\(minutes)m" }
  let hours = minutes / 60
  let mins = minutes % 60
  return mins == 0 ? "\(hours)h" : "\(hours)h\(mins)m"
}

func clock(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.timeStyle = .short
  formatter.dateStyle = .none
  return formatter.string(from: date)
}

func dayHeader(_ day: Date, now: Date = Date()) -> String {
  let calendar = Calendar.current
  if calendar.isDate(day, inSameDayAs: now) { return "Today" }
  if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
     calendar.isDate(day, inSameDayAs: tomorrow) {
    return "Tomorrow"
  }
  let formatter = DateFormatter()
  formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
  return formatter.string(from: day)
}
