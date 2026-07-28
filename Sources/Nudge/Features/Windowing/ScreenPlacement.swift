import CoreGraphics

enum ScreenPlacement {
    static func cornerFrame(
        contentSize: CGSize,
        in visibleFrame: CGRect,
        corner: ScreenCorner,
        edgeInset: CGFloat
    ) -> CGRect {
        let size = fittedSize(contentSize, in: visibleFrame)
        let horizontalInset = min(max(edgeInset, 0), max((visibleFrame.width - size.width) / 2, 0))
        let verticalInset = min(max(edgeInset, 0), max((visibleFrame.height - size.height) / 2, 0))

        let leadingX = visibleFrame.minX + horizontalInset
        let trailingX = visibleFrame.maxX - horizontalInset - size.width
        let bottomY = visibleFrame.minY + verticalInset
        let topY = visibleFrame.maxY - verticalInset - size.height

        switch corner {
        case .topLeading:
            return CGRect(origin: CGPoint(x: leadingX, y: topY), size: size)
        case .topTrailing:
            return CGRect(origin: CGPoint(x: trailingX, y: topY), size: size)
        case .bottomLeading:
            return CGRect(origin: CGPoint(x: leadingX, y: bottomY), size: size)
        case .bottomTrailing:
            return CGRect(origin: CGPoint(x: trailingX, y: bottomY), size: size)
        }
    }

    static func customFrame(
        contentSize: CGSize,
        in visibleFrame: CGRect,
        normalizedPosition: TaskPanelState.NormalizedPosition,
        edgeInset: CGFloat
    ) -> CGRect {
        let bounds = placementBounds(in: visibleFrame, edgeInset: edgeInset)
        let size = fittedSize(contentSize, in: bounds)
        let horizontalTravel = max(bounds.width - size.width, 0)
        let verticalTravel = max(bounds.height - size.height, 0)
        return CGRect(
            origin: CGPoint(
                x: bounds.minX + horizontalTravel * normalizedPosition.x,
                y: bounds.minY + verticalTravel * normalizedPosition.y
            ),
            size: size
        )
    }

    static func normalizedPosition(
        for frame: CGRect,
        in visibleFrame: CGRect,
        edgeInset: CGFloat
    ) -> TaskPanelState.NormalizedPosition {
        let bounds = placementBounds(in: visibleFrame, edgeInset: edgeInset)
        let horizontalTravel = max(bounds.width - frame.width, 0)
        let verticalTravel = max(bounds.height - frame.height, 0)
        let x = horizontalTravel > 0 ? (frame.minX - bounds.minX) / horizontalTravel : 0
        let y = verticalTravel > 0 ? (frame.minY - bounds.minY) / verticalTravel : 0
        return TaskPanelState.NormalizedPosition(x: x, y: y)
    }

    /// Upper-center resting place for the reminder control strip, always inside the visible frame
    /// so the menu bar and the Dock are never covered.
    static func reminderStripFrame(
        contentSize: CGSize,
        in visibleFrame: CGRect,
        topInset: CGFloat,
        horizontalInset: CGFloat
    ) -> CGRect {
        let requestedInset = max(horizontalInset, 0)
        let availableFrame = visibleFrame.insetBy(
            dx: min(requestedInset, visibleFrame.width / 2),
            dy: 0
        )
        let size = fittedSize(contentSize, in: availableFrame)
        let verticalInset = min(max(topInset, 0), max(visibleFrame.height - size.height, 0))
        let centeredX = visibleFrame.midX - size.width / 2
        let minimumX = visibleFrame.minX + min(requestedInset, visibleFrame.width - size.width)
        let maximumX = visibleFrame.maxX - min(requestedInset, visibleFrame.width - size.width)
            - size.width
        return CGRect(
            origin: CGPoint(
                x: min(max(centeredX, minimumX), maximumX),
                y: visibleFrame.maxY - verticalInset - size.height
            ),
            size: size
        )
    }

    private static func fittedSize(_ contentSize: CGSize, in visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: min(max(contentSize.width, 0), max(visibleFrame.width, 0)),
            height: min(max(contentSize.height, 0), max(visibleFrame.height, 0))
        )
    }

    private static func placementBounds(in visibleFrame: CGRect, edgeInset: CGFloat) -> CGRect {
        let horizontalInset = min(max(edgeInset, 0), visibleFrame.width / 2)
        let verticalInset = min(max(edgeInset, 0), visibleFrame.height / 2)
        return visibleFrame.insetBy(dx: horizontalInset, dy: verticalInset)
    }
}
