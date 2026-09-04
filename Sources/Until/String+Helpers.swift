import Foundation

extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }

  var emailDomain: String? {
    split(separator: "@").last.map {
      String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
  }
}
