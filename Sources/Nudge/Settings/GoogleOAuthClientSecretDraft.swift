import Foundation

struct GoogleOAuthClientSecretDraft: Equatable {
    var value = ""

    mutating func save(using saver: (String) -> Bool) -> Bool {
        guard saver(value) else {
            return false
        }
        value = ""
        return true
    }
}
