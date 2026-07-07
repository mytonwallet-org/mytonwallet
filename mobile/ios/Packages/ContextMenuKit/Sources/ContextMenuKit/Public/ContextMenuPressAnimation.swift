import UIKit

public struct ContextMenuPressAnimation: Sendable {
    public enum TransformMode: Sendable {
        case sublayerTransform
        case transform
    }

    public var transformMode: TransformMode
    public var beginDelay: TimeInterval
    public var pressInDuration: TimeInterval
    public var releaseDuration: TimeInterval
    public var scaleInset: CGFloat
    public var minimumScale: CGFloat
    public var allowableMovement: CGFloat

    public init(
        transformMode: TransformMode = .sublayerTransform,
        beginDelay: TimeInterval = 0.12,
        pressInDuration: TimeInterval = 0.2,
        releaseDuration: TimeInterval = 0.2,
        scaleInset: CGFloat = 15.0,
        minimumScale: CGFloat = 0.7,
        allowableMovement: CGFloat = 10.0
    ) {
        self.transformMode = transformMode
        self.beginDelay = beginDelay
        self.pressInDuration = pressInDuration
        self.releaseDuration = releaseDuration
        self.scaleInset = scaleInset
        self.minimumScale = minimumScale
        self.allowableMovement = allowableMovement
    }

    public static func `default`(transformMode: TransformMode = .sublayerTransform) -> ContextMenuPressAnimation {
        ContextMenuPressAnimation(transformMode: transformMode)
    }
}
