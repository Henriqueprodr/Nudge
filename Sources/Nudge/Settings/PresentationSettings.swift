import Foundation

struct PresentationSettings: Codable, Equatable, Sendable {
    enum ReminderDisplayTarget: Codable, Equatable, Hashable, Sendable {
        case pointer
        case fixed(String)
    }

    /// Version 5 replaces the original sound palette and migrates removed audible choices to Hero.
    static let currentSchemaVersion = 5

    var schemaVersion: Int
    var reminderDisplayTarget: ReminderDisplayTarget
    var reminderDuration: ReminderPresentationDuration
    var remindersPersistUntilAction: Bool
    var reminderSound: ReminderSound
    var reminderOverFullScreen: Bool
    var taskPanelOverFullScreen: Bool
    var remindersJoinAllSpaces: Bool
    var taskPanelJoinsAllSpaces: Bool
    var showsDockIcon: Bool

    static let defaultValue = PresentationSettings(
        schemaVersion: currentSchemaVersion,
        reminderDisplayTarget: .pointer,
        reminderDuration: .defaultValue,
        remindersPersistUntilAction: false,
        reminderSound: .defaultValue,
        reminderOverFullScreen: false,
        taskPanelOverFullScreen: false,
        remindersJoinAllSpaces: true,
        taskPanelJoinsAllSpaces: true,
        showsDockIcon: false
    )

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reminderDisplayTarget
        case reminderDuration
        case remindersPersistUntilAction
        case reminderSound
        case reminderOverFullScreen
        case taskPanelOverFullScreen
        case remindersJoinAllSpaces
        case taskPanelJoinsAllSpaces
        case showsDockIcon
    }

    init(
        schemaVersion: Int,
        reminderDisplayTarget: ReminderDisplayTarget,
        reminderDuration: ReminderPresentationDuration,
        remindersPersistUntilAction: Bool,
        reminderSound: ReminderSound,
        reminderOverFullScreen: Bool,
        taskPanelOverFullScreen: Bool,
        remindersJoinAllSpaces: Bool,
        taskPanelJoinsAllSpaces: Bool,
        showsDockIcon: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.reminderDisplayTarget = reminderDisplayTarget
        self.reminderDuration = reminderDuration
        self.remindersPersistUntilAction = remindersPersistUntilAction
        self.reminderSound = reminderSound
        self.reminderOverFullScreen = reminderOverFullScreen
        self.taskPanelOverFullScreen = taskPanelOverFullScreen
        self.remindersJoinAllSpaces = remindersJoinAllSpaces
        self.taskPanelJoinsAllSpaces = taskPanelJoinsAllSpaces
        self.showsDockIcon = showsDockIcon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        schemaVersion = max(storedSchemaVersion, Self.currentSchemaVersion)
        reminderDisplayTarget = try container.decodeIfPresent(
            ReminderDisplayTarget.self,
            forKey: .reminderDisplayTarget
        ) ?? .pointer
        reminderDuration = try container.decodeIfPresent(
            ReminderPresentationDuration.self,
            forKey: .reminderDuration
        ) ?? .defaultValue
        // A missing preference adopts the timed default. Any explicitly stored choice remains
        // durable, including settings written before the Control Strip redesign.
        let storedPersistence = try container.decodeIfPresent(
            Bool.self,
            forKey: .remindersPersistUntilAction
        )
        remindersPersistUntilAction = storedPersistence ?? false
        reminderSound = try container.decodeIfPresent(
            ReminderSound.self,
            forKey: .reminderSound
        ) ?? .defaultValue
        reminderOverFullScreen = try container.decodeIfPresent(
            Bool.self,
            forKey: .reminderOverFullScreen
        ) ?? false
        taskPanelOverFullScreen = try container.decodeIfPresent(
            Bool.self,
            forKey: .taskPanelOverFullScreen
        ) ?? false
        remindersJoinAllSpaces = try container.decodeIfPresent(
            Bool.self,
            forKey: .remindersJoinAllSpaces
        ) ?? true
        taskPanelJoinsAllSpaces = try container.decodeIfPresent(
            Bool.self,
            forKey: .taskPanelJoinsAllSpaces
        ) ?? true
        showsDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showsDockIcon) ?? false
    }
}
