import AppKit
import CryptoKit
import Darwin
import Foundation

private let googleScopes = [
  "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
  "https://www.googleapis.com/auth/calendar.events",
  "https://www.googleapis.com/auth/drive.file",
  "https://www.googleapis.com/auth/userinfo.email",
  "openid"
]

@MainActor
final class GoogleAuth: Identifiable {
  let id = UUID()
  private var config: AppConfig
  private(set) var token: StoredToken?

  var email: String { token?.email ?? "" }
  var isAuthenticated: Bool { token?.refreshToken.isEmpty == false }

  init(config: AppConfig, token: StoredToken? = nil) {
    self.config = config
    self.token = token
  }

  func configure(_ config: AppConfig) {
    self.config = config
  }

  func login(loginHint: String? = nil, expectedEmail: String? = nil) async throws {
    let clientId = config.oauthClientId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientId.isEmpty else {
      throw AppError.message(loc("Google OAuth Client ID is not configured."))
    }

    let loopback = try await LoopbackServer.start()
    let redirectURI = "http://127.0.0.1:\(loopback.port)"
    let verifier = PKCE.makeVerifier()
    let challenge = PKCE.challenge(for: verifier)

    var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    var queryItems = [
      URLQueryItem(name: "client_id", value: clientId),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: googleScopes.joined(separator: " ")),
      URLQueryItem(name: "access_type", value: "offline"),
      URLQueryItem(name: "prompt", value: "consent select_account"),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256")
    ]
    if let loginHint = loginHint?.trimmingCharacters(in: .whitespacesAndNewlines), !loginHint.isEmpty {
      queryItems.append(URLQueryItem(name: "login_hint", value: loginHint))
    }
    components.queryItems = queryItems
    guard let authURL = components.url else {
      throw AppError.message(loc("Failed to build Google sign-in URL."))
    }

    try openAuthURL(authURL)
    let code = try await loopback.waitForCode()
    let exchanged = try await exchangeCode(code: code, verifier: verifier, redirectURI: redirectURI)
    let email = try await fetchEmail(accessToken: exchanged.accessToken)
    if let expectedEmail = expectedEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
       !expectedEmail.isEmpty,
       email.caseInsensitiveCompare(expectedEmail) != .orderedSame {
      throw AppError.message(loc("Selected Google account %1$@ does not match %2$@.", email, expectedEmail))
    }
    guard !exchanged.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      let key = "Google did not return a refresh token. Try removing access for Until from your Google " +
        "Account, then sign in again."
      throw AppError.message(loc(key))
    }
    let stored = StoredToken(
      email: email,
      accessToken: exchanged.accessToken,
      refreshToken: exchanged.refreshToken,
      expiryDate: Date().addingTimeInterval(TimeInterval(exchanged.expiresIn)),
      tokenType: exchanged.tokenType
    )
    try KeychainStore.upsert(stored)
    token = stored
  }

  func revokeAndLogout() async throws {
    let stored = token
    token = nil
    if let email = stored?.email {
      try KeychainStore.remove(email: email)
    }
    if let tokenToRevoke = firstNonEmptyToken(stored?.refreshToken, stored?.accessToken) {
      try? await revoke(token: tokenToRevoke)
    }
  }

  func accessToken() async throws -> String {
    guard var token else {
      throw AppError.message(loc("Not authenticated."))
    }
    if token.expiryDate.timeIntervalSinceNow > 60 {
      return token.accessToken
    }

    let refreshed = try await refresh(refreshToken: token.refreshToken)
    token.accessToken = refreshed.accessToken
    token.expiryDate = Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
    token.tokenType = refreshed.tokenType
    try KeychainStore.upsert(token)
    self.token = token
    return token.accessToken
  }

  private func exchangeCode(code: String, verifier: String, redirectURI: String) async throws -> TokenResponse {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var items = [
      URLQueryItem(name: "client_id", value: config.oauthClientId.trimmingCharacters(in: .whitespacesAndNewlines)),
      URLQueryItem(name: "code", value: code),
      URLQueryItem(name: "code_verifier", value: verifier),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "grant_type", value: "authorization_code")
    ]
    let clientSecret = config.oauthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    if !clientSecret.isEmpty {
      items.append(URLQueryItem(name: "client_secret", value: clientSecret))
    }
    request.httpBody = formBody(items)
    return try await runTokenRequest(request)
  }

  private func refresh(refreshToken: String) async throws -> TokenResponse {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var items = [
      URLQueryItem(name: "client_id", value: config.oauthClientId.trimmingCharacters(in: .whitespacesAndNewlines)),
      URLQueryItem(name: "refresh_token", value: refreshToken),
      URLQueryItem(name: "grant_type", value: "refresh_token")
    ]
    let clientSecret = config.oauthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    if !clientSecret.isEmpty {
      items.append(URLQueryItem(name: "client_secret", value: clientSecret))
    }
    request.httpBody = formBody(items)
    var response = try await runTokenRequest(request)
    response.refreshToken = refreshToken
    return response
  }

  private func revoke(token: String) async throws {
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = formBody([URLQueryItem(name: "token", value: token)])
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw AppError.message(loc("Failed to revoke Google credentials."))
    }
  }

  private func runTokenRequest(_ request: URLRequest) async throws -> TokenResponse {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "unknown error"
      throw AppError.message("Google OAuth failed: \(body)")
    }
    return try JSONDecoder.google.decode(TokenResponse.self, from: data)
  }

  private func fetchEmail(accessToken: String) async throws -> String {
    var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw AppError.message(loc("Failed to fetch Google account email."))
    }
    let user = try JSONDecoder().decode(UserInfo.self, from: data)
    return user.email
  }

  private func openAuthURL(_ url: URL) throws {
    if NSWorkspace.shared.open(url) {
      return
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.absoluteString]
    do {
      try process.run()
    } catch {
      throw AppError.message(loc("Failed to open browser for Google sign-in: %@", error.localizedDescription))
    }
  }
}

