import Foundation
import XCTest
@testable import Nudge

final class LoopbackOAuthCallbackSessionTests: XCTestCase {
    @MainActor
    func testListenerUsesEphemeralLoopbackPortAndReturnsCallbackURL() async throws {
        let callbackSession = LoopbackOAuthCallbackSession()
        let redirectURL = try await callbackSession.start()
        defer {
            callbackSession.stop()
        }

        XCTAssertEqual(redirectURL.scheme, "http")
        XCTAssertEqual(redirectURL.host, "127.0.0.1")
        XCTAssertNotNil(redirectURL.port)
        XCTAssertTrue(redirectURL.path.isEmpty)

        async let receivedCallback = callbackSession.waitForCallback()
        var components = try XCTUnwrap(
            URLComponents(url: redirectURL, resolvingAgainstBaseURL: false)
        )
        components.queryItems = [
            URLQueryItem(name: "code", value: "authorization-code"),
            URLQueryItem(name: "state", value: "state-value"),
        ]
        let callbackURL = try XCTUnwrap(components.url)
        let (_, response) = try await URLSession.shared.data(from: callbackURL)
        let deliveredURL = try await receivedCallback

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(deliveredURL.scheme, callbackURL.scheme)
        XCTAssertEqual(deliveredURL.host, callbackURL.host)
        XCTAssertEqual(deliveredURL.port, callbackURL.port)
        XCTAssertTrue(deliveredURL.path.isEmpty || deliveredURL.path == "/")
        XCTAssertEqual(
            URLComponents(url: deliveredURL, resolvingAgainstBaseURL: false)?.query,
            URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.query
        )
    }
}
