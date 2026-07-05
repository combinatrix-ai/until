import AppKit
import Foundation
import UserNotifications

@MainActor
final class EventNotifier: NSObject, UNUserNotificationCenterDelegate {
  private enum Backend {
    case native
    case script
  }

  /// Prefix for all per-event notification identifiers scheduled by the native
  /// backend. Used to scope reconciliation (fetching/removing pending requests)
  /// to notifications we own, without touching test notifications or snoozed
  /// copies (which carry their own "-snooze-" suffix but still start with this
  /// prefix so they're covered by delivered-set bookkeeping, not reconciliation
  /// removal — see `sync` for how snoozed copies are excluded from cleanup).
  private static let eventNotificationPrefix = "event-"

  private let backend: Backend

  /// Script backend only: fire-once timers, since osascript has no
  /// UNUserNotificationCenter to schedule against.
  private var scriptTimers: [String: Timer] = [:]

  /// Native backend only: identifiers we've already delivered immediately
  /// (trigger == nil) during this app session, so a later `sync()` call
  /// doesn't re-deliver the same "already inside the lead window" event
  /// every ~30 seconds.
  private var deliveredImmediately: Set<String> = []

  /// Native backend only: monotonic counter to keep repeated snoozes of the
  /// same notification unique.
  private static var snoozeCounter = 0

  override init() {
    if Bundle.main.bundleURL.pathExtension == "app" {
      backend = .native
    } else {
      backend = .script
    }
    super.init()

    if backend == .native {
      let open = UNNotificationAction(identifier: "open", title: loc("Open Event"), options: [.foreground])
      let snooze = UNNotificationAction(identifier: "snooze", title: loc("Snooze 5 min"), options: [])
      let eventCategory = UNNotificationCategory(
        identifier: "event-reminder",
        actions: [open, snooze],
        intentIdentifiers: []
      )
      let center = UNUserNotificationCenter.current()
      center.setNotificationCategories([
        eventCategory,
        Self.videoCategory(
          identifier: "event-reminder-video", title: loc("Open Video Call"), open: open, snooze: snooze
        ),
        Self.videoCategory(
          identifier: "event-reminder-meet", title: loc("Open Google Meet"), open: open, snooze: snooze
        ),
        Self.videoCategory(identifier: "event-reminder-zoom", title: loc("Open Zoom"), open: open, snooze: snooze),
        Self.videoCategory(identifier: "event-reminder-teams", title: loc("Open Teams"), open: open, snooze: snooze),
        Self.videoCategory(identifier: "event-reminder-webex", title: loc("Open Webex"), open: open, snooze: snooze)
      ])
      center.delegate = self
    }
  }

