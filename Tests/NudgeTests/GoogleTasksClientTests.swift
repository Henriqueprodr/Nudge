import Foundation
import XCTest
@testable import Nudge

final class GoogleTasksClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.setHandler(nil)
        super.tearDown()
    }

    @MainActor
    func testPaginationDecodingReadOnlyParametersAndDateOnlyMapping() async throws {
        let recorder = RequestRecorder()
        URLProtocolStub.setHandler { request in
            recorder.record(request)
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(
                URLComponents(url: url, resolvingAgainstBaseURL: false)
            )
            let pageToken = components.queryItems?.first(where: { $0.name == "pageToken" })?.value
            let body: String

            switch (url.path, pageToken) {
            case ("/tasks/v1/users/@me/lists", nil):
                body = """
                {
                  "nextPageToken": "lists-page-2",
                  "items": [{"id":"list-a","title":"Inbox"}]
                }
                """
            case ("/tasks/v1/users/@me/lists", "lists-page-2"):
                body = """
                {"items":[{"id":"list-b","title":"Work"}]}
                """
            case ("/tasks/v1/lists/list-a/tasks", nil):
                body = """
                {
                  "nextPageToken": "tasks-page-2",
                  "items": [
                    {
                      "id":"task-1",
                      "title":"Date-only task",
                      "notes":"Keep cached",
                      "status":"needsAction",
                      "due":"2026-07-21T23:59:59.000Z",
                      "webViewLink":"https://tasks.google.com/task/task-1"
                    },
                    {"id":"completed","title":"Done","status":"completed"}
                  ]
                }
                """
            case ("/tasks/v1/lists/list-a/tasks", "tasks-page-2"):
                body = """
                {"items":[{"id":"task-2","title":"Second task","status":"needsAction"}]}
                """
            case ("/tasks/v1/lists/list-b/tasks", nil):
                body = "{\"items\":[] }"
            default:
                throw URLError(.badURL)
            }

            return (
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(body.utf8)
            )
        }

        let client = makeClient()
        let snapshot = try await client.fetchIncompleteTasks(accessToken: "secret-access-token")

        XCTAssertEqual(
            snapshot.taskLists,
            [TaskList(id: "list-a", title: "Inbox"), TaskList(id: "list-b", title: "Work")]
        )
        XCTAssertEqual(snapshot.tasks.map(\.id), ["task-1", "task-2"])
        XCTAssertEqual(
            snapshot.tasks.first?.dueDate,
            TaskItem.DueDate(year: 2026, month: 7, day: 21)
        )
        XCTAssertNil(snapshot.tasks.first?.localTimeOverride)
        XCTAssertEqual(
            snapshot.tasks.first?.webViewURL,
            URL(string: "https://tasks.google.com/task/task-1")
        )

        let requests = recorder.requests
        XCTAssertEqual(requests.count, 5)
        XCTAssertTrue(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret-access-token"
        })
        let taskRequest = try XCTUnwrap(
            requests.first { $0.url?.path == "/tasks/v1/lists/list-a/tasks" }
        )
        let taskQuery = Dictionary(
            URLComponents(url: taskRequest.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .map { ($0.name, $0.value ?? "") } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        XCTAssertEqual(taskQuery["showCompleted"], "false")
        XCTAssertEqual(taskQuery["showDeleted"], "false")
        XCTAssertEqual(taskQuery["showHidden"], "false")
        XCTAssertEqual(taskQuery["maxResults"], "100")
    }

    @MainActor
    func testCompletionUsesAuthenticatedPatchWithEncodedIdentifiers() async throws {
        let transport = MutationRecordingTransport()

        try await GoogleTasksClient(transport: transport).completeTask(
            taskListID: "list/one",
            taskID: "task two",
            accessToken: "mutation-token"
        )

        let request = try XCTUnwrap(transport.request)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.percentEncodedPath,
            "/tasks/v1/lists/list%2Fone/tasks/task%20two"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer mutation-token"
        )
        let body = try XCTUnwrap(request.httpBody)
        let values = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        XCTAssertEqual(values, ["status": "completed"])
    }

    @MainActor
    func testHTTPAuthenticationAndRetryableStatusErrorsAreTyped() async throws {
        let statusCodes = [401, 429, 503]
        for statusCode in statusCodes {
            URLProtocolStub.setHandler { request in
                let url = request.url!
                return (
                    HTTPURLResponse(
                        url: url,
                        statusCode: statusCode,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data()
                )
            }

            do {
                _ = try await makeClient().fetchIncompleteTasks(accessToken: "token")
                XCTFail("Expected HTTP failure")
            } catch {
                if statusCode == 401 {
                    XCTAssertEqual(error as? GoogleTasksError, .authenticationRequired)
                } else {
                    let typedError = try XCTUnwrap(error as? GoogleTasksError)
                    XCTAssertEqual(typedError, .httpStatus(statusCode))
                    XCTAssertTrue(typedError.isRetryable)
                }
            }
        }
    }

    @MainActor
    func testPartialPaginationFailureDoesNotReturnAPartialSnapshot() async {
        URLProtocolStub.setHandler { request in
            let url = request.url!
            let pageToken = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "pageToken" })?
                .value
            if pageToken == nil {
                return (
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data(
                        "{\"nextPageToken\":\"second-page\",\"items\":[{\"id\":\"list-a\",\"title\":\"Inbox\"}]}".utf8
                    )
                )
            }
            return (
                HTTPURLResponse(
                    url: url,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        do {
            _ = try await makeClient().fetchIncompleteTasks(accessToken: "token")
            XCTFail("Expected the second page to fail")
        } catch {
            XCTAssertEqual(error as? GoogleTasksError, .httpStatus(503))
        }
    }

    @MainActor
    func testCancellationPropagatesAsTypedCancellation() async {
        let client = GoogleTasksClient(
            baseURL: URL(string: "https://tasks.example")!,
            transport: CancellationHTTPTransport()
        )
        let task = Task { @MainActor in
            try await client.fetchIncompleteTasks(accessToken: "token")
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? GoogleTasksError, .cancelled)
        }
    }

    @MainActor
    private func makeClient() -> GoogleTasksClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return GoogleTasksClient(
            transport: URLSessionHTTPTransport(
                session: URLSession(configuration: configuration)
            )
        )
    }
}

@MainActor
private final class MutationRecordingTransport: HTTPTransport {
    private(set) var request: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        return (
            Data("{\"id\":\"task two\",\"status\":\"completed\"}".utf8),
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func record(_ request: URLRequest) {
        lock.lock()
        storedRequests.append(request)
        lock.unlock()
    }
}

@MainActor
private final class CancellationHTTPTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return (
            Data(),
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}
