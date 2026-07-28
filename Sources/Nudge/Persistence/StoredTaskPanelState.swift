import SwiftData

@Model
final class StoredTaskPanelState {
    var isEnabled: Bool
    var displayModeRawValue: String
    var cornerRawValue: String
    var selectedTaskListIdentifier: String?
    var screenIdentifier: String?
    var opacity: Double = 1
    var maximumVisibleTaskCount: Int = 10
    var placementModeRawValue: String = TaskPanelState.PlacementMode.anchored.rawValue
    var normalizedPositionX: Double?
    var normalizedPositionY: Double?
    var expandedHeight: Double = TaskPanelState.defaultExpandedHeight
    var highPriorityColorHex: String = TaskPriorityPalette.defaultValue.highColorHex
    var mediumPriorityColorHex: String = TaskPriorityPalette.defaultValue.mediumColorHex
    var lowPriorityColorHex: String = TaskPriorityPalette.defaultValue.lowColorHex

    init(state: TaskPanelState) {
        isEnabled = state.isEnabled
        displayModeRawValue = state.displayMode.rawValue
        cornerRawValue = state.corner.rawValue
        selectedTaskListIdentifier = state.selectedTaskListID
        screenIdentifier = state.screenIdentifier
        opacity = TaskPanelState.validatedOpacity(state.opacity)
        maximumVisibleTaskCount = TaskPanelState.validatedMaximumVisibleTaskCount(
            state.maximumVisibleTaskCount
        )
        applyExtendedState(from: state)
    }

    func update(from state: TaskPanelState) {
        isEnabled = state.isEnabled
        displayModeRawValue = state.displayMode.rawValue
        cornerRawValue = state.corner.rawValue
        selectedTaskListIdentifier = state.selectedTaskListID
        screenIdentifier = state.screenIdentifier
        opacity = TaskPanelState.validatedOpacity(state.opacity)
        maximumVisibleTaskCount = TaskPanelState.validatedMaximumVisibleTaskCount(
            state.maximumVisibleTaskCount
        )
        applyExtendedState(from: state)
    }

    func domainValue() -> TaskPanelState? {
        guard
            let displayMode = TaskPanelState.DisplayMode(rawValue: displayModeRawValue),
            let corner = ScreenCorner(rawValue: cornerRawValue),
            let placementMode = TaskPanelState.PlacementMode(rawValue: placementModeRawValue)
        else {
            return nil
        }

        let normalizedPosition: TaskPanelState.NormalizedPosition?
        if let normalizedPositionX, let normalizedPositionY {
            normalizedPosition = TaskPanelState.NormalizedPosition(
                x: normalizedPositionX,
                y: normalizedPositionY
            )
        } else {
            normalizedPosition = nil
        }

        return TaskPanelState(
            isEnabled: isEnabled,
            displayMode: displayMode,
            corner: corner,
            selectedTaskListID: selectedTaskListIdentifier,
            screenIdentifier: screenIdentifier,
            opacity: TaskPanelState.validatedOpacity(opacity),
            maximumVisibleTaskCount: TaskPanelState.validatedMaximumVisibleTaskCount(
                maximumVisibleTaskCount
            ),
            placementMode: placementMode,
            normalizedPosition: normalizedPosition,
            expandedHeight: TaskPanelState.validatedExpandedHeight(expandedHeight),
            priorityPalette: TaskPriorityPalette(
                highColorHex: highPriorityColorHex,
                mediumColorHex: mediumPriorityColorHex,
                lowColorHex: lowPriorityColorHex
            )
        )
    }

    private func applyExtendedState(from state: TaskPanelState) {
        placementModeRawValue = state.placementMode.rawValue
        normalizedPositionX = state.normalizedPosition?.x
        normalizedPositionY = state.normalizedPosition?.y
        expandedHeight = TaskPanelState.validatedExpandedHeight(state.expandedHeight)
        highPriorityColorHex = state.priorityPalette.highColorHex
        mediumPriorityColorHex = state.priorityPalette.mediumColorHex
        lowPriorityColorHex = state.priorityPalette.lowColorHex
    }
}
