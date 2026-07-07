import XCTest
@testable import Until

final class GrantedScopesTests: XCTestCase {
  // MARK: - parseGrantedScopes

  func testParseSpaceSeparatedScopes() {
    let scopes = parseGrantedScopes(
      "openid https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/drive.file"
    )
    XCTAssertEqual(scopes, [
      "openid",
      "https://www.googleapis.com/auth/calendar.events",
      "https://www.googleapis.com/auth/drive.file"
    ])
  }

  func testParseCollapsesRepeatedAndSurroundingWhitespace() {
    let scopes = parseGrantedScopes("  openid   \t email\n ")
    XCTAssertEqual(scopes, ["openid", "email"])
  }

  func testParseNilIsEmpty() {
    XCTAssertTrue(parseGrantedScopes(nil).isEmpty)
  }

  func testParseEmptyStringIsEmpty() {
    XCTAssertTrue(parseGrantedScopes("").isEmpty)
  }

  // MARK: - hasScope semantics

  @MainActor
  func testHasScopeGranted() {
    let auth = makeAuth(grantedScopes: [
      "openid",
      driveFileScope
    ])
    XCTAssertTrue(auth.hasScope(driveFileScope))
  }

  @MainActor
  func testHasScopeNotGranted() {
    let auth = makeAuth(grantedScopes: ["openid"])
    XCTAssertFalse(auth.hasScope(driveFileScope))
  }

  @MainActor
  func testHasScopeUnknownEmptyTreatedAsGranted() {
    // Empty list = "unknown" (existing user re-decode) → assume granted.
    let auth = makeAuth(grantedScopes: [])
    XCTAssertTrue(auth.hasScope(driveFileScope))
  }

  @MainActor
  func testHasScopeUnknownNilTreatedAsGranted() {
    let auth = makeAuth(grantedScopes: nil)
    XCTAssertTrue(auth.hasScope(driveFileScope))
  }

  @MainActor
  private func makeAuth(grantedScopes: [String]?) -> GoogleAuth {
    let token = StoredToken(
      email: "user@example.com",
      accessToken: "at",
      refreshToken: "rt",
      expiryDate: Date().addingTimeInterval(3600),
      tokenType: "Bearer",
      grantedScopes: grantedScopes
    )
    return GoogleAuth(config: AppConfig.default, token: token)
  }

  // MARK: - Insufficient-scope error detection

  func testDetectsInsufficientPermissions() {
    let body = #"{"error":{"code":403,"errors":[{"reason":"insufficientPermissions"}]}}"#
    XCTAssertTrue(isInsufficientScopeError("Google API failed: \(body)"))
  }

  func testDetectsAccessTokenScopeInsufficient() {
    let body = #"{"error_description":"ACCESS_TOKEN_SCOPE_INSUFFICIENT"}"#
    XCTAssertTrue(isInsufficientScopeError(body))
  }

  func testDoesNotMatchUnrelatedError() {
    XCTAssertFalse(isInsufficientScopeError("Google API failed: {\"error\":\"notFound\"}"))
    XCTAssertFalse(isInsufficientScopeError("The network connection was lost."))
  }
}

final class StoredTokenDecodingTests: XCTestCase {
  private func decode(_ json: String) throws -> StoredToken {
    try JSONDecoder().decode(StoredToken.self, from: Data(json.utf8))
  }

  /// Existing keychain entries predate `grantedScopes`; decoding must succeed
  /// with the field absent and leave it nil (→ "unknown" → assume granted).
  func testDecodeWithoutGrantedScopes() throws {
    let json = """
    {
      "email": "user@example.com",
      "accessToken": "at",
      "refreshToken": "rt",
      "expiryDate": 0,
      "tokenType": "Bearer"
    }
    """
    let token = try decode(json)
    XCTAssertEqual(token.email, "user@example.com")
    XCTAssertNil(token.grantedScopes)
  }

  func testDecodeWithGrantedScopes() throws {
    let json = """
    {
      "email": "user@example.com",
      "accessToken": "at",
      "refreshToken": "rt",
      "expiryDate": 0,
      "tokenType": "Bearer",
      "grantedScopes": ["openid", "https://www.googleapis.com/auth/drive.file"]
    }
    """
    let token = try decode(json)
    XCTAssertEqual(token.grantedScopes, ["openid", "https://www.googleapis.com/auth/drive.file"])
  }

  /// A token encoded by the current code round-trips back to the same value,
  /// including the scopes.
  func testRoundTripPreservesGrantedScopes() throws {
    let original = StoredToken(
      email: "user@example.com",
      accessToken: "at",
      refreshToken: "rt",
      expiryDate: Date(timeIntervalSinceReferenceDate: 123),
      tokenType: "Bearer",
      grantedScopes: [driveFileScope]
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(StoredToken.self, from: data)
    XCTAssertEqual(decoded, original)
  }
}
