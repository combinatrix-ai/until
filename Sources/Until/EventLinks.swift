import Foundation

enum EventLinks {
  enum MeetingProvider {
    case googleMeet
    case zoom
    case teams
    case webex
    case blueJeans
    case goToMeeting
    case whereby
    case around

    var label: String {
      switch self {
      case .googleMeet: return "Google Meet"
      case .zoom: return "Zoom"
      case .teams: return "Microsoft Teams"
      case .webex: return "Webex"
      case .blueJeans: return "BlueJeans"
      case .goToMeeting: return "GoTo Meeting"
      case .whereby: return "Whereby"
      case .around: return "Around"
      }
    }
  }

  static func eventURL(for event: CalendarEvent) -> URL? {
    authenticatedGoogleURL(
      from: event.htmlLink.isEmpty ? event.conferenceUrl : event.htmlLink,
      accountEmail: event.account.email
    )
  }

  static func conferenceURL(for event: CalendarEvent) -> URL? {
    authenticatedGoogleURL(from: event.conferenceUrl, accountEmail: event.account.email)
  }

  static func eventURLString(for event: CalendarEvent) -> String {
    eventURL(for: event)?.absoluteString ?? ""
  }

  static func conferenceURLString(for event: CalendarEvent) -> String {
    conferenceURL(for: event)?.absoluteString ?? ""
  }

  static func authenticatedURL(from rawValue: String, accountEmail: String) -> URL? {
    authenticatedGoogleURL(from: rawValue, accountEmail: accountEmail)
  }

  static func meetingProvider(for event: CalendarEvent) -> MeetingProvider? {
    meetingProvider(for: event.conferenceUrl)
  }

  static func meetingProvider(for rawValue: String) -> MeetingProvider? {
    guard !rawValue.isEmpty, let host = URL(string: rawValue)?.host?.lowercased() else { return nil }
    if host == "meet.google.com" { return .googleMeet }
    if matches(host, "zoom.us") { return .zoom }
    if matches(host, "teams.microsoft.com") { return .teams }
    if matches(host, "webex.com") { return .webex }
    if matches(host, "bluejeans.com") { return .blueJeans }
    if matches(host, "gotomeeting.com") || matches(host, "goto.com") { return .goToMeeting }
    if matches(host, "whereby.com") { return .whereby }
    if matches(host, "around.co") { return .around }
    return nil
  }

  /// True when `host` is exactly `domain` or a subdomain of it (`*.domain`).
  private static func matches(_ host: String, _ domain: String) -> Bool {
    host == domain || host.hasSuffix("." + domain)
  }

  private static func authenticatedGoogleURL(from rawValue: String, accountEmail: String) -> URL? {
    guard !rawValue.isEmpty, let url = URL(string: rawValue) else { return nil }
    guard isGoogleURL(url), !accountEmail.isEmpty else { return url }
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    var queryItems = components?.queryItems ?? []
    queryItems.removeAll { $0.name == "authuser" }
    queryItems.append(URLQueryItem(name: "authuser", value: accountEmail))
    components?.queryItems = queryItems
    return components?.url ?? url
  }

  private static func isGoogleURL(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return host == "google.com"
      || host.hasSuffix(".google.com")
      || host == "google.co.jp"
      || host.hasSuffix(".google.co.jp")
      || host == "meet.google.com"
  }
}
