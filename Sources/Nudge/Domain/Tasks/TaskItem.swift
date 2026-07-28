import Foundation

struct TaskItem: Codable, Hashable, Identifiable, Sendable {
    enum CompletionState: String, Codable, Hashable, Sendable {
        case incomplete
        case completed
    }

    struct DueDate: Codable, Hashable, Sendable {
        let year: Int
        let month: Int
        let day: Int
    }

    struct LocalTimeOverride: Codable, Hashable, Sendable {
        let hour: Int
        let minute: Int
        let timeZoneIdentifier: String
    }

    let id: String
    let taskListID: String
    var title: String
    var notes: String?
    var completionState: CompletionState
    var dueDate: DueDate?
    var localTimeOverride: LocalTimeOverride?
    var webViewURL: URL? = nil
    var locallySnoozedUntil: Date? = nil
    var priority: TaskPriority = .none

    var isIncomplete: Bool {
        completionState == .incomplete
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case taskListID
        case title
        case notes
        case completionState
        case dueDate
        case localTimeOverride
        case webViewURL
        case locallySnoozedUntil
        case priority
    }

    init(
        id: String,
        taskListID: String,
        title: String,
        notes: String?,
        completionState: CompletionState,
        dueDate: DueDate?,
        localTimeOverride: LocalTimeOverride?,
        webViewURL: URL? = nil,
        locallySnoozedUntil: Date? = nil,
        priority: TaskPriority = .none
    ) {
        self.id = id
        self.taskListID = taskListID
        self.title = title
        self.notes = notes
        self.completionState = completionState
        self.dueDate = dueDate
        self.localTimeOverride = localTimeOverride
        self.webViewURL = webViewURL
        self.locallySnoozedUntil = locallySnoozedUntil
        self.priority = priority
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            taskListID: try container.decode(String.self, forKey: .taskListID),
            title: try container.decode(String.self, forKey: .title),
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            completionState: try container.decode(CompletionState.self, forKey: .completionState),
            dueDate: try container.decodeIfPresent(DueDate.self, forKey: .dueDate),
            localTimeOverride: try container.decodeIfPresent(
                LocalTimeOverride.self,
                forKey: .localTimeOverride
            ),
            webViewURL: try container.decodeIfPresent(URL.self, forKey: .webViewURL),
            locallySnoozedUntil: try container.decodeIfPresent(
                Date.self,
                forKey: .locallySnoozedUntil
            ),
            priority: try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .none
        )
    }
}
