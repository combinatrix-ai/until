import Foundation

struct ConfigStore {
  private let fileURL: URL

  init() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let directory = support.appendingPathComponent("Until", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    fileURL = directory.appendingPathComponent("config.json")
  }

  func load() -> AppConfig {
    var config: AppConfig
    if let data = try? Data(contentsOf: fileURL),
       let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
      config = decoded
    } else {
      config = .default
    }
    resolveClientSecret(&config)
    return config
  }

  func save(_ config: AppConfig) throws {
    persistClientSecret(config)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(config)
    try data.write(to: fileURL, options: .atomic)
  }

  // MARK: - OAuth client secret resolution

  /// Resolves the in-memory `oauthClientSecret` with precedence:
  /// (1) build-time injected secret, (2) Keychain value, (3) legacy value still
  /// present in config.json (old installs). When a legacy secret is found and
  /// the Keychain has none, it's migrated into the Keychain; it then disappears
  /// from config.json automatically on the next save (encode no longer writes it).
  private func resolveClientSecret(_ config: inout AppConfig) {
    let buildTime = AppConfig.bundledGoogleClientSecret
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if !buildTime.isEmpty {
      config.oauthClientSecret = buildTime
      return
    }

    if let keychain = KeychainStore.loadClientSecret() {
      config.oauthClientSecret = keychain
      return
    }

    // Legacy value carried in via config.json decode: migrate to Keychain.
    let legacy = config.oauthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    if !legacy.isEmpty {
      try? KeychainStore.saveClientSecret(legacy)
      config.oauthClientSecret = legacy
    }
  }

  /// On save, persist a non-build-time secret to the Keychain. Build-time
  /// secrets are never written (they always win at load time), and empty
  /// secrets are left as-is so we don't clobber a stored value.
  private func persistClientSecret(_ config: AppConfig) {
    let buildTime = AppConfig.bundledGoogleClientSecret
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard buildTime.isEmpty else { return }
    let secret = config.oauthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !secret.isEmpty else { return }
    try? KeychainStore.saveClientSecret(secret)
  }
}
