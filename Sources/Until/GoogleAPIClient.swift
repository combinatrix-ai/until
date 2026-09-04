import Foundation

/// Shared authenticated JSON transport for Google APIs. Callers retain their
/// existing error prefixes and empty-response policy while request assembly,
/// status validation, and decoding stay consistent.
struct GoogleAPIClient {
  private let auth: GoogleAuth

  init(auth: GoogleAuth) {
    self.auth = auth
  }

  var accountEmail: String {
    get async { await auth.email }
  }

  func request<T: Decodable>(
    _ url: URL,
    method: String = "GET",
    body: [String: Any]? = nil,
    errorPrefix: String,
    emptyBodyAsObject: Bool = false
  ) async throws -> T {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? "unknown error"
      throw AppError.message("\(errorPrefix): \(message)")
    }
    let responseData = data.isEmpty && emptyBodyAsObject ? Data("{}".utf8) : data
    return try JSONDecoder.google.decode(T.self, from: responseData)
  }
}

extension URL {
  func appending(queryItems: [URLQueryItem]) -> URL {
    var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
    components.queryItems = (components.queryItems ?? []) + queryItems
    return components.url!
  }
}
