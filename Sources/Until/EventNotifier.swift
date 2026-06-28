import AppKit
import Foundation
import UserNotifications

@MainActor
final class EventNotifier: NSObject, UNUserNotificationCenterDelegate {
  private enum Backend {
    case native
    case script
  }

  private let backend: Backend
  private var timers: [String: Timer] = [:]

  override init() {
    if Bundle.main.bundleURL.pathExtension == "app" {
      backend = .native
    } else {
      backend = .script
    }
    super.init()

    if backend == .native {
      let open = UNNotificationAction(identifier: "open", title: "Open Event", options: [.foreground])
      let eventCategory = UNNotificationCategory(
        identifier: "event-reminder",
        actions: [open],
        intentIdentifiers: []
      )
      let center = UNUserNotificationCenter.current()
      center.setNotificationCategories([
        eventCategory,
        Self.videoCategory(identifier: "event-reminder-video", title: "Open Video Call", open: open),
        Self.videoCategory(identifier: "event-reminder-meet", title: "Open Google Meet", open: open),
        Self.videoCategory(identifier: "event-reminder-zoom", title: "Open Zoom", open: open),
        Self.videoCategory(identifier: "event-reminder-teams", title: "Open Teams", open: open),
        Self.videoCategory(identifier: "event-reminder-webex", title: "Open Webex", open: open)
      ])
      center.delegate = self
    }
  }

  private static func videoCategory(
    identifier: String,
    title: String,
    open: UNNotificationAction
  ) -> UNNotificationCategory {
    let join = UNNotificationAction(identifier: "join", title: title, options: [.foreground])
    return UNNotificationCategory(
      identifier: identifier,
      actions: [join, open],
      intentIdentifiers: []
    )
  }

  @discardableResult
  func requestAuthorization() async -> Bool {
    guard backend == .native else { return true }
    return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
  }

  func authorizationState() async -> NotificationAuthorizationState {
    guard backend == .native else { return .unavailable }
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .notDetermined:
      return .notDetermined
    case .denied:
      return .denied
    case .authorized:
      return .authorized
    case .provisional:
      return .provisional
    @unknown default:
      return .unknown
    }
  }

  func sendTestNotification() async throws {
    switch backend {
    case .native:
      let authorized = await requestAuthorization()
      guard authorized else {
        throw NSError(
          domain: "Until.Notifications",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Notifications are not authorized for Until."]
        )
      }
      try await deliverNativeTest()
    case .script:
      try deliverScriptTest()
    }
  }

  func sync(events: [CalendarEvent], leadMinutes: Int, enabled: Bool) async {
    for timer in timers.values {
      timer.invalidate()
    }
    timers.removeAll()
    guard enabled else { return }

    if backend == .native {
      await requestAuthorization()
    }

    let now = Date()
    let lead = TimeInterval(max(0, leadMinutes) * 60)
    for event in events where !event.allDay && event.startDate > now {
      let fireDate = max(event.startDate.addingTimeInterval(-lead), now.addingTimeInterval(1))
      let id = "\(event.account.email)-\(event.id)"
      let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
        Task { @MainActor in
          self?.deliver(event, identifier: id)
          self?.timers[id] = nil
        }
      }
      timers[id] = timer
      RunLoop.main.add(timer, forMode: .common)
    }
  }

  private func deliver(_ event: CalendarEvent, identifier: String) {
    switch backend {
    case .native:
      deliverNative(event, identifier: identifier)
    case .script:
      deliverScript(event)
    }
  }

  private func deliverNative(_ event: CalendarEvent, identifier: String) {
    let content = UNMutableNotificationContent()
    content.title = event.title
    content.body = notificationBody(for: event)
    content.sound = .default
    content.categoryIdentifier = notificationCategoryIdentifier(for: event)
    content.userInfo = [
      "eventURL": EventLinks.eventURLString(for: event),
      "joinURL": EventLinks.conferenceURLString(for: event)
    ]

    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  private func deliverNativeTest() async throws {
    let content = UNMutableNotificationContent()
    content.title = "Test Notification"
    content.body = "Until notifications are working."
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "test-\(UUID().uuidString)",
      content: content,
      trigger: nil
    )

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      UNUserNotificationCenter.current().add(request) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func deliverScript(_ event: CalendarEvent) {
    let body = appleScriptString(notificationBody(for: event))
    let title = appleScriptString(event.title)
    let script = """
    display notification \(body) with title \(title) sound name "default"
    """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    try? process.run()
  }

  private func deliverScriptTest() throws {
    let script = """
    display notification "Until notifications are working." with title "Test Notification" sound name "default"
    """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    try process.run()
  }

  private func notificationBody(for event: CalendarEvent) -> String {
    let mins = max(0, Int(event.startDate.timeIntervalSince(Date()) / 60))
    let when = mins == 0 ? "Starting now" : "Starts in \(mins) min"
    let provider = EventLinks.meetingProvider(for: event)?.label ?? ""
    return [when, provider, event.location].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  private func notificationCategoryIdentifier(for event: CalendarEvent) -> String {
    switch EventLinks.meetingProvider(for: event) {
    case .googleMeet:
      return "event-reminder-meet"
    case .zoom:
      return "event-reminder-zoom"
    case .teams:
      return "event-reminder-teams"
    case .webex:
      return "event-reminder-webex"
    case .blueJeans, .goToMeeting, .whereby, .around:
      return "event-reminder-video"
    case nil:
      return "event-reminder"
    }
  }

  private func appleScriptString(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo
    let preferredURL: String?
    switch response.actionIdentifier {
    case "join":
      preferredURL = userInfo["joinURL"] as? String
    case "open":
      preferredURL = userInfo["eventURL"] as? String
    case UNNotificationDefaultActionIdentifier:
      preferredURL = (userInfo["joinURL"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        ?? (userInfo["eventURL"] as? String)
    default:
      preferredURL = userInfo["eventURL"] as? String
    }

    guard let urlString = preferredURL,
          !urlString.isEmpty,
          let url = URL(string: urlString)
    else { return }

    _ = await MainActor.run {
      NSWorkspace.shared.open(url)
    }
  }
}
