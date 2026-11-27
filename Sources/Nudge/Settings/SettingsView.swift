import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Sendable {
    case account
    case reminders
    case tasks
    case application
}

struct SettingsView: View {
    private enum ReminderVisibilityMode: String, CaseIterable, Identifiable {
        case timed
        case persistent

        var id: Self { self }

        var label: String {
            switch self {
            case .timed:
                return "Timed"
            case .persistent:
                return "Persistent"
            }
        }
    }

    let calendarCoordinator: CalendarScheduleCoordinator
    let googleTasksCoordinator: GoogleTasksSyncCoordinator
    let googleOAuthConfigurationManager: GoogleOAuthClientConfigurationManager
    let windowCoordinator: WindowPresentationCoordinator
    let launchAtLoginManager: LaunchAtLoginManager
    let persistenceStatusMessage: String?
    @State private var selectedTab: SettingsTab
    @State private var googleClientSecretDraft = GoogleOAuthClientSecretDraft()
    @State private var isImportingGoogleOAuthConfiguration = false
    @State private var googleOAuthConfigurationStatusMessage: String?

    init(
        calendarCoordinator: CalendarScheduleCoordinator,
        googleTasksCoordinator: GoogleTasksSyncCoordinator,
        googleOAuthConfigurationManager: GoogleOAuthClientConfigurationManager,
        windowCoordinator: WindowPresentationCoordinator,
        launchAtLoginManager: LaunchAtLoginManager,
        persistenceStatusMessage: String?,
        initialTab: SettingsTab = .account
    ) {
        self.calendarCoordinator = calendarCoordinator
        self.googleTasksCoordinator = googleTasksCoordinator
        self.googleOAuthConfigurationManager = googleOAuthConfigurationManager
        self.windowCoordinator = windowCoordinator
        self.launchAtLoginManager = launchAtLoginManager
        self.persistenceStatusMessage = persistenceStatusMessage
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            accountSettings
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(SettingsTab.account)
            reminderSettings
                .tabItem { Label("Reminders", systemImage: "bell.badge") }
                .tag(SettingsTab.reminders)
            taskSettings
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(SettingsTab.tasks)
            applicationSettings
                .tabItem { Label("Application", systemImage: "gearshape") }
                .tag(SettingsTab.application)
        }
        .frame(width: 640, height: 700)
        .tint(NudgePalette.blue)
        .fileImporter(
            isPresented: $isImportingGoogleOAuthConfiguration,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleGoogleOAuthImport
        )
    }

    private var accountSettings: some View {
        Form {
            Section {
                SettingsBrandHeader()
            }

            Section("Google account") {
                LabeledContent(
                    "OAuth configuration",
                    value: googleOAuthConfigurationManager.source?.label ?? "Not configured"
                )
                LabeledContent(
                    "OAuth client secret",
                    value: clientSecretStatus
                )

                if googleOAuthConfigurationManager.source == nil {
                    Text(
                        "Import the JSON downloaded for a Google Desktop OAuth client. " +
                            "Nudge stores the client ID and secret together in Keychain on this Mac."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else if googleOAuthConfigurationManager.source == .bundled {
                    Text("This build includes its Desktop OAuth configuration.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if googleOAuthConfigurationManager.source == .imported {
                    Text("The imported Desktop OAuth configuration is stored only in Keychain.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if googleOAuthConfigurationManager.source == nil ||
                    googleOAuthConfigurationManager.source == .imported {
                    HStack {
                        Button(
                            googleOAuthConfigurationManager.hasImportedConfiguration
                                ? "Import Replacement JSON…"
                                : "Import Desktop OAuth JSON…"
                        ) {
                            isImportingGoogleOAuthConfiguration = true
                        }
                        .disabled(!canModifyGoogleOAuthConfiguration)

                        if googleOAuthConfigurationManager.hasImportedConfiguration {
                            Button("Remove Imported Configuration", role: .destructive) {
                                removeImportedGoogleOAuthConfiguration()
                            }
                            .disabled(!canModifyGoogleOAuthConfiguration)
                        }
                    }
                } else if !googleTasksCoordinator.hasBundledClientSecret {
                    if !googleTasksCoordinator.hasStoredClientSecret {
                        HStack {
                            SecureField(
                                "Optional desktop client secret",
                                text: $googleClientSecretDraft.value
                            )
                            Button("Save") {
                                _ = googleClientSecretDraft.save {
                                    googleTasksCoordinator.saveClientSecret($0)
                                }
                            }
                            .disabled(googleClientSecretDraft.value.isEmpty)
                        }
                    } else {
                        Button("Remove Client Secret") {
                            googleTasksCoordinator.removeClientSecret()
                        }
                        .disabled(
                            googleTasksCoordinator.isAuthenticated || providerOperationInProgress
                        )
                    }
                }

                if let googleOAuthConfigurationStatusMessage {
                    Text(googleOAuthConfigurationStatusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let secureStoreStatusMessage =
                    googleOAuthConfigurationManager.secureStoreStatusMessage {
                    Text(secureStoreStatusMessage)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                accountAction

                if calendarCoordinator.isAuthenticating || googleTasksCoordinator.isAuthenticating {
                    ProgressView().controlSize(.small)
                }
            }

            Section("Provider status") {
                LabeledContent("Google Calendar", value: calendarCoordinator.statusMessage)
                LabeledContent("Google Tasks", value: googleTasksCoordinator.authenticationStatusMessage)
                Text("Calendar and Tasks use separate clients, caches, status, and refresh coordinators.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var reminderSettings: some View {
        Form {
            Section("Presentation") {
                Picker("Mode", selection: reminderVisibilityModeBinding) {
                    ForEach(ReminderVisibilityMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Sound", selection: reminderSoundBinding) {
                    ForEach(ReminderSound.allCases) { sound in
                        Text(sound.label).tag(sound)
                    }
                }
                .pickerStyle(.menu)
                Text("Selecting a sound plays a preview. Off silences reminder overlays and fallback notifications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(
                    "Display duration: \(windowCoordinator.reminderDuration.seconds) seconds",
                    value: reminderDurationBinding,
                    in: ReminderPresentationDuration.allowedSeconds
                )
                .disabled(windowCoordinator.remindersPersistUntilAction)

                Picker("Display", selection: reminderDisplayBinding) {
                    Text("Display containing pointer")
                        .tag(PresentationSettings.ReminderDisplayTarget.pointer)
                    if let missingReminderDisplayTarget {
                        Text("Saved display (currently unavailable)")
                            .tag(missingReminderDisplayTarget)
                    }
                    ForEach(windowCoordinator.availableScreens) { screen in
                        Text(screen.name)
                            .tag(PresentationSettings.ReminderDisplayTarget.fixed(screen.id))
                    }
                }
                Toggle("Show on all ordinary Spaces", isOn: remindersJoinAllSpacesBinding)
                Toggle("Show over full-screen apps", isOn: reminderFullScreenBinding)
            }

            Section("Google Calendar") {
                if calendarCoordinator.calendars.isEmpty {
                    Text("No cached Google calendars are available yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendarCoordinator.calendars) { calendar in
                        Toggle(
                            calendar.title,
                            isOn: Binding(
                                get: {
                                    calendarCoordinator.selectedCalendarIdentifiers.contains(calendar.id)
                                },
                                set: { isSelected in
                                    Task {
                                        await calendarCoordinator.setCalendar(
                                            calendar.id,
                                            isSelected: isSelected
                                        )
                                    }
                                }
                            )
                        )
                    }
                }

                HStack {
                    Button("Refresh Calendar") {
                        Task { await calendarCoordinator.refreshSchedule() }
                    }
                    .disabled(
                        calendarCoordinator.isRefreshing ||
                            !calendarCoordinator.hasCalendarAuthorization
                    )
                    if calendarCoordinator.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }
                Stepper(
                    "Periodic refresh: \(calendarRefreshMinutes) minutes",
                    value: calendarRefreshBinding,
                    in: PeriodicRefreshInterval.allowedMinutes
                )
                Toggle(
                    "Use Notification Center only when the overlay is unavailable",
                    isOn: Binding(
                        get: { calendarCoordinator.usesNotificationFallback },
                        set: { value in
                            Task { await calendarCoordinator.setUsesNotificationFallback(value) }
                        }
                    )
                )
                Text(calendarCoordinator.notificationFallbackStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(calendarCoordinator.metadata.freshnessSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var taskSettings: some View {
        Form {
            Section("Google Tasks synchronization") {
                LabeledContent("Account", value: googleTasksCoordinator.authenticationStatusMessage)
                HStack {
                    Button("Refresh Tasks") {
                        googleTasksCoordinator.requestRefresh(.manual)
                    }
                    .disabled(
                        googleTasksCoordinator.isRefreshing ||
                            !googleTasksCoordinator.isAuthenticated
                    )
                    if googleTasksCoordinator.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }
                Stepper(
                    "Periodic refresh: \(tasksRefreshMinutes) minutes",
                    value: tasksRefreshBinding,
                    in: PeriodicRefreshInterval.allowedMinutes
                )
                Text(
                    googleTasksCoordinator.metadata.statusMessage
                        ?? "Cached tasks remain visible between synchronizations."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                Text(googleTasksCoordinator.metadata.freshnessSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Persistent corner panel") {
                Picker("Placement", selection: taskPanelPlacementBinding) {
                    Text("Fixed").tag(TaskPanelState.PlacementMode.anchored)
                    Text("Free").tag(TaskPanelState.PlacementMode.custom)
                }
                .pickerStyle(.segmented)
                Picker("Display", selection: taskPanelDisplayBinding) {
                    Text("Main display").tag(nil as String?)
                    if let missingTaskPanelScreenIdentifier {
                        Text("Saved display (currently unavailable)")
                            .tag(missingTaskPanelScreenIdentifier as String?)
                    }
                    ForEach(windowCoordinator.availableScreens) { screen in
                        Text(screen.name).tag(screen.id as String?)
                    }
                }
                Picker("Corner", selection: taskPanelCornerBinding) {
                    ForEach(ScreenCorner.allCases, id: \.self) { corner in
                        Text(corner.rawValue).tag(corner)
                    }
                }
                .disabled(windowCoordinator.taskPanelPlacementMode == .custom)
                Text(
                    windowCoordinator.taskPanelPlacementMode == .anchored
                        ? "Fixed keeps the panel in the selected corner."
                        : "Free lets you move the panel using its header grip."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Picker("Size", selection: taskPanelModeBinding) {
                    Text("Compact").tag(TaskPanelState.DisplayMode.compact)
                    Text("Expanded").tag(TaskPanelState.DisplayMode.expanded)
                }
                Slider(
                    value: taskPanelOpacityBinding,
                    in: 0.65...1,
                    step: 0.05
                ) {
                    Text("Opacity")
                } minimumValueLabel: {
                    Text("65%")
                } maximumValueLabel: {
                    Text("100%")
                }
                Text("Opacity: \(Int(windowCoordinator.taskPanelOpacity * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ColorPicker(
                    "High priority",
                    selection: taskPriorityColorBinding(for: .high),
                    supportsOpacity: false
                )
                ColorPicker(
                    "Medium priority",
                    selection: taskPriorityColorBinding(for: .medium),
                    supportsOpacity: false
                )
                ColorPicker(
                    "Low priority",
                    selection: taskPriorityColorBinding(for: .low),
                    supportsOpacity: false
                )
                Text("Task priorities and their colors are stored locally by Nudge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show on all ordinary Spaces", isOn: taskPanelJoinsAllSpacesBinding)
                Toggle("Show over full-screen apps", isOn: taskPanelFullScreenBinding)
                Text("The cached panel remains independent from reminder overlays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var applicationSettings: some View {
        Form {
            Section("Application") {
                Toggle(
                    "Show Nudge in the Dock",
                    isOn: Binding(
                        get: { windowCoordinator.showsDockIcon },
                        set: { _ = windowCoordinator.setShowsDockIcon($0) }
                    )
                )
                Toggle(
                    "Launch Nudge at login",
                    isOn: Binding(
                        get: { launchAtLoginManager.status.isEnabled },
                        set: { launchAtLoginManager.setEnabled($0) }
                    )
                )
                Text(launchAtLoginManager.status.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if launchAtLoginManager.status == .requiresApproval {
                    Button("Open Login Items Settings") {
                        launchAtLoginManager.openSystemSettings()
                    }
                }
            }

            Section("Local data") {
                Text("Cached Calendar reminders and Google Tasks stay available during provider failures.")
                    .foregroundStyle(.secondary)
                if let persistenceStatusMessage {
                    Text(persistenceStatusMessage)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var accountAction: some View {
        if calendarCoordinator.needsScopeUpgrade {
            Button("Add Google Calendar Access") {
                Task {
                    _ = await calendarCoordinator.signInWithGoogle()
                    googleTasksCoordinator.accountDidAuthenticate()
                }
            }
            .disabled(calendarCoordinator.isAuthenticating)
        } else if googleTasksCoordinator.isAuthenticated || calendarCoordinator.hasCalendarAuthorization {
            Button("Disconnect Google Account") {
                googleTasksCoordinator.signOut()
                calendarCoordinator.accountDidDisconnect()
            }
            .disabled(providerOperationInProgress)
        } else {
            Button("Sign in with Google") {
                Task {
                    _ = await calendarCoordinator.signInWithGoogle()
                    googleTasksCoordinator.accountDidAuthenticate()
                }
            }
            .disabled(
                calendarCoordinator.isAuthenticating ||
                    !googleTasksCoordinator.isOAuthClientConfigured
            )
        }
    }

    private var clientSecretStatus: String {
        if !googleTasksCoordinator.isClientIDConfigured {
            return "Not checked"
        }
        if googleOAuthConfigurationManager.source == .imported {
            return "Stored in Keychain"
        }
        if googleOAuthConfigurationManager.source == .environment {
            return googleTasksCoordinator.hasBundledClientSecret
                ? "Build environment"
                : "Optional — not stored"
        }
        if googleTasksCoordinator.hasBundledClientSecret {
            return "Included in this build"
        }
        if googleTasksCoordinator.hasStoredClientSecret {
            return "Stored securely"
        }
        return "Optional — not stored"
    }

    private var canModifyGoogleOAuthConfiguration: Bool {
        GoogleOAuthClientConfigurationChangePolicy.canModify(
            isTasksAuthenticated: googleTasksCoordinator.isAuthenticated,
            hasStoredGoogleCredential: calendarCoordinator.hasStoredGoogleCredential,
            providerOperationInProgress: providerOperationInProgress
        )
    }

    private func handleGoogleOAuthImport(_ result: Result<[URL], Error>) {
        do {
            guard canModifyGoogleOAuthConfiguration else {
                googleOAuthConfigurationStatusMessage =
                    "Disconnect the Google account before changing its OAuth client."
                return
            }
            guard let url = try result.get().first else {
                return
            }
            try googleOAuthConfigurationManager.importConfiguration(from: url)
            notifyGoogleOAuthConfigurationChanged()
            googleOAuthConfigurationStatusMessage =
                "Desktop OAuth configuration imported securely. You can now sign in."
        } catch let error as GoogleOAuthClientConfigurationError {
            googleOAuthConfigurationStatusMessage = error.userMessage
        } catch {
            googleOAuthConfigurationStatusMessage =
                GoogleOAuthClientConfigurationError.unreadableFile.userMessage
        }
    }

    private func removeImportedGoogleOAuthConfiguration() {
        guard canModifyGoogleOAuthConfiguration else {
            googleOAuthConfigurationStatusMessage =
                "Disconnect the Google account before changing its OAuth client."
            return
        }
        do {
            try googleOAuthConfigurationManager.removeImportedConfiguration()
            notifyGoogleOAuthConfigurationChanged()
            googleOAuthConfigurationStatusMessage = "Imported OAuth configuration removed."
        } catch let error as GoogleOAuthClientConfigurationError {
            googleOAuthConfigurationStatusMessage = error.userMessage
        } catch {
            googleOAuthConfigurationStatusMessage =
                GoogleOAuthClientConfigurationError.secureStoreFailed.userMessage
        }
    }

    private func notifyGoogleOAuthConfigurationChanged() {
        calendarCoordinator.clientConfigurationDidChange()
        googleTasksCoordinator.clientConfigurationDidChange()
    }

    private var providerOperationInProgress: Bool {
        googleTasksCoordinator.isAuthenticating ||
            googleTasksCoordinator.isRefreshing ||
            calendarCoordinator.isRefreshing
    }

    private var reminderDurationBinding: Binding<Int> {
        Binding(
            get: { windowCoordinator.reminderDuration.seconds },
            set: { windowCoordinator.setReminderDuration(seconds: $0) }
        )
    }

    private var reminderVisibilityModeBinding: Binding<ReminderVisibilityMode> {
        Binding(
            get: {
                windowCoordinator.remindersPersistUntilAction ? .persistent : .timed
            },
            set: {
                windowCoordinator.setRemindersPersistUntilAction($0 == .persistent)
            }
        )
    }

    private var reminderSoundBinding: Binding<ReminderSound> {
        Binding(
            get: { windowCoordinator.reminderSound },
            set: { windowCoordinator.setReminderSound($0) }
        )
    }

    private var reminderDisplayBinding: Binding<PresentationSettings.ReminderDisplayTarget> {
        Binding(
            get: { windowCoordinator.reminderDisplayTarget },
            set: { windowCoordinator.setReminderDisplayTarget($0) }
        )
    }

    private var taskPanelDisplayBinding: Binding<String?> {
        Binding(
            get: { windowCoordinator.taskPanelScreenIdentifier },
            set: { windowCoordinator.setTaskPanelScreenIdentifier($0) }
        )
    }

    private var taskPanelCornerBinding: Binding<ScreenCorner> {
        Binding(
            get: { windowCoordinator.taskPanelCorner },
            set: { windowCoordinator.setTaskPanelCorner($0) }
        )
    }

    private var taskPanelModeBinding: Binding<TaskPanelState.DisplayMode> {
        Binding(
            get: { windowCoordinator.taskPanelDisplayMode },
            set: { windowCoordinator.setTaskPanelDisplayMode($0) }
        )
    }

    private var taskPanelPlacementBinding: Binding<TaskPanelState.PlacementMode> {
        Binding(
            get: { windowCoordinator.taskPanelPlacementMode },
            set: { windowCoordinator.setTaskPanelPlacementMode($0) }
        )
    }

    private var taskPanelOpacityBinding: Binding<Double> {
        Binding(
            get: { windowCoordinator.taskPanelOpacity },
            set: { windowCoordinator.setTaskPanelOpacity($0) }
        )
    }

    private func taskPriorityColorBinding(for priority: TaskPriority) -> Binding<Color> {
        Binding(
            get: {
                let palette = windowCoordinator.taskPanelPriorityPalette
                let fallback = TaskPriorityPalette.defaultValue.colorHex(for: priority) ?? "#000000"
                return TaskPriorityColor.color(hex: palette.colorHex(for: priority) ?? fallback)
            },
            set: { color in
                let palette = windowCoordinator.taskPanelPriorityPalette
                let fallback = palette.colorHex(for: priority)
                    ?? TaskPriorityPalette.defaultValue.colorHex(for: priority)
                    ?? "#000000"
                windowCoordinator.setTaskPanelPriorityColor(
                    TaskPriorityColor.hex(color: color, fallback: fallback),
                    for: priority
                )
            }
        )
    }

    private var reminderFullScreenBinding: Binding<Bool> {
        Binding(
            get: { windowCoordinator.reminderOverFullScreen },
            set: { windowCoordinator.setReminderOverFullScreen($0) }
        )
    }

    private var taskPanelFullScreenBinding: Binding<Bool> {
        Binding(
            get: { windowCoordinator.taskPanelOverFullScreen },
            set: { windowCoordinator.setTaskPanelOverFullScreen($0) }
        )
    }

    private var remindersJoinAllSpacesBinding: Binding<Bool> {
        Binding(
            get: { windowCoordinator.remindersJoinAllSpaces },
            set: { windowCoordinator.setRemindersJoinAllSpaces($0) }
        )
    }

    private var taskPanelJoinsAllSpacesBinding: Binding<Bool> {
        Binding(
            get: { windowCoordinator.taskPanelJoinsAllSpaces },
            set: { windowCoordinator.setTaskPanelJoinsAllSpaces($0) }
        )
    }

    private var calendarRefreshMinutes: Int {
        Int(calendarCoordinator.periodicInterval / 60)
    }

    private var calendarRefreshBinding: Binding<Int> {
        Binding(
            get: { calendarRefreshMinutes },
            set: {
                calendarCoordinator.setPeriodicRefreshInterval(
                    PeriodicRefreshInterval(minutes: $0)
                )
            }
        )
    }

    private var tasksRefreshMinutes: Int {
        Int(googleTasksCoordinator.periodicInterval / 60)
    }

    private var tasksRefreshBinding: Binding<Int> {
        Binding(
            get: { tasksRefreshMinutes },
            set: {
                googleTasksCoordinator.setPeriodicRefreshInterval(
                    PeriodicRefreshInterval(minutes: $0)
                )
            }
        )
    }

    private var missingReminderDisplayTarget: PresentationSettings.ReminderDisplayTarget? {
        guard case let .fixed(identifier) = windowCoordinator.reminderDisplayTarget,
              !windowCoordinator.availableScreens.contains(where: { $0.id == identifier }) else {
            return nil
        }
        return .fixed(identifier)
    }

    private var missingTaskPanelScreenIdentifier: String? {
        guard let identifier = windowCoordinator.taskPanelScreenIdentifier,
              !windowCoordinator.availableScreens.contains(where: { $0.id == identifier }) else {
            return nil
        }
        return identifier
    }
}
