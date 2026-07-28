import SwiftData

@MainActor
final class SwiftDataTaskRepository: TaskRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchIncompleteTasks() throws -> [TaskItem] {
        try modelContext.fetch(FetchDescriptor<StoredTask>())
            .compactMap { $0.domainValue() }
            .filter(\.isIncomplete)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func fetchTaskLists() throws -> [TaskList] {
        try modelContext.fetch(FetchDescriptor<StoredTaskList>())
            .map { $0.domainValue() }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func fetchTask(identifier: String) throws -> TaskItem? {
        try modelContext.fetch(FetchDescriptor<StoredTask>())
            .first(where: { $0.identifier == identifier })?
            .domainValue()
    }

    func saveTask(_ task: TaskItem) throws {
        let storedTasks = try modelContext.fetch(FetchDescriptor<StoredTask>())
        if let storedTask = storedTasks.first(where: { $0.identifier == task.id }) {
            storedTask.update(from: task)
        } else {
            modelContext.insert(StoredTask(task: task))
        }
        try modelContext.save()
    }

    func replaceCache(taskLists: [TaskList], tasks: [TaskItem]) throws {
        let existingLists = try modelContext.fetch(FetchDescriptor<StoredTaskList>())
        let incomingListIDs = Set(taskLists.map(\.id))
        for storedList in existingLists where !incomingListIDs.contains(storedList.identifier) {
            modelContext.delete(storedList)
        }
        for taskList in taskLists {
            if let storedList = existingLists.first(where: { $0.identifier == taskList.id }) {
                storedList.update(from: taskList)
            } else {
                modelContext.insert(StoredTaskList(taskList: taskList))
            }
        }

        let existingTasks = try modelContext.fetch(FetchDescriptor<StoredTask>())
        let existingTasksByIdentifier = Dictionary(
            uniqueKeysWithValues: existingTasks.map { ($0.identifier, $0) }
        )
        let incomingTaskIDs = Set(tasks.map(\.id))
        for storedTask in existingTasks where !incomingTaskIDs.contains(storedTask.identifier) {
            modelContext.delete(storedTask)
        }
        for task in tasks {
            if let storedTask = existingTasksByIdentifier[task.id] {
                var reconciledTask = task
                if reconciledTask.localTimeOverride == nil {
                    reconciledTask.localTimeOverride = storedTask.domainValue()?.localTimeOverride
                }
                if reconciledTask.locallySnoozedUntil == nil {
                    reconciledTask.locallySnoozedUntil = storedTask.domainValue()?.locallySnoozedUntil
                }
                reconciledTask.priority = storedTask.domainValue()?.priority ?? .none
                storedTask.update(from: reconciledTask)
            } else {
                modelContext.insert(StoredTask(task: task))
            }
        }

        try modelContext.save()
    }
}
