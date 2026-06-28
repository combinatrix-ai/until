import Foundation
import Security

struct StoredToken: Codable, Hashable {
  var email: String
  var accessToken: String
  var refreshToken: String
  var expiryDate: Date
  var tokenType: String
}

enum KeychainStore {
  private static let service = "app.until"
  private static let account = "google-oauth"

  static func loadTokens() -> [StoredToken] {
    guard let data = readData(service: service) else {
      return []
    }
    return ((try? JSONDecoder().decode([StoredToken].self, from: data)) ?? [])
      .filter { token in
        !token.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && !token.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
  }

  private static func readData(service: String) -> Data? {
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
}
