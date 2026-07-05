import Foundation

/// Localization helpers for the `Until` executable target.
///
/// Localized resources (`en.lproj` / `ja.lproj` under `Sources/Until/Resources/`)
/// are auto-processed by SwiftPM and live in `Bundle.module`, NOT `Bundle.main`.
/// SwiftUI's `Text("...")` and `String(localized:)` default to the *main* bundle,
/// so every user-visible string must be routed through these helpers to resolve
/// against the module bundle. English strings double as the lookup keys.
///
/// English is the base/development language (`defaultLocalization: "en"` in
/// Package.swift); a missing key falls back to the key itself, i.e. the English
/// source string.

/// The module's localized resource bundle.
///
/// SwiftPM's generated `Bundle.module` accessor looks for `Until_Until.bundle`
/// next to `Bundle.main.bundleURL`, which — for a packaged `.app` — is the app
/// *root* (`Until.app/Until_Until.bundle`). Loose content at the app root is
/// not a valid, sealable bundle layout and trips codesign ("unsealed contents
/// present in the bundle root"), so `scripts/package-app.sh` instead copies the
/// bundle into the conventional, codesign-clean `Contents/Resources/`.
///
/// This resolver therefore prefers `Contents/Resources/Until_Until.bundle`, then
/// falls back to `Bundle.module` for the plain `swift build` / `swift test`
/// executable layout (bundle sits next to the binary and `Bundle.module`
/// resolves it directly). Exposed so tests can load a specific localization
/// (`en.lproj` / `ja.lproj`); reaching `Bundle.module` needs `@testable import`.
let localizationBundle: Bundle = {
  if let resourceURL = Bundle.main.resourceURL {
    let packaged = resourceURL.appendingPathComponent("Until_Until.bundle")
    if let bundle = Bundle(url: packaged) {
      return bundle
    }
  }
  return Bundle.module
}()

/// Look up a localized string by its English key.
func loc(_ key: String) -> String {
  localizationBundle.localizedString(forKey: key, value: key, table: nil)
}

/// Look up a localized format string and interpolate `args`.
///
/// The format string in the `.strings` file may reorder arguments with
/// positional specifiers (`%1$@`, `%2$d`, …) for natural word order in each
/// language, which is why formatting is centralized here.
func loc(_ key: String, _ args: CVarArg...) -> String {
  let format = localizationBundle.localizedString(forKey: key, value: key, table: nil)
  return String(format: format, locale: Locale.current, arguments: args)
}
