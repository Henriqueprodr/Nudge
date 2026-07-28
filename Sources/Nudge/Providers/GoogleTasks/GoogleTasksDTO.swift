import Foundation

enum GoogleTasksDTO {
    struct TaskListPage: Decodable, Sendable {
        let nextPageToken: String?
        let items: [TaskListValue]?
    }

    struct TaskListValue: Decodable, Sendable {
        let id: String
        let title: String
    }

    struct TaskPage: Decodable, Sendable {
        let nextPageToken: String?
        let items: [TaskValue]?
    }

    struct TaskValue: Decodable, Sendable {
        let id: String
        let title: String
        let notes: String?
        let status: String
        let due: String?
        let webViewLink: String?
        let deleted: Bool?
        let hidden: Bool?
    }
}
