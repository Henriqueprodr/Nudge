import Foundation

@MainActor
protocol GoogleTasksProviding: AnyObject {
    func fetchIncompleteTasks(accessToken: String) async throws -> GoogleTasksSnapshot
}

@MainActor
protocol GoogleTasksMutating: AnyObject {
    func completeTask(
        taskListID: String,
        taskID: String,
        accessToken: String
    ) async throws
}

@MainActor
final class GoogleTasksClient: GoogleTasksProviding {
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private let mapper: GoogleTasksMapper

    init(
        baseURL: URL = URL(string: "https://tasks.googleapis.com")!,
        transport: any HTTPTransport,
        decoder: JSONDecoder = JSONDecoder(),
        mapper: GoogleTasksMapper = GoogleTasksMapper()
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.decoder = decoder
        self.mapper = mapper
    }

    func fetchIncompleteTasks(accessToken: String) async throws -> GoogleTasksSnapshot {
        let taskLists = try await fetchTaskLists(accessToken: accessToken)
        var tasks: [TaskItem] = []
        for taskList in taskLists {
            try Task.checkCancellation()
            tasks.append(
                contentsOf: try await fetchTasks(
                    taskListID: taskList.id,
                    accessToken: accessToken
                )
            )
        }
        return GoogleTasksSnapshot(taskLists: taskLists, tasks: tasks)
    }

    func completeTask(
        taskListID: String,
        taskID: String,
        accessToken: String
    ) async throws {
        let encodedTaskListID = Self.percentEncodedPathComponent(taskListID)
        let encodedTaskID = Self.percentEncodedPathComponent(taskID)
        let url = try endpointURL(
            percentEncodedPath: "/tasks/v1/lists/\(encodedTaskListID)/tasks/\(encodedTaskID)",
            queryItems: []
        )
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["status": "completed"])

        let response: HTTPURLResponse
        do {
            (_, response) = try await transport.data(for: request)
        } catch {
            throw GoogleTasksError.normalized(error)
        }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw GoogleTasksError.authenticationRequired
            }
            throw GoogleTasksError.httpStatus(response.statusCode)
        }
    }

    private func fetchTaskLists(accessToken: String) async throws -> [TaskList] {
        var taskLists: [TaskList] = []
        var pageToken: String?
        var seenPageTokens: Set<String> = []

        repeat {
            try Task.checkCancellation()
            let url = try endpointURL(
                percentEncodedPath: "/tasks/v1/users/@me/lists",
                queryItems: [
                    URLQueryItem(name: "maxResults", value: "1000"),
                    URLQueryItem(name: "pageToken", value: pageToken),
                ]
            )
            let page: GoogleTasksDTO.TaskListPage = try await fetch(
                url: url,
                accessToken: accessToken
            )
            taskLists.append(contentsOf: (page.items ?? []).map(mapper.taskList(from:)))
            pageToken = try nextPageToken(page.nextPageToken, seen: &seenPageTokens)
        } while pageToken != nil

        return taskLists
    }

    private func fetchTasks(
        taskListID: String,
        accessToken: String
    ) async throws -> [TaskItem] {
        var tasks: [TaskItem] = []
        var pageToken: String?
        var seenPageTokens: Set<String> = []
        let encodedTaskListID = Self.percentEncodedPathComponent(taskListID)

        repeat {
            try Task.checkCancellation()
            let url = try endpointURL(
                percentEncodedPath: "/tasks/v1/lists/\(encodedTaskListID)/tasks",
                queryItems: [
                    URLQueryItem(name: "maxResults", value: "100"),
                    URLQueryItem(name: "showCompleted", value: "false"),
                    URLQueryItem(name: "showDeleted", value: "false"),
                    URLQueryItem(name: "showHidden", value: "false"),
                    URLQueryItem(name: "showAssigned", value: "true"),
                    URLQueryItem(name: "pageToken", value: pageToken),
                ]
            )
            let page: GoogleTasksDTO.TaskPage = try await fetch(
                url: url,
                accessToken: accessToken
            )
            tasks.append(
                contentsOf: (page.items ?? []).compactMap {
                    mapper.task(from: $0, taskListID: taskListID)
                }
            )
            pageToken = try nextPageToken(page.nextPageToken, seen: &seenPageTokens)
        } while pageToken != nil

        return tasks
    }

    private func fetch<Value: Decodable>(
        url: URL,
        accessToken: String
    ) async throws -> Value {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw GoogleTasksError.normalized(error)
        }

        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 {
                throw GoogleTasksError.authenticationRequired
            }
            throw GoogleTasksError.httpStatus(response.statusCode)
        }

        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw GoogleTasksError.decodingFailed
        }
    }

    private func endpointURL(
        percentEncodedPath: String,
        queryItems: [URLQueryItem]
    ) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GoogleTasksError.invalidResponse
        }
        components.percentEncodedPath = percentEncodedPath
        components.queryItems = queryItems.filter { $0.value != nil }
        guard let url = components.url else {
            throw GoogleTasksError.invalidResponse
        }
        return url
    }

    private func nextPageToken(
        _ nextPageToken: String?,
        seen: inout Set<String>
    ) throws -> String? {
        guard let nextPageToken, !nextPageToken.isEmpty else {
            return nil
        }
        guard seen.insert(nextPageToken).inserted else {
            throw GoogleTasksError.invalidResponse
        }
        return nextPageToken
    }

    private static func percentEncodedPathComponent(_ value: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}

extension GoogleTasksClient: GoogleTasksMutating {}