  private static func videoCategory(
    identifier: String,
    title: String,
    open: UNNotificationAction,
    snooze: UNNotificationAction
  ) -> UNNotificationCategory {
    let join = UNNotificationAction(identifier: "join", title: title, options: [.foreground])
    return UNNotificationCategory(
      identifier: identifier,
      actions: [join, open, snooze],
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
          userInfo: [NSLocalizedDescriptionKey: loc("Notifications are not authorized for Until.")]
        )
      }
      try await deliverNativeTest()
    case .script:
      try deliverScriptTest()
    }
  }

  func sync(events: [CalendarEvent], leadMinutes: Int, enabled: Bool) async {
    switch backend {
    case .native:
      await syncNative(events: events, leadMinutes: leadMinutes, enabled: enabled)
    case .script:
      syncScript(events: events, leadMinutes: leadMinutes, enabled: enabled)
    }
  }

  // MARK: - Native backend (UNCalendarNotificationTrigger)

  /// A notification that should be outstanding right now for `event`: its
  /// scheduling `identifier` and the `fireDate` it should trigger at.
  private struct DesiredNotification {
    var event: CalendarEvent
    var identifier: String
    var fireDate: Date
  }

  /// Builds the identifier for an event notification. Encodes the event and
  /// its start time (and lead minutes) so a rescheduled event, or a changed
  /// lead time, naturally produces a new identifier rather than colliding
  /// with a stale pending/delivered one.
  private func nativeIdentifier(for event: CalendarEvent, leadMinutes: Int) -> String {
    "\(Self.eventNotificationPrefix)\(event.account.email)-\(event.id)-" +
      "\(event.startDate.timeIntervalSince1970)-lead\(leadMinutes)"
  }

  private func syncNative(events: [CalendarEvent], leadMinutes: Int, enabled: Bool) async {
    let center = UNUserNotificationCenter.current()

    guard enabled else {
      let pending = await center.pendingNotificationRequests()
      let ours = pending
        .map(\.identifier)
        .filter { $0.hasPrefix(Self.eventNotificationPrefix) }
      if !ours.isEmpty {
        center.removePendingNotificationRequests(withIdentifiers: ours)
      }
      deliveredImmediately.removeAll()
      return
    }

    await requestAuthorization()

    let now = Date()
    let lead = TimeInterval(max(0, leadMinutes) * 60)

    // One entry for every event that should have a reminder outstanding
    // right now.
    var desired: [DesiredNotification] = []
    for event in events where !event.allDay && event.startDate > now {
      let id = nativeIdentifier(for: event, leadMinutes: leadMinutes)
      let fireDate = event.startDate.addingTimeInterval(-lead)
      desired.append(DesiredNotification(event: event, identifier: id, fireDate: fireDate))
    }
    let desiredIds = Set(desired.map(\.identifier))

    // Reconciliation: drop any pending request we own that's no longer
    // desired (event removed/filtered out, rescheduled, or lead changed —
    // in which case its old identifier simply isn't in `desiredIds`).
    // Snoozed copies carry a "-snooze-" suffix and are intentionally left
    // alone here; they're one-shot and should fire regardless of the
    // current sync's desired set.
    let pending = await center.pendingNotificationRequests()
    let pendingIds = Set(pending.map(\.identifier))
    let staleOwned = pendingIds.filter {
      $0.hasPrefix(Self.eventNotificationPrefix) && !$0.contains("-snooze-") && !desiredIds.contains($0)
    }
    if !staleOwned.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: Array(staleOwned))
    }

    // Drop delivered-set entries that are no longer desired, so the set
    // doesn't grow unboundedly across a long-running session.
    deliveredImmediately.formIntersection(desiredIds)

    for item in desired {
      // Already pending (system will fire it) or already delivered this
      // session: skip, so we never reset/replace/re-deliver.
      if pendingIds.contains(item.identifier) || deliveredImmediately.contains(item.identifier) {
        continue
      }

      let content = nativeContent(for: item.event)

      if item.fireDate > now {
        let components = Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute, .second],
          from: item.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
        try? await center.add(request)
      } else {
        // Already inside the lead window: deliver once, immediately.
        let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: nil)
        try? await center.add(request)
        deliveredImmediately.insert(item.identifier)
      }
    }
  }

  private func nativeContent(for event: CalendarEvent) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = event.title
    content.body = notificationBody(for: event)
    content.sound = .default
    content.categoryIdentifier = notificationCategoryIdentifier(for: event)
    content.userInfo = [
      "eventURL": EventLinks.eventURLString(for: event),
      "joinURL": EventLinks.conferenceURLString(for: event)
    ]
    return content
  }

  private func deliverNativeTest() async throws {
    let content = UNMutableNotificationContent()
    content.title = loc("Test Notification")
    content.body = loc("Until notifications are working.")
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

  // MARK: - Script backend (osascript, dev/non-.app runs)

  private func syncScript(events: [CalendarEvent], leadMinutes: Int, enabled: Bool) {
    for timer in scriptTimers.values {
      timer.invalidate()
    }
    scriptTimers.removeAll()
    guard enabled else { return }

    let now = Date()
    let lead = TimeInterval(max(0, leadMinutes) * 60)
    for event in events where !event.allDay && event.startDate > now {
      let fireDate = max(event.startDate.addingTimeInterval(-lead), now.addingTimeInterval(1))
      let id = "\(event.account.email)-\(event.id)"
      let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
        Task { @MainActor in
          self?.deliverScript(event)
          self?.scriptTimers[id] = nil
        }
      }
      scriptTimers[id] = timer
      RunLoop.main.add(timer, forMode: .common)
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
    let body = appleScriptString(loc("Until notifications are working."))
    let title = appleScriptString(loc("Test Notification"))
    let script = """
    display notification \(body) with title \(title) sound name "default"
    """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    try process.run()
  }

  // MARK: - Shared content helpers

  private static let shortTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()

  private func notificationBody(for event: CalendarEvent) -> String {
    let when = loc("Starts at %@", Self.shortTimeFormatter.string(from: event.startDate))
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
    if response.actionIdentifier == "snooze" {
      let original = response.notification.request
      let snoozed = UNMutableNotificationContent()
      let originalContent = original.content
      snoozed.title = originalContent.title
      snoozed.body = originalContent.body
      snoozed.sound = originalContent.sound
      snoozed.categoryIdentifier = originalContent.categoryIdentifier
      snoozed.userInfo = originalContent.userInfo

      let identifier = await MainActor.run { () -> String in
        Self.snoozeCounter += 1
        return "\(original.identifier)-snooze-\(Self.snoozeCounter)"
      }

      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)
      let request = UNNotificationRequest(identifier: identifier, content: snoozed, trigger: trigger)
      try? await UNUserNotificationCenter.current().add(request)
      return
    }

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
