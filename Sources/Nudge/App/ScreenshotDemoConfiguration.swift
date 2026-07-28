#if DEBUG
import Foundation

enum ScreenshotDemoPage: String, CaseIterable, Sendable {
    case menu
    case account
    case reminders
    case tasks
    case application
    case overlay
    case taskPanel = "task-panel"

    var outputFilename: String {
        switch self {
        case .menu:
            return "menu-bar.png"
        case .account:
            return "settings-account.png"
        case .reminders:
            return "settings-reminders.png"
        case .tasks:
            return "settings-tasks.png"
        case .application:
            return "settings-application.png"
        case .overlay:
            return "reminder-overlay.png"
        case .taskPanel:
            return "task-panel.png"
        }
    }
}

struct ScreenshotDemoConfiguration: Equatable, Sendable {
    enum ConfigurationError: Error, Equatable {
        case missingPage
        case invalidPage(String)
        case missingOutput
        case invalidOutputExtension
    }

    static let enableArgument = "--screenshot-demo"
    static let pageArgument = "--screenshot-page"
    static let outputArgument = "--screenshot-output"

    let page: ScreenshotDemoPage
    let outputURL: URL

    static func isRequested(arguments: [String]) -> Bool {
        arguments.contains(enableArgument)
    }

    static func parse(arguments: [String]) throws -> ScreenshotDemoConfiguration {
        guard isRequested(arguments: arguments) else {
            throw ConfigurationError.missingPage
        }
        guard let pageValue = value(after: pageArgument, in: arguments) else {
            throw ConfigurationError.missingPage
        }
        guard let page = ScreenshotDemoPage(rawValue: pageValue) else {
            throw ConfigurationError.invalidPage(pageValue)
        }
        guard let outputValue = value(after: outputArgument, in: arguments),
              !outputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationError.missingOutput
        }
        let outputURL = URL(fileURLWithPath: outputValue).standardizedFileURL
        guard outputURL.pathExtension.lowercased() == "png" else {
            throw ConfigurationError.invalidOutputExtension
        }
        return ScreenshotDemoConfiguration(page: page, outputURL: outputURL)
    }

    private static func value(after argument: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }
        return arguments[valueIndex]
    }
}
#endif
