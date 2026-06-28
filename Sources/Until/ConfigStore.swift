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
    guard let data = try? Data(contentsOf: fileURL) else {
      return .default
    }
    do {
      return try JSONDecoder().decode(AppConfig.self, from: data)
    } catch {
      return .default
    }
  }

  func save(_ config: AppConfig) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(config)
    try data.write(to: fileURL, options: .atomic)
  }
}
