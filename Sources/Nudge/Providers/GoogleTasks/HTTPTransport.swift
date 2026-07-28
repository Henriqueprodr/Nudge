import Foundation

enum HTTPTransportError: Error {
    case invalidResponse
}

@MainActor
protocol HTTPTransport: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

@MainActor
final class URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPTransportError.invalidResponse
        }
        return (data, httpResponse)
    }
}
