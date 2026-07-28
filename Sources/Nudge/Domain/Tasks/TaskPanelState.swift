import Foundation

struct TaskPanelState: Codable, Equatable, Sendable {
    enum DisplayMode: String, Codable, Sendable {
        case compact
        case expanded
    }

    enum PlacementMode: String, Codable, Sendable {
        case anchored
        case custom
    }

    struct NormalizedPosition: Codable, Equatable, Sendable {
        let x: Double
        let y: Double

        init(x: Double, y: Double) {
            self.x = min(max(x, 0), 1)
            self.y = min(max(y, 0), 1)
        }
    }

    static let defaultExpandedHeight = 254.0

    var isEnabled: Bool
    var displayMode: DisplayMode
    var corner: ScreenCorner
    var selectedTaskListID: String? = nil
    var screenIdentifier: String? = nil
    var opacity: Double = 1
    // Retained for compatibility with the existing persisted schema. The panel
    // now renders every filtered task and no longer exposes this as a setting.
    var maximumVisibleTaskCount: Int = 10
    var placementMode: PlacementMode = .anchored
    var normalizedPosition: NormalizedPosition? = nil
    var expandedHeight: Double = Self.defaultExpandedHeight
    var priorityPalette: TaskPriorityPalette = .defaultValue

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case displayMode
        case corner
        case selectedTaskListID
        case screenIdentifier
        case opacity
        case maximumVisibleTaskCount
        case placementMode
        case normalizedPosition
        case expandedHeight
        case priorityPalette
    }

    init(
        isEnabled: Bool,
        displayMode: DisplayMode,
        corner: ScreenCorner,
        selectedTaskListID: String? = nil,
        screenIdentifier: String? = nil,
        opacity: Double = 1,
        maximumVisibleTaskCount: Int = 10,
        placementMode: PlacementMode = .anchored,
        normalizedPosition: NormalizedPosition? = nil,
        expandedHeight: Double = Self.defaultExpandedHeight,
        priorityPalette: TaskPriorityPalette = .defaultValue
    ) {
        self.isEnabled = isEnabled
        self.displayMode = displayMode
        self.corner = corner
        self.selectedTaskListID = selectedTaskListID
        self.screenIdentifier = screenIdentifier
        self.opacity = Self.validatedOpacity(opacity)
        self.maximumVisibleTaskCount = Self.validatedMaximumVisibleTaskCount(
            maximumVisibleTaskCount
        )
        self.placementMode = placementMode
        // Keep the last free-placement coordinates while the panel is fixed so
        // switching back to Free can restore the user's previous location.
        self.normalizedPosition = normalizedPosition
        self.expandedHeight = Self.validatedExpandedHeight(expandedHeight)
        self.priorityPalette = priorityPalette
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            displayMode: try container.decode(DisplayMode.self, forKey: .displayMode),
            corner: try container.decode(ScreenCorner.self, forKey: .corner),
            selectedTaskListID: try container.decodeIfPresent(
                String.self,
                forKey: .selectedTaskListID
            ),
            screenIdentifier: try container.decodeIfPresent(
                String.self,
                forKey: .screenIdentifier
            ),
            opacity: try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
            maximumVisibleTaskCount: try container.decodeIfPresent(
                Int.self,
                forKey: .maximumVisibleTaskCount
            ) ?? 10,
            placementMode: try container.decodeIfPresent(
                PlacementMode.self,
                forKey: .placementMode
            ) ?? .anchored,
            normalizedPosition: try container.decodeIfPresent(
                NormalizedPosition.self,
                forKey: .normalizedPosition
            ),
            expandedHeight: try container.decodeIfPresent(
                Double.self,
                forKey: .expandedHeight
            ) ?? Self.defaultExpandedHeight,
            priorityPalette: try container.decodeIfPresent(
                TaskPriorityPalette.self,
                forKey: .priorityPalette
            ) ?? .defaultValue
        )
    }

    static let defaultValue = TaskPanelState(
        isEnabled: false,
        displayMode: .expanded,
        corner: .topTrailing
    )

    static func validatedOpacity(_ opacity: Double) -> Double {
        min(max(opacity, 0.65), 1)
    }

    static func validatedMaximumVisibleTaskCount(_ count: Int) -> Int {
        min(max(count, 1), 25)
    }

    static func validatedExpandedHeight(_ height: Double) -> Double {
        min(max(height, 146), 4_000)
    }

    static func effectiveOpacity(
        _ opacity: Double,
        accessibilityRequiresOpaqueSurface: Bool
    ) -> Double {
        accessibilityRequiresOpaqueSurface ? 1 : validatedOpacity(opacity)
    }
}
