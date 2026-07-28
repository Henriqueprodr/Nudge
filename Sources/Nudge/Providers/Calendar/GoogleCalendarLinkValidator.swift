import Foundation

enum GoogleCalendarLinkValidator {
    static func validatedURL(from value: String?) -> URL? {
        guard
            let value,
            let url = URL(string: value),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            components.user == nil,
            components.password == nil,
            let host = components.host?.lowercased(),
            host == "calendar.google.com" || host == "www.google.com",
            components.path.lowercased().contains("calendar")
        else {
            return nil
        }
        return url
    }
}
