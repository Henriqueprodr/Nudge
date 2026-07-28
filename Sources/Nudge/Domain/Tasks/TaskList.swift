import Foundation

struct TaskList: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var title: String
}
