import AppKit
import Foundation

enum EventLinks {
  enum MeetingProvider: CaseIterable {
    case googleMeet
    case zoom
    case teams
    case webex
    case blueJeans
    case goToMeeting
    case whereby
    case around
    case slackHuddle
    case discord
    case jitsi
    case eightByEight
    case faceTime
    case chime
    case gather
    case tuple
    case ringCentral
    case skype
    case dialpad
    case zohoMeeting
    case larkMeetings
    case tencentMeeting
    case livestorm
    case streamYard
    case riverside
    case pop
    case calVideo
    case liveKit
    case demio
    case huddle01
    case signal

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
      case .slackHuddle: return "Slack huddle"
      case .discord: return "Discord"
      case .jitsi: return "Jitsi Meet"
      case .eightByEight: return "8x8"
      case .faceTime: return "FaceTime"
      case .chime: return "Amazon Chime"
      case .gather: return "Gather"
      case .tuple: return "Tuple"
      case .ringCentral: return "RingCentral"
      case .skype: return "Skype"
      case .dialpad: return "Dialpad"
      case .zohoMeeting: return "Zoho Meeting"
      case .larkMeetings: return "Lark"
      case .tencentMeeting: return "Tencent Meeting"
      case .livestorm: return "Livestorm"
      case .streamYard: return "StreamYard"
      case .riverside: return "Riverside"
      case .pop: return "Pop"
      case .calVideo: return "Cal Video"
      case .liveKit: return "LiveKit Meet"
      case .demio: return "Demio"
      case .huddle01: return "Huddle01"
      case .signal: return "Signal"
      }
    }

    /// Domains whose links are calls, matched exactly or as a subdomain.
    /// Hosts that also serve ordinary pages (Slack, Discord, Cal.com,
    /// Signal) additionally need a call-shaped path; see `pathPrefixes`.
    fileprivate var domains: [String] {
      switch self {
      case .googleMeet: return ["meet.google.com"]
      case .zoom: return ["zoom.us", "zoom.com", "zoomgov.com"]
      case .teams: return ["teams.microsoft.com", "teams.live.com", "teams.microsoft.us"]
      case .webex: return ["webex.com"]
      case .blueJeans: return ["bluejeans.com"]
      case .goToMeeting: return ["gotomeeting.com", "goto.com", "gotomeet.me"]
      case .whereby: return ["whereby.com"]
      case .around: return ["around.co"]
      case .slackHuddle: return ["slack.com"]
      case .discord: return ["discord.gg", "discord.com"]
      case .jitsi: return ["meet.jit.si"]
      case .eightByEight: return ["8x8.vc"]
      case .faceTime: return ["facetime.apple.com"]
      case .chime: return ["chime.aws"]
      case .gather: return ["gather.town"]
      case .tuple: return ["tuple.app"]
      case .ringCentral: return ["meetings.ringcentral.com", "v.ringcentral.com", "video.ringcentral.com"]
      case .skype: return ["join.skype.com", "meet.lync.com"]
      case .dialpad: return ["meetings.dialpad.com"]
      case .zohoMeeting: return ["meeting.zoho.com", "meeting.zoho.eu", "meeting.zoho.in", "meeting.zoho.jp"]
      case .larkMeetings: return ["vc.larksuite.com", "vc.feishu.cn"]
      case .tencentMeeting: return ["meeting.tencent.com", "voovmeeting.com"]
      case .livestorm: return ["app.livestorm.co"]
      case .streamYard: return ["streamyard.com"]
      case .riverside: return ["riverside.fm"]
      case .pop: return ["pop.com"]
      case .calVideo: return ["app.cal.com"]
      case .liveKit: return ["meet.livekit.io"]
      case .demio: return ["demio.com"]
      case .huddle01: return ["huddle01.com"]
      case .signal: return ["signal.link"]
      }
    }

    /// For hosts that are mostly not calls, the path that marks a call link.
    fileprivate var pathPrefixes: [String]? {
      switch self {
      case .slackHuddle: return ["/huddle"]
      case .discord: return ["/channels", "/invite"]
      case .calVideo: return ["/video"]
      case .signal: return ["/call"]
      case .pop: return ["/j"]
      case .riverside: return ["/studio"]
      default: return nil
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
    guard !rawValue.isEmpty, let url = URL(string: rawValue), let host = url.host?.lowercased() else { return nil }
    return MeetingProvider.allCases.first { provider in
      guard provider.domains.contains(where: { matches(host, $0) }) else { return false }
      guard let prefixes = provider.pathPrefixes else { return true }
      // discord.gg invites are always calls; discord.com needs a channel path.
      if provider == .discord && host.hasSuffix("discord.gg") { return true }
      let path = url.path.lowercased()
      return prefixes.contains { path.hasPrefix($0) }
    }
  }

  /// The desktop-app form of a meeting link, for services whose apps register
  /// their own URL scheme. Nil when the link should just open as is.
  static func desktopAppURL(for url: URL) -> URL? {
    guard let host = url.host?.lowercased() else { return nil }
    switch meetingProvider(for: url.absoluteString) {
    case .zoom:
      return zoomAppURL(for: url, host: host)
    case .teams:
      return URL(string: url.absoluteString.replacingOccurrences(of: "https://", with: "msteams://"))
    default:
      return nil
    }
  }

  /// zoom.us/j/123?pwd=abc → zoommtg://zoom.us/join?action=join&confno=123&pwd=abc
  private static func zoomAppURL(for url: URL, host: String) -> URL? {
    let parts = url.path.split(separator: "/")
    guard parts.count >= 2, parts[0] == "j" || parts[0] == "w" else { return nil }
    var components = URLComponents()
    components.scheme = "zoommtg"
    components.host = host
    components.path = "/join"
    var items = [
      URLQueryItem(name: "action", value: "join"),
      URLQueryItem(name: "confno", value: String(parts[1]))
    ]
    if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "pwd" })?.value {
      items.append(URLQueryItem(name: "pwd", value: pwd))
    }
    components.queryItems = items
    return components.url
  }

  /// Opens a meeting link, in the service's desktop app when asked to and
  /// the app is installed; otherwise in the browser as before.
  @MainActor
  static func openMeeting(_ url: URL, preferDesktopApp: Bool) {
    if preferDesktopApp,
       let appURL = desktopAppURL(for: url),
       NSWorkspace.shared.urlForApplication(toOpen: appURL) != nil {
      NSWorkspace.shared.open(appURL)
      return
    }
    NSWorkspace.shared.open(url)
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
