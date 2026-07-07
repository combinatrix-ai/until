import Foundation
import Security

struct StoredToken: Codable, Hashable {
  var email: String
  var accessToken: String
  var refreshToken: String
  var expiryDate: Date
  var tokenType: String
  /// Scopes Google reported as granted for this token. Existing keychain
  /// entries predate this field, so decoding must tolerate its absence — a nil
  /// value means "unknown" and is treated as "all scopes granted" until the
  /// next login/refresh populates it.
  var grantedScopes: [String]?

  init(
    email: String,
    accessToken: String,
    refreshToken: String,
    expiryDate: Date,
    tokenType: String,
    grantedScopes: [String]? = nil
  ) {
    self.email = email
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiryDate = expiryDate
    self.tokenType = tokenType
    self.grantedScopes = grantedScopes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    email = try container.decode(String.self, forKey: .email)
    accessToken = try container.decode(String.self, forKey: .accessToken)
    refreshToken = try container.decode(String.self, forKey: .refreshToken)
    expiryDate = try container.decode(Date.self, forKey: .expiryDate)
    tokenType = try container.decode(String.self, forKey: .tokenType)
    grantedScopes = try container.decodeIfPresent([String].self, forKey: .grantedScopes)
  }
}

enum KeychainStore {
  private static let service = "ai.combinatrix.until"
  private static let account = "google-oauth"
  private static let clientSecretAccount = "oauth-client-secret"

  static func loadTokens() -> [StoredToken] {
    guard let data = readData(service: service, account: account) else {
      return []
    }
    return ((try? JSONDecoder().decode([StoredToken].self, from: data)) ?? [])
      .filter { token in
        !token.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && !token.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
  }

  private static func readData(service: String, account: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else { return nil }
    return item as? Data
  }

  static func saveTokens(_ tokens: [StoredToken]) throws {
    let tokens = tokens.filter { token in
      !token.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !token.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !tokens.isEmpty else {
      deleteAll()
      return
    }

    let data = try JSONEncoder().encode(tokens)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    let attributes: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecSuccess { return }

    var add = query
    add[kSecValueData as String] = data
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    if addStatus != errSecSuccess {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
    }
  }

  static func upsert(_ token: StoredToken) throws {
    var tokens = loadTokens().filter { $0.email.caseInsensitiveCompare(token.email) != .orderedSame }
    tokens.append(token)
    try saveTokens(tokens.sorted { $0.email < $1.email })
  }

  static func remove(email: String? = nil) throws {
    if let email {
      let tokens = loadTokens().filter { $0.email.caseInsensitiveCompare(email) != .orderedSame }
      try saveTokens(tokens)
      return
    }
    deleteAll()
  }

  private static func deleteAll() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
  }

  // MARK: - OAuth client secret (generic string entry)

  /// Reads the OAuth client secret from the Keychain, or nil if none is stored.
  static func loadClientSecret() -> String? {
    guard let data = readData(service: service, account: clientSecretAccount),
          let value = String(data: data, encoding: .utf8),
          !value.isEmpty
    else { return nil }
    return value
  }

  /// Upserts the OAuth client secret. An empty value deletes the entry.
  static func saveClientSecret(_ value: String) throws {
    guard !value.isEmpty else {
      deleteClientSecret()
      return
    }
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: clientSecretAccount
    ]
    let attributes: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecSuccess { return }

    var add = query
    add[kSecValueData as String] = data
    let addStatus = SecItemAdd(add as CFDictionary, nil)
    if addStatus != errSecSuccess {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
    }
  }

  static func deleteClientSecret() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: clientSecretAccount
    ]
    SecItemDelete(query as CFDictionary)
  }
}
