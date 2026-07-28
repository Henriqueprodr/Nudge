import Foundation
import SwiftData

enum NudgeSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            NudgeSchemaV3.StoredTask.self,
            StoredTaskList.self,
            StoredReminderDelivery.self,
            StoredTaskPanelState.self,
            StoredSyncMetadata.self,
            StoredTaskPendingAction.self,
            StoredCalendarDescriptor.self,
            StoredCalendarEvent.self,
            StoredCalendarSyncMetadata.self,
        ]
    }

    @Model
    final class StoredTaskPanelState {
        var isEnabled: Bool
        var displayModeRawValue: String
        var cornerRawValue: String
        var selectedTaskListIdentifier: String?

        init(
            isEnabled: Bool,
            displayModeRawValue: String,
            cornerRawValue: String,
            selectedTaskListIdentifier: String?
        ) {
            self.isEnabled = isEnabled
            self.displayModeRawValue = displayModeRawValue
            self.cornerRawValue = cornerRawValue
            self.selectedTaskListIdentifier = selectedTaskListIdentifier
        }
    }
}

enum NudgeSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            NudgeSchemaV3.StoredTask.self,
            StoredTaskList.self,
            StoredReminderDelivery.self,
            NudgeSchemaV2.StoredTaskPanelState.self,
            StoredSyncMetadata.self,
            StoredTaskPendingAction.self,
            StoredCalendarDescriptor.self,
            StoredCalendarEvent.self,
            StoredCalendarSyncMetadata.self,
        ]
    }

    @Model
    final class StoredTaskPanelState {
        var isEnabled: Bool
        var displayModeRawValue: String
        var cornerRawValue: String
        var selectedTaskListIdentifier: String?
        var screenIdentifier: String?

        init(
            isEnabled: Bool,
            displayModeRawValue: String,
            cornerRawValue: String,
            selectedTaskListIdentifier: String?,
            screenIdentifier: String?
        ) {
            self.isEnabled = isEnabled
            self.displayModeRawValue = displayModeRawValue
            self.cornerRawValue = cornerRawValue
            self.selectedTaskListIdentifier = selectedTaskListIdentifier
            self.screenIdentifier = screenIdentifier
        }
    }
}

enum NudgeSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            NudgeSchemaV3.StoredTask.self,
            StoredTaskList.self,
            StoredReminderDelivery.self,
            NudgeSchemaV3.StoredTaskPanelState.self,
            StoredSyncMetadata.self,
            StoredTaskPendingAction.self,
            StoredCalendarDescriptor.self,
            StoredCalendarEvent.self,
            StoredCalendarSyncMetadata.self,
        ]
    }

    @Model
    final class StoredTask {
        @Attribute(.unique) var identifier: String
        var taskListIdentifier: String
        var title: String
        var notes: String?
        var completionStateRawValue: String
        var dueYear: Int?
        var dueMonth: Int?
        var dueDay: Int?
        var overrideHour: Int?
        var overrideMinute: Int?
        var overrideTimeZoneIdentifier: String?
        var webViewURLString: String?
        var locallySnoozedUntil: Date?

        init(task: TaskItem) {
            identifier = task.id
            taskListIdentifier = task.taskListID
            title = task.title
            notes = task.notes
            completionStateRawValue = task.completionState.rawValue
            dueYear = task.dueDate?.year
            dueMonth = task.dueDate?.month
            dueDay = task.dueDate?.day
            overrideHour = task.localTimeOverride?.hour
            overrideMinute = task.localTimeOverride?.minute
            overrideTimeZoneIdentifier = task.localTimeOverride?.timeZoneIdentifier
            webViewURLString = task.webViewURL?.absoluteString
            locallySnoozedUntil = task.locallySnoozedUntil
        }
    }

    @Model
    final class StoredTaskPanelState {
        var isEnabled: Bool
        var displayModeRawValue: String
        var cornerRawValue: String
        var selectedTaskListIdentifier: String?
        var screenIdentifier: String?
        var opacity: Double = 1
        var maximumVisibleTaskCount: Int = 10

        init(state: TaskPanelState) {
            isEnabled = state.isEnabled
            displayModeRawValue = state.displayMode.rawValue
            cornerRawValue = state.corner.rawValue
            selectedTaskListIdentifier = state.selectedTaskListID
            screenIdentifier = state.screenIdentifier
            opacity = state.opacity
            maximumVisibleTaskCount = state.maximumVisibleTaskCount
        }
    }
}

enum NudgeSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            StoredTask.self,
            StoredTaskList.self,
            StoredReminderDelivery.self,
            StoredTaskPanelState.self,
            StoredSyncMetadata.self,
            StoredTaskPendingAction.self,
            StoredCalendarDescriptor.self,
            StoredCalendarEvent.self,
            StoredCalendarSyncMetadata.self,
        ]
    }
}

enum NudgeSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [NudgeSchemaV1.self, NudgeSchemaV2.self, NudgeSchemaV3.self, NudgeSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: NudgeSchemaV1.self, toVersion: NudgeSchemaV2.self),
            .lightweight(fromVersion: NudgeSchemaV2.self, toVersion: NudgeSchemaV3.self),
            .lightweight(fromVersion: NudgeSchemaV3.self, toVersion: NudgeSchemaV4.self),
        ]
    }
}
