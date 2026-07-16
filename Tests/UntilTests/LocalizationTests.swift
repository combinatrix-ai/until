import XCTest
@testable import Until

/// Proves the Japanese localization is actually compiled into the module
/// resource bundle (`Until_Until.bundle`) and resolves at runtime. This runs
/// under plain `swift test`, guarding against the `.lproj` resources silently
/// dropping out of the build (e.g. a missing `defaultLocalization`, a renamed
/// Resources directory, or a packaging regression).
final class LocalizationTests: XCTestCase {
  /// Loads the `ja.lproj` bundle nested inside the module resource bundle and
  /// asserts known keys resolve to their expected Japanese strings.
  func testJapaneseStringsResolveFromModuleBundle() throws {
    let jaBundle = try XCTUnwrap(
      localizationBundle.url(forResource: "ja", withExtension: "lproj").flatMap(Bundle.init(url:)),
      "ja.lproj is missing from the module resource bundle"
    )

    let cases: [(key: String, expected: String)] = [
      ("Sign in with Google", "Googleでサインイン"),
      ("Refresh interval", "更新間隔"),
      ("Quit Until?", "Untilを終了しますか?"),
      ("all-day", "終日"),
      ("now", "今"),
      ("Launch at login", "ログイン時に起動"),
      ("Skip in menubar", "メニューバーでスキップ")
    ]

    for testCase in cases {
      let value = jaBundle.localizedString(forKey: testCase.key, value: nil, table: nil)
      XCTAssertEqual(
        value, testCase.expected,
        "Japanese lookup for \"\(testCase.key)\" resolved to \"\(value)\""
      )
    }
  }

  /// A format string with positional specifiers must survive into the ja
  /// bundle so word order can be reordered per language.
  func testJapaneseFormatStringResolves() throws {
    let jaBundle = try XCTUnwrap(
      localizationBundle.url(forResource: "ja", withExtension: "lproj").flatMap(Bundle.init(url:))
    )
    let format = jaBundle.localizedString(forKey: "%1$d of %2$d events match", value: nil, table: nil)
    let rendered = String(format: format, locale: Locale(identifier: "ja"), 3, 10)
    XCTAssertEqual(rendered, "10件中3件が一致")
  }

  /// The English base bundle exists and maps keys back to their source text.
  func testEnglishBaseBundlePresent() throws {
    let enBundle = try XCTUnwrap(
      localizationBundle.url(forResource: "en", withExtension: "lproj").flatMap(Bundle.init(url:)),
      "en.lproj is missing from the module resource bundle"
    )
    XCTAssertEqual(
      enBundle.localizedString(forKey: "Sign in with Google", value: nil, table: nil),
      "Sign in with Google"
    )
  }
}
