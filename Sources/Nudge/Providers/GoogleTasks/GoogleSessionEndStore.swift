import Foundation

@MainActor
protocol GoogleSessionEndStore: AnyObject {
    func loadRecord() -> GoogleSessionEndRecord?
    func saveRecord(_ record: GoogleSessionEndRecord)
    func clearRecord()
}