private struct UserInfo: Decodable {
  var email: String
}

private struct TokenResponse: Decodable {
  var accessToken: String
  var expiresIn: Int
  var refreshToken: String
  var tokenType: String

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case expiresIn = "expires_in"
    case refreshToken = "refresh_token"
    case tokenType = "token_type"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    accessToken = try container.decode(String.self, forKey: .accessToken)
    expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn) ?? 3600
    refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
    tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType) ?? "Bearer"
  }
}

private func formBody(_ items: [URLQueryItem]) -> Data {
  var components = URLComponents()
  components.queryItems = items
  return Data((components.percentEncodedQuery ?? "").utf8)
}

private func firstNonEmptyToken(_ values: String?...) -> String? {
  values
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
    .first { !$0.isEmpty }
}

private enum PKCE {
  static func makeVerifier() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return base64URL(Data(bytes))
  }

  static func challenge(for verifier: String) -> String {
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return base64URL(Data(digest))
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

private final class LoopbackServer {
  let port: UInt16
  private let socketFD: Int32
  private var source: DispatchSourceRead?
  private var continuation: CheckedContinuation<String, Error>?

  private init(socketFD: Int32, port: UInt16) {
    self.socketFD = socketFD
    self.port = port
  }

  static func start() async throws -> LoopbackServer {
    let socketFD = try makeSocket()
    try bindLoopback(socketFD: socketFD)
    try listenOnSocket(socketFD)
    let port = try assignedPort(socketFD: socketFD)

    let server = LoopbackServer(socketFD: socketFD, port: port)
    let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: .main)
    source.setEventHandler { [weak server] in
      server?.acceptConnection()
    }
    source.setCancelHandler {
      close(socketFD)
    }
    server.source = source
    source.resume()
    return server
  }

  private static func makeSocket() throws -> Int32 {
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    guard socketFD >= 0 else {
      throw POSIXError(.init(rawValue: errno) ?? .EINVAL)
    }
    var yes: Int32 = 1
    setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
    return socketFD
  }

  private static func bindLoopback(socketFD: Int32) throws {
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(0).bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &addr) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0 else {
      let error = POSIXError(.init(rawValue: errno) ?? .EINVAL)
      close(socketFD)
      throw error
    }
  }

  private static func listenOnSocket(_ socketFD: Int32) throws {
    guard listen(socketFD, 4) == 0 else {
      let error = POSIXError(.init(rawValue: errno) ?? .EINVAL)
      close(socketFD)
      throw error
    }
  }

  private static func assignedPort(socketFD: Int32) throws -> UInt16 {
    var actual = sockaddr_in()
    var actualLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &actual) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        getsockname(socketFD, sockaddrPointer, &actualLength)
      }
    }
    guard nameResult == 0 else {
      let error = POSIXError(.init(rawValue: errno) ?? .EINVAL)
      close(socketFD)
      throw error
    }

    let port = UInt16(bigEndian: actual.sin_port)
    guard port != 0 else {
      close(socketFD)
      throw AppError.message(loc("Failed to allocate loopback port."))
    }
    return port
  }

  func waitForCode() async throws -> String {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
      }
    } onCancel: {
      Task { @MainActor in
        self.stop()
      }
    }
  }

  private func acceptConnection() {
    var clientAddress = sockaddr()
    var clientAddressLength = socklen_t(MemoryLayout<sockaddr>.size)
    let clientFD = accept(socketFD, &clientAddress, &clientAddressLength)
    guard clientFD >= 0 else {
      // Ignore accept failures on a single connection; keep listening.
      // Task cancellation (via waitForCode's cancellation handler) remains
      // the escape hatch if the server needs to be torn down.
      return
    }
    handle(clientFD: clientFD)
  }

  /// Result of parsing the raw HTTP request line for the OAuth redirect's
  /// `code`/`error` query parameters.
  private struct RedirectParams {
    var code: String?
    var error: String?

    var isRedirect: Bool { code != nil || error != nil }
  }

  private func handle(clientFD: Int32) {
    defer {
      close(clientFD)
    }

    var buffer = [UInt8](repeating: 0, count: 8192)
    let count = recv(clientFD, &buffer, buffer.count, 0)
    guard count > 0 else {
      // Speculative/preconnect connections send no bytes. Just close and
      // keep the server running for the real redirect.
      return
    }

    let request = String(bytes: buffer.prefix(count), encoding: .utf8) ?? ""
    let params = parseRedirectParams(from: request)

    guard params.isRedirect else {
      // Not the OAuth redirect (e.g. /favicon.ico or another stray request).
      // Respond minimally and keep listening for the real redirect.
      sendResponse(notFoundResponse(), to: clientFD)
      return
    }

    sendResponse(landingPageResponse(for: params), to: clientFD)

    if let authError = params.error {
      finish(.failure(AppError.message(authError)))
    } else if let code = params.code {
      finish(.success(code))
    }
    stop()
  }

  private func parseRedirectParams(from request: String) -> RedirectParams {
    let firstLine = request.components(separatedBy: "\r\n").first ?? ""
    let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
    let components = URLComponents(string: "http://127.0.0.1\(path)")
    let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
    let authError = components?.queryItems?.first(where: { $0.name == "error" })?.value
    return RedirectParams(code: code, error: authError)
  }

  private func notFoundResponse() -> Data {
    let response = """
    HTTP/1.1 404 Not Found\r
    Content-Length: 0\r
    Connection: close\r
    \r

    """
    return Data(response.utf8)
  }

  private func landingPageResponse(for params: RedirectParams) -> Data {
    let success = params.error == nil && params.code != nil
    let title = success ? loc("You can close this tab") : loc("Login failed")
    let detail = success ? loc("Return to Until.") : (params.error ?? loc("No authorization code returned."))
    let body = """
    <html><body style="font-family:-apple-system,sans-serif;padding:40px;text-align:center">
    <h2>\(title)</h2><p>\(detail)</p></body></html>
    """
    let response = """
    HTTP/1.1 200 OK\r
    Content-Type: text/html; charset=utf-8\r
    Content-Length: \(Data(body.utf8).count)\r
    Connection: close\r
    \r
    \(body)
    """
    return Data(response.utf8)
  }

  private func sendResponse(_ data: Data, to clientFD: Int32) {
    data.withUnsafeBytes { bytes in
      if let baseAddress = bytes.baseAddress {
        _ = send(clientFD, baseAddress, data.count, 0)
      }
    }
  }

  private func finish(_ result: Result<String, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    switch result {
    case .success(let code):
      continuation.resume(returning: code)
    case .failure(let error):
      continuation.resume(throwing: error)
    }
  }

  private func stop() {
    source?.cancel()
    source = nil
  }
}

enum AppError: LocalizedError {
  case message(String)

  var errorDescription: String? {
    switch self {
    case .message(let message): return message
    }
  }
}

extension JSONDecoder {
  static let google: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
