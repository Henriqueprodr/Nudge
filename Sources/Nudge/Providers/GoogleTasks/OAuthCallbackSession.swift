import Foundation

@MainActor
protocol OAuthCallbackSession: AnyObject {
    func start() async throws -> URL
    func waitForCallback() async throws -> URL
    func stop()
}
