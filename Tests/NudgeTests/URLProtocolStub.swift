import Foundation

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?

        func setHandler(_ handler: Handler?) {
            lock.lock()
            self.handler = handler
            lock.unlock()
        }

        func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
            lock.lock()
            let handler = self.handler
            lock.unlock()
            guard let handler else {
                throw URLError(.badServerResponse)
            }
            return try handler(request)
        }
    }

    private static let storage = Storage()

    static func setHandler(_ handler: Handler?) {
        storage.setHandler(handler)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try Self.storage.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
