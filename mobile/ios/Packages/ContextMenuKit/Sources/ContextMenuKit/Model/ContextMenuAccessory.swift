import UIKit

public struct ContextMenuAccessoryContext {
    private let dismissHandler: @MainActor () -> Void

    init(dismissHandler: @escaping @MainActor () -> Void) {
        self.dismissHandler = dismissHandler
    }

    @MainActor
    public func dismiss() {
        self.dismissHandler()
    }
}

/// A view that the menu shows over its source's top edge, such as a row of reactions.
///
/// The overlay keeps the accessory inside the screen insets and the safe area, places the menu panel clear of the
/// source and the accessory, animates the accessory together with the panel and does not dismiss the menu on taps
/// inside it. Right-to-left layouts mirror its placement and `backgroundCapsules`.
public struct ContextMenuAccessory {
    public typealias ViewProvider = @MainActor (ContextMenuAccessoryContext) -> UIView

    public var size: CGSize
    /// The offset of the accessory's top trailing corner from the source's top trailing corner: a positive `dx`
    /// moves the accessory past the source's trailing edge, a positive `dy` moves it down
    public var topTrailingOffset: CGVector
    /// Rects of the accessory, measured from its leading edge, that the menu panel's material fills as capsules
    /// under the content view. Overlapping capsules merge into one shape.
    public var backgroundCapsules: [CGRect]
    /// The tint of the capsules' glass; nil takes the menu style's
    public var glassTint: ContextMenuGlassTint?
    /// A soft shadow around the capsules over native glass, which otherwise draws only its own depth
    public var shadow: ContextMenuAccessoryShadow?
    /// With native glass, the first capsule holds the content and answers touches as the menu panel's glass does: it
    /// swells under the finger and stretches toward it, carrying the content
    public var isGlassInteractive: Bool
    /// Makes the view that fills the accessory's bounds over its background
    public var makeContentView: ViewProvider

    public init(
        size: CGSize,
        topTrailingOffset: CGVector,
        backgroundCapsules: [CGRect],
        glassTint: ContextMenuGlassTint? = nil,
        shadow: ContextMenuAccessoryShadow? = nil,
        isGlassInteractive: Bool = false,
        makeContentView: @escaping ViewProvider
    ) {
        self.size = size
        self.topTrailingOffset = topTrailingOffset
        self.backgroundCapsules = backgroundCapsules
        self.glassTint = glassTint
        self.shadow = shadow
        self.isGlassInteractive = isGlassInteractive
        self.makeContentView = makeContentView
    }
}

/// A black shadow around an accessory's capsules, as a design's drop shadow describes it
public struct ContextMenuAccessoryShadow: Equatable, Sendable {
    public var lightOpacity: Float
    public var darkOpacity: Float
    /// The blur's standard deviation, as `CALayer.shadowRadius` takes it
    public var radius: CGFloat
    public var offset: CGSize

    public init(lightOpacity: Float, darkOpacity: Float, radius: CGFloat, offset: CGSize) {
        self.lightOpacity = lightOpacity
        self.darkOpacity = darkOpacity
        self.radius = radius
        self.offset = offset
    }
}
