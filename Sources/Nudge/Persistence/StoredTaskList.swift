import SwiftData

@Model
final class StoredTaskList {
    @Attribute(.unique) var identifier: String
    var title: String

    init(taskList: TaskList) {
        identifier = taskList.id
        title = taskList.title
    }

    func update(from taskList: TaskList) {
        title = taskList.title
    }

    func domainValue() -> TaskList {
        TaskList(id: identifier, title: title)
    }
}
