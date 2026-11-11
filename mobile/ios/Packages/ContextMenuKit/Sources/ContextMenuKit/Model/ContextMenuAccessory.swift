import UIKit

public struct ContextMenuAccessoryContext {
    private let dismissHandler: @MainActor ((@MainActor () -> Void)?) -> Void
    private let sourceFrameHandler: @MainActor (CGRect) -> CGRect?

    init(
        dismissHandler: @escaping @MainActor ((@MainActor () -> Void)?) -> Void,
        sourceFrameHandler: @escaping @MainActor (CGRect) -> CGRect? = { _ in nil }
    ) {
        self.dismissHandler = dismissHandler
        self.sourceFrameHandler = sourceFrameHandler
    }

    /// Where `rect`, in the coordinates of the menu's portal source, shows on screen at the moment, in the window's
    /// coordinates: on the source's replica, wherever the replica stands as it moves into view and back. Nil without a
    /// replica, and once the menu is gone and the source shows again in its own place.
    @MainActor
    public func getSourceFrameOnScreen(_ rect: CGRect) -> CGRect? {
        self.sourceFrameHandler(rect)
    }

    @MainActor
    public func dismiss() {
        self.dismissHandler(nil)
    }

    /// Closes the menu and calls `completion` once it is gone and its source shows again
    @MainActor
    public func dismiss(completion: @escaping @MainActor () -> Void) {
        self.dismissHandler(completion)
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
    /// The capsules that stay at the source while the rest slides inside the screen; nil keeps the whole accessory
    /// inside the screen insets and the safe area
    public var tail: ContextMenuAccessoryTail?
    public var motion: ContextMenuAccessoryMotion
    /// The tint of the capsules' glass; nil takes the menu style's
    public var glassTint: ContextMenuGlassTint?
    /// A soft shadow around the capsules over native glass, which otherwise draws only its own depth
    public var shadow: ContextMenuAccessoryShadow?
    /// With native glass, the first capsule holds the content and answers touches as the menu panel's glass does: it
    /// swells under the finger and stretches toward it, carrying the content
    public var isGlassInteractive: Bool
    /// Makes the view that fills the accessory's bounds over its background. A view that conforms to
    /// `ContextMenuAccessoryAnimating` animates its parts as the accessory appears.
    public var makeContentView: ViewProvider

    public init(
        size: CGSize,
        topTrailingOffset: CGVector,
        backgroundCapsules: [CGRect],
        tail: ContextMenuAccessoryTail? = nil,
        motion: ContextMenuAccessoryMotion = .scale,
        glassTint: ContextMenuGlassTint? = nil,
        shadow: ContextMenuAccessoryShadow? = nil,
        isGlassInteractive: Bool = false,
        makeContentView: @escaping ViewProvider
    ) {
        self.size = size
        self.topTrailingOffset = topTrailingOffset
        self.backgroundCapsules = backgroundCapsules
        self.tail = tail
        self.motion = motion
        self.glassTint = glassTint
        self.shadow = shadow
        self.isGlassInteractive = isGlassInteractive
        self.makeContentView = makeContentView
    }

    /// Where the accessory stands over `sourceRect` between `minX` and `maxX`, the safe area's sides. Without a tail
    /// the whole accessory keeps `screenInsets` from them. With one, the other capsules and the content slide inward
    /// to keep the tail's `screenInset` from them, and the tail stays at the source. A tail that would then come
    /// nearer the sides than its `edgeSpacing`, or come off the capsules it hangs from, goes with them instead.
    public func getPlacement(
        sourceRect: CGRect,
        minX: CGFloat,
        maxX: CGFloat,
        screenInsets: UIEdgeInsets,
        isRightToLeft: Bool
    ) -> ContextMenuAccessoryPlacement {
        let x = isRightToLeft
            ? sourceRect.minX - self.topTrailingOffset.dx
            : sourceRect.maxX + self.topTrailingOffset.dx - self.size.width
        let y = sourceRect.minY + self.topTrailingOffset.dy
        guard let tail, let bodyRect = self.getBodyRect(isRightToLeft: isRightToLeft) else {
            let clampedX = min(max(x, minX + screenInsets.left), maxX - screenInsets.right - self.size.width)
            return ContextMenuAccessoryPlacement(
                frame: CGRect(x: clampedX, y: y, width: self.size.width, height: self.size.height),
                bodyOffset: 0.0,
                tailOffset: 0.0
            )
        }
        let bodyMinX = x + bodyRect.minX
        let bodyMaxX = x + bodyRect.maxX
        var bodyOffset: CGFloat = 0.0
        if bodyMaxX > maxX - tail.screenInset {
            bodyOffset = maxX - tail.screenInset - bodyMaxX
        }
        if bodyMinX + bodyOffset < minX + tail.screenInset {
            bodyOffset = minX + tail.screenInset - bodyMinX
        }
        let isTailAtSource = self.canKeepTailAtSource(
            x: x,
            bodyRect: bodyRect,
            bodyOffset: bodyOffset,
            minX: minX,
            maxX: maxX,
            isRightToLeft: isRightToLeft
        )
        let tailOffset = isTailAtSource ? 0.0 : bodyOffset
        // The frame spans the accessory where its tail is and its body where that slid to
        let frame = CGRect(x: x, y: y, width: self.size.width, height: self.size.height)
        return ContextMenuAccessoryPlacement(
            frame: frame.offsetBy(dx: tailOffset, dy: 0.0).union(frame.offsetBy(dx: bodyOffset, dy: 0.0)),
            bodyOffset: bodyOffset,
            tailOffset: tailOffset
        )
    }

    /// Whether the tail can stay at the source while the body stands `bodyOffset` from it: each of its capsules keeps
    /// the tail's `edgeSpacing` from the safe area's sides, and each one that overlaps the body keeps its centre over it
    private func canKeepTailAtSource(
        x: CGFloat,
        bodyRect: CGRect,
        bodyOffset: CGFloat,
        minX: CGFloat,
        maxX: CGFloat,
        isRightToLeft: Bool
    ) -> Bool {
        guard let tail else {
            return true
        }
        let bodyMinX = x + bodyRect.minX + bodyOffset
        let bodyMaxX = x + bodyRect.maxX + bodyOffset
        return tail.capsuleIndices.allSatisfy { index in
            guard self.backgroundCapsules.indices.contains(index) else {
                return true
            }
            let capsule = isRightToLeft ? self.mirror(self.backgroundCapsules[index]) : self.backgroundCapsules[index]
            let capsuleMinX = x + capsule.minX
            let capsuleMaxX = x + capsule.maxX
            guard capsuleMinX >= minX + tail.edgeSpacing, capsuleMaxX <= maxX - tail.edgeSpacing else {
                return false
            }
            guard capsule.intersects(bodyRect) else {
                return true
            }
            return (bodyMinX...bodyMaxX).contains(x + capsule.midX)
        }
    }

    /// The union of the capsules that are not the tail, measured from the accessory's left edge
    func getBodyRect(isRightToLeft: Bool) -> CGRect? {
        let tailIndices = Set(self.tail?.capsuleIndices ?? [])
        let body = self.backgroundCapsules.enumerated()
            .filter { !tailIndices.contains($0.offset) }
            .map { isRightToLeft ? self.mirror($0.element) : $0.element }
            .reduce(nil as CGRect?) { union, capsule in union?.union(capsule) ?? capsule }
        return body
    }

    func mirror(_ rect: CGRect) -> CGRect {
        CGRect(x: self.size.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

/// Where an accessory stands: its frame and how far its body and its tail moved from where the source puts them
public struct ContextMenuAccessoryPlacement: Equatable, Sendable {
    /// The accessory's frame, wide enough for its tail and its body where each of them stands
    public var frame: CGRect
    /// How far the capsules that are not the tail and the content moved sideways, negative to the left
    public var bodyOffset: CGFloat
    /// How far the tail moved sideways: none while it stays at the source, the body's offset when it goes with it
    public var tailOffset: CGFloat
}

/// A thought bubble's tail: capsules that stay over the source's corner while the rest of the accessory slides
/// inside the screen, as long as they keep clear of the screen's sides and on the capsules they hang from
public struct ContextMenuAccessoryTail: Equatable, Sendable {
    /// Indices of the accessory's `backgroundCapsules` that form the tail
    public var capsuleIndices: [Int]
    /// The least distance between the safe area's sides and the rest of the accessory
    public var screenInset: CGFloat
    /// The least distance between the safe area's sides and the tail at the source; nearer, it goes with the rest
    public var edgeSpacing: CGFloat

    public init(capsuleIndices: [Int], screenInset: CGFloat, edgeSpacing: CGFloat = 0.0) {
        self.capsuleIndices = capsuleIndices
        self.screenInset = screenInset
        self.edgeSpacing = edgeSpacing
    }
}

public enum ContextMenuAccessoryMotion: Equatable, Sendable {
    /// The accessory grows from its bottom edge with the panel and shrinks back into it
    case scale
    /// A thought bubble out of the source's corner, as Telegram's and iMessage's reaction clouds: the tail's capsules
    /// pop in from the smallest one, then the rest grows out of a circle at its trailing end, the tail's side. It
    /// shrinks back toward the tail as the menu closes. With Reduce Motion it fades in and out.
    case thoughtBubble
}

/// The timing of an accessory's appearance, for its content to show its parts as the body grows past them
public struct ContextMenuAccessoryAppearance: Sendable {
    /// How long after the appearance starts the body grows from one end to the other
    static let revealSpan: TimeInterval = 0.12

    /// Whether the accessory fades in, as with Reduce Motion, rather than moving
    public let isReduced: Bool
    /// When the body starts to grow, from the start of the appearance
    public let bodyDelay: TimeInterval
    /// The x in the content's coordinates that the body's first circle covers up to, from which it grows on
    let growthStartX: CGFloat
    /// The x in the content's coordinates where the growing body ends
    let growthEndX: CGFloat

    /// How long after the start of the appearance the growing body reaches `x` of the content
    public func getRevealDelay(forX x: CGFloat) -> TimeInterval {
        guard !self.isReduced else {
            return 0.0
        }
        let distance = self.growthEndX - self.growthStartX
        guard abs(distance) > 0.5 else {
            return self.bodyDelay
        }
        let fraction = min(max((x - self.growthStartX) / distance, 0.0), 1.0)
        return self.bodyDelay + Self.revealSpan * TimeInterval(fraction)
    }
}

/// The content of an accessory that shows its own parts with the accessory's motion
@MainActor
public protocol ContextMenuAccessoryAnimating: UIView {
    func animateAccessoryAppearance(_ appearance: ContextMenuAccessoryAppearance)
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
