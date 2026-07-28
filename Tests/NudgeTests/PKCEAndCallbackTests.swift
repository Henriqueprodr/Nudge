import Foundation
import XCTest
@testable import Nudge

final class PKCEAndCallbackTests: XCTestCase {
    func testPKCEChallengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

        XCTAssertEqual(
            PKCEGenerator.challenge(for: verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testGeneratedPKCEVerifierAndStateAreURLSafeAndHighEntropy() throws {
        let pair = try PKCEGenerator.generate()
        let state = try PKCEGenerator.randomState()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

        XCTAssertTrue((43...128).contains(pair.verifier.count))
        XCTAssertFalse(pair.challenge.contains("="))
        XCTAssertFalse(state.isEmpty)
        XCTAssertNil(pair.verifier.unicodeScalars.first { !allowed.contains($0) })
        XCTAssertNil(state.unicodeScalars.first { !allowed.contains($0) })
    }

    func testCallbackValidationRequiresMatchingLoopbackEndpointAndState() throws {
        let redirectURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:54321")
        )
        let callbackURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:54321/?code=code-value&state=state-value")
        )
        let validator = OAuthCallbackValidator()

        XCTAssertEqual(
            try validator.authorizationCode(
                from: callbackURL,
                expectedState: "state-value",
                redirectURL: redirectURL
            ),
            "code-value"
        )
        XCTAssertThrowsError(
            try validator.authorizationCode(
                from: callbackURL,
                expectedState: "different-state",
                redirectURL: redirectURL
            )
        ) { error in
            XCTAssertEqual(error as? GoogleOAuthError, .invalidAuthorizationCallback)
        }
    }

    func testCallbackDenialIsReportedWithoutAcceptingAnAuthorizationCode() throws {
        let redirectURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:54321")
        )
        let callbackURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:54321/?error=access_denied&state=state-value")
        )

        XCTAssertThrowsError(
            try OAuthCallbackValidator().authorizationCode(
                from: callbackURL,
                expectedState: "state-value",
                redirectURL: redirectURL
            )
        ) { error in
            XCTAssertEqual(error as? GoogleOAuthError, .authorizationDenied)
        }
    }

    func testAuthorizationURLUsesFullScopeUnionPKCEAndOfflineAccess() throws {
        let configuration = GoogleOAuthConfiguration(clientID: "desktop-client-id")
        let url = try configuration.authorizationURL(
            redirectURL: URL(string: "http://127.0.0.1:54321")!,
            codeChallenge: "challenge",
            state: "state"
        )
        let values = Dictionary(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map {
                ($0.name, $0.value ?? "")
            } ?? [],
            uniquingKeysWith: { first, _ in first }
        )

        XCTAssertEqual(
            Set((values["scope"] ?? "").split(separator: " ").map(String.init)),
            GoogleOAuthConfiguration.requiredScopeUnion
        )
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["access_type"], "offline")
        XCTAssertEqual(values["prompt"], "consent")
        XCTAssertEqual(values["response_type"], "code")
    }
}
