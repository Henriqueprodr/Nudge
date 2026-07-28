@preconcurrency import Network
import Foundation

@MainActor
final class LoopbackOAuthCallbackSession: OAuthCallbackSession {
    nonisolated private static let maximumRequestLength = 16_384

    private let queue = DispatchQueue(label: "com.local.Nudge.google-oauth-callback")
    private var listener: NWListener?
    private var redirectURL: URL?
    private var pendingCallbackURL: URL?
    private var startContinuation: CheckedContinuation<URL, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?

    func start() async throws -> URL {
        guard listener == nil else {
            throw GoogleOAuthError.callbackListenerFailed
        }

        let listener: NWListener
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(.loopback),
                port: .any
            )
            parameters.acceptLocalOnly = true
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            throw GoogleOAuthError.callbackListenerFailed
        }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let listener else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handleListenerState(state, listener: listener)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.accept(connection)
            }
        }
        listener.start(queue: queue)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(with: .cancelled)
            }
        }
    }

    func waitForCallback() async throws -> URL {
        if let pendingCallbackURL {
            self.pendingCallbackURL = nil
            return pendingCallbackURL
        }
        guard listener != nil, redirectURL != nil, callbackContinuation == nil else {
            throw GoogleOAuthError.callbackListenerFailed
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                callbackContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(with: .cancelled)
            }
        }
    }

    func stop() {
        finish(with: .cancelled)
    }

    private func handleListenerState(_ state: NWListener.State, listener: NWListener) {
        switch state {
        case .ready:
            guard let port = listener.port else {
                finish(with: .callbackListenerFailed)
                return
            }
            var components = URLComponents()
            components.scheme = "http"
            components.host = "127.0.0.1"
            components.port = Int(port.rawValue)
            guard let redirectURL = components.url else {
                finish(with: .callbackListenerFailed)
                return
            }
            self.redirectURL = redirectURL
            startContinuation?.resume(returning: redirectURL)
            startContinuation = nil
        case .failed:
            finish(with: .callbackListenerFailed)
        case .cancelled:
            finish(with: .cancelled)
        case .setup, .waiting:
            break
        @unknown default:
            finish(with: .callbackListenerFailed)
        }
    }

    private func accept(_ connection: NWConnection) {
        guard let redirectURL else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: Self.maximumRequestLength
        ) { [weak self] data, _, _, _ in
            let callbackURL = data.flatMap {
                Self.callbackURL(from: $0, redirectURL: redirectURL)
            }
            let isExpectedPath = callbackURL.map { Self.isRootPath($0.path) } == true
            let response = Self.httpResponse(success: isExpectedPath)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
            guard let callbackURL, isExpectedPath else {
                return
            }
            Task { @MainActor [weak self] in
                self?.received(callbackURL)
            }
        }
    }

    private func received(_ callbackURL: URL) {
        if let callbackContinuation {
            self.callbackContinuation = nil
            callbackContinuation.resume(returning: callbackURL)
        } else {
            pendingCallbackURL = callbackURL
        }
    }

    private func finish(with error: GoogleOAuthError) {
        listener?.cancel()
        listener = nil
        redirectURL = nil
        pendingCallbackURL = nil
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        callbackContinuation?.resume(throwing: error)
        callbackContinuation = nil
    }

    nonisolated private static func callbackURL(
        from requestData: Data,
        redirectURL: URL
    ) -> URL? {
        guard
            let request = String(data: requestData, encoding: .utf8),
            let firstLine = request.components(separatedBy: "\r\n").first
        else {
            return nil
        }
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "GET" else {
            return nil
        }
        return URL(string: String(parts[1]), relativeTo: redirectURL)?.absoluteURL
    }

    nonisolated private static func isRootPath(_ path: String) -> Bool {
        path.isEmpty || path == "/"
    }

    nonisolated private static func httpResponse(success: Bool) -> Data {
        let status = success ? "200 OK" : "404 Not Found"
        let message = success
            ? "Nudge received the Google sign-in response. You can close this window."
            : "Nudge is waiting for the Google sign-in response."
        let body = "<html><body><p>\(message)</p></body></html>"
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        return Data(response.utf8)
    }
}
