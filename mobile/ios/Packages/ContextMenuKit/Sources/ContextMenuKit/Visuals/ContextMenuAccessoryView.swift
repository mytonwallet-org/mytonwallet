import UIKit

@MainActor
final class ContextMenuAccessoryView: UIView {
    /// The thought bubble's timing, after Telegram's reaction cloud: its tail circles pop on a 0.4 s spring 0.04 s
    /// apart, and its body pops from a circle at the tail's end and stretches to its width on a 0.35 s spring
    private enum ThoughtBubbleMotion {
        static let tailStagger: TimeInterval = 0.04
        static let tailDuration: TimeInterval = 0.4
        static let tailDamping: CGFloat = 0.6
        static let bodyPopDuration: TimeInterval = 0.3
        static let bodyPopDamping: CGFloat = 0.7
        static let bodyStretchDuration: TimeInterval = 0.35
        static let bodyStretchDamping: CGFloat = 0.75
        static let collapsedScale: CGFloat = 0.01
        static let fadeDuration: TimeInterval = 0.2
        static let disappearDuration: TimeInterval = 0.18
    }

    private let capsules: [CGRect]
    private let tailCapsuleIndices: Set<Int>
    let motion: ContextMenuAccessoryMotion
    /// The accessory's own size, which `bounds` exceeds by how far the body slid
    private let designSize: CGSize
    // Native glass merges the capsules that overlap into one shape, while the ones apart stay apart
    private let glassContainer = ContextMenuGlassContainerView(spacing: 0.0)
    private let backgroundViews: [ContextMenuGlassBackgroundView]
    private let glassTint: ContextMenuGlassTint
    private let shadow: ContextMenuAccessoryShadow?
    /// Draws `shadow` around native glass, cut out where the glass is, which would show it through
    private let shadowView = UIView()
    private let shadowMaskLayer = CAShapeLayer()
    private let isRightToLeft: Bool
    let contentView: UIView
    /// The capsule whose glass holds the content and answers touches, when the glass is interactive
    private let interactiveCapsuleIndex: Int?
    /// While the thought bubble grows, the capsules' frames are its motion's rather than the layout's
    private var isRunningThoughtBubbleMotion = false

    /// How far the body and the tail moved from where the source puts them, negative to the left
    private(set) var bodyOffset: CGFloat = 0.0
    private(set) var tailOffset: CGFloat = 0.0

    init(
        capsules: [CGRect],
        tailCapsuleIndices: Set<Int> = [],
        designSize: CGSize,
        motion: ContextMenuAccessoryMotion = .scale,
        contentView: UIView,
        glassTint: ContextMenuGlassTint,
        shadow: ContextMenuAccessoryShadow? = nil,
        isGlassInteractive: Bool = false,
        sourceUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection
    ) {
        self.capsules = capsules
        self.tailCapsuleIndices = tailCapsuleIndices
        self.designSize = designSize
        self.motion = motion
        self.shadow = shadow
        self.interactiveCapsuleIndex = isGlassInteractive && ContextMenuVisuals.supportsNativeGlass && !capsules.isEmpty ? 0 : nil
        // The pre-glass material is one view cut to the capsules' union, so overlapping capsules are not tinted twice
        self.backgroundViews = ContextMenuVisuals.supportsNativeGlass || capsules.isEmpty
            ? capsules.map { _ in ContextMenuGlassBackgroundView() }
            : [ContextMenuGlassBackgroundView()]
        self.glassTint = glassTint
        self.isRightToLeft = sourceUserInterfaceLayoutDirection.contextMenuIsRightToLeft
        self.contentView = contentView

        super.init(frame: .zero)

        self.semanticContentAttribute = sourceUserInterfaceLayoutDirection.contextMenuSemanticContentAttribute
        // The accessory grows from and shrinks into its bottom edge, the one over the source
        self.layer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        if shadow != nil, ContextMenuVisuals.supportsNativeGlass {
            self.shadowView.isUserInteractionEnabled = false
            self.shadowMaskLayer.fillRule = .evenOdd
            self.shadowView.layer.mask = self.shadowMaskLayer
            self.addSubview(self.shadowView)
        }
        self.glassContainer.isUserInteractionEnabled = self.interactiveCapsuleIndex != nil
        self.addSubview(self.glassContainer)
        // The capsule that holds the content goes over the others, so that the tail is its background and never drawn
        // over the content
        let interactiveIndex = self.interactiveCapsuleIndex
        let stackOrder = self.backgroundViews.indices.filter { $0 != interactiveIndex }
            + self.backgroundViews.indices.filter { $0 == interactiveIndex }
        for index in stackOrder {
            let backgroundView = self.backgroundViews[index]
            backgroundView.isUserInteractionEnabled = index == self.interactiveCapsuleIndex
            self.glassContainer.contentView.addSubview(backgroundView)
        }
        if let index = self.interactiveCapsuleIndex {
            // Inside the glass the content moves with it as it stretches, and its touches reach the glass too
            self.backgroundViews[index].contentView.addSubview(contentView)
            if shadow != nil {
                let touchObserver = ContextMenuTouchObserver { [weak self] isTouching in
                    self?.setGlassTouched(isTouching)
                }
                self.addGestureRecognizer(touchObserver)
            }
        } else {
            self.addSubview(contentView)
        }
    }

    // MARK: - Touches

    /// How long the glass takes to settle back into place once the finger lets go, before the shadow returns
    private static let glassSettleDuration: TimeInterval = 0.35
    private static let shadowFadeDuration: TimeInterval = 0.2
    /// While a finger is on the interactive glass, which then swells and stretches toward it, the shadow fades out:
    /// it stays where the capsules rest, cut out where they rest, so it would leave their resting shape uncovered
    private var isGlassTouched = false
    private var glassTouchID = 0

    private func setGlassTouched(_ isTouching: Bool) {
        self.glassTouchID += 1
        let touchID = self.glassTouchID
        guard isTouching else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.glassSettleDuration) { [weak self] in
                guard let self, self.glassTouchID == touchID else {
                    return
                }
                self.isGlassTouched = false
                self.fadeShadow()
            }
            return
        }
        guard !self.isGlassTouched else {
            return
        }
        self.isGlassTouched = true
        self.fadeShadow()
    }

    /// Fades the shadow to its opacity for the glass's touch, from where it shows
    private func fadeShadow() {
        guard let shadow else {
            return
        }
        let layer = self.shadowView.layer
        let opacity = self.getShadowOpacity(shadow)
        let fade = CABasicAnimation(keyPath: "shadowOpacity")
        fade.fromValue = layer.presentation()?.shadowOpacity ?? layer.shadowOpacity
        fade.toValue = opacity
        fade.duration = Self.shadowFadeDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.shadowOpacity = opacity
        layer.add(fade, forKey: "shadowOpacity")
    }

    private func getShadowOpacity(_ shadow: ContextMenuAccessoryShadow) -> Float {
        if self.isGlassTouched {
            return 0.0
        }
        return self.traitCollection.userInterfaceStyle == .dark ? shadow.darkOpacity : shadow.lightOpacity
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Places the body and the tail as `placement` does; `bounds` spans both
    func apply(_ placement: ContextMenuAccessoryPlacement) {
        guard placement.bodyOffset != self.bodyOffset || placement.tailOffset != self.tailOffset else {
            return
        }
        self.bodyOffset = placement.bodyOffset
        self.tailOffset = placement.tailOffset
        self.setNeedsLayout()
    }

    /// Where the tail's and the body's design frames start in `bounds`
    private var tailOriginX: CGFloat { self.tailOffset - min(self.tailOffset, self.bodyOffset) }
    private var bodyOriginX: CGFloat { self.bodyOffset - min(self.tailOffset, self.bodyOffset) }

    /// The capsules' frames in `bounds`: the tail's where the accessory stands, the others where the body slid to
    private var capsuleFrames: [CGRect] {
        self.capsules.enumerated().map { index, capsule in
            let mirrored = self.isRightToLeft
                ? CGRect(x: self.designSize.width - capsule.maxX, y: capsule.minY, width: capsule.width, height: capsule.height)
                : capsule
            let originX = self.tailCapsuleIndices.contains(index) ? self.tailOriginX : self.bodyOriginX
            return mirrored.offsetBy(dx: originX, dy: 0.0)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let capsuleFrames = self.capsuleFrames
        self.glassContainer.update(size: self.bounds.size)
        let contentFrame = CGRect(origin: CGPoint(x: self.bodyOriginX, y: 0.0), size: self.designSize)
        if let index = self.interactiveCapsuleIndex {
            if !self.isRunningThoughtBubbleMotion {
                let capsule = capsuleFrames[index]
                self.contentView.frame = contentFrame.offsetBy(dx: -capsule.minX, dy: -capsule.minY)
            }
        } else {
            self.contentView.frame = contentFrame
        }

        // Native glass draws its own depth, as it does for the menu panel, under an accessory's own shadow
        if ContextMenuVisuals.supportsNativeGlass {
            self.layoutShadow(around: capsuleFrames)
            guard !self.isRunningThoughtBubbleMotion else {
                return
            }
            for index in self.backgroundViews.indices {
                self.applyCapsuleFrame(capsuleFrames[index], at: index)
            }
            self.layer.shadowOpacity = 0.0
            self.layer.shadowPath = nil
            return
        }

        let shape = Self.makeUnionShape(of: capsuleFrames)
        for backgroundView in self.backgroundViews {
            backgroundView.frame = self.bounds
            backgroundView.update(
                size: self.bounds.size,
                cornerRadius: 0.0,
                legacyShape: shape,
                traits: self.traitCollection,
                isInteractive: false,
                glassTint: self.glassTint
            )
        }
        // The pre-glass material and its shadow are the menu panel's
        ContextMenuVisuals.applyLegacyPanelShadow(to: self.layer, path: shape, traits: self.traitCollection)
    }

    /// Puts the native glass capsule at `index` in `frame`, keeping the content where the accessory has it. The frame
    /// goes through the bounds and the center, which keep the capsule's motion transform out of it.
    private func applyCapsuleFrame(_ frame: CGRect, at index: Int) {
        let backgroundView = self.backgroundViews[index]
        backgroundView.bounds = CGRect(origin: .zero, size: frame.size)
        backgroundView.center = CGPoint(x: frame.midX, y: frame.midY)
        backgroundView.update(
            size: frame.size,
            cornerRadius: Self.cornerRadius(of: frame),
            traits: self.traitCollection,
            isInteractive: index == self.interactiveCapsuleIndex,
            glassTint: self.glassTint
        )
        if index == self.interactiveCapsuleIndex {
            let contentFrame = CGRect(origin: CGPoint(x: self.bodyOriginX, y: 0.0), size: self.designSize)
            self.contentView.frame = contentFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        }
    }

    // MARK: - Thought bubble

    /// The thought bubble's appearance: the tail pops in from its smallest circle, then the body grows out of a
    /// circle at its tail's end, and the content shows its parts as the body reaches them
    func animateThoughtBubbleIn() {
        let isReduced = UIAccessibility.isReduceMotionEnabled
        self.layoutIfNeeded()
        let tailOrder = self.tailCapsuleIndices.sorted { self.capsules[$0].width * self.capsules[$0].height < self.capsules[$1].width * self.capsules[$1].height }
        let bodyDelay = isReduced ? 0.0 : ThoughtBubbleMotion.tailStagger * TimeInterval(tailOrder.count)
        let bodyIndices = self.capsules.indices.filter { !self.tailCapsuleIndices.contains($0) }
        let finalFrames = self.capsuleFrames
        let bodyFrame = bodyIndices.map { finalFrames[$0] }.reduce(nil as CGRect?) { $0?.union($1) ?? $1 }

        if let animating = self.contentView as? ContextMenuAccessoryAnimating, let bodyFrame {
            // The body grows from its first circle's far edge toward its leading end, in the content's coordinates
            let startCircle = self.getStartCircle(of: bodyFrame)
            animating.animateAccessoryAppearance(ContextMenuAccessoryAppearance(
                isReduced: isReduced,
                bodyDelay: bodyDelay,
                growthStartX: (self.isRightToLeft ? startCircle.maxX : startCircle.minX) - self.bodyOriginX,
                growthEndX: (self.isRightToLeft ? bodyFrame.maxX : bodyFrame.minX) - self.bodyOriginX
            ))
        }

        guard !isReduced, ContextMenuVisuals.supportsNativeGlass else {
            self.layer.addContextMenuAlphaAnimation(from: 0.0, to: 1.0, duration: ThoughtBubbleMotion.fadeDuration)
            if !isReduced {
                // The pre-glass material is one shape, which grows out of the tail as a whole
                self.layer.addContextMenuSpringAnimation(
                    keyPath: "transform",
                    from: NSValue(caTransform3D: self.getScaleTowardTail(ThoughtBubbleMotion.collapsedScale)),
                    to: NSValue(caTransform3D: CATransform3DIdentity),
                    duration: ContextMenuAnimationSupport.appearDuration,
                    damping: ContextMenuAnimationSupport.appearDamping,
                    additive: false
                )
            }
            return
        }

        self.isRunningThoughtBubbleMotion = true
        self.shadowView.alpha = 0.0
        for (order, index) in tailOrder.enumerated() {
            let backgroundView = self.backgroundViews[index]
            backgroundView.transform = CGAffineTransform(
                scaleX: ThoughtBubbleMotion.collapsedScale,
                y: ThoughtBubbleMotion.collapsedScale
            )
            UIView.animate(
                withDuration: ThoughtBubbleMotion.tailDuration,
                delay: ThoughtBubbleMotion.tailStagger * TimeInterval(order),
                usingSpringWithDamping: ThoughtBubbleMotion.tailDamping,
                initialSpringVelocity: 0.0,
                options: [.allowUserInteraction]
            ) {
                backgroundView.transform = .identity
            }
        }
        for index in bodyIndices {
            self.applyCapsuleFrame(self.getStartCircle(of: finalFrames[index]), at: index)
            self.backgroundViews[index].isHidden = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + bodyDelay) { [weak self] in
            self?.growBody(indices: bodyIndices, to: finalFrames)
        }
    }

    private func growBody(indices: [Int], to finalFrames: [CGRect]) {
        for index in indices {
            let backgroundView = self.backgroundViews[index]
            backgroundView.isHidden = false
            backgroundView.transform = CGAffineTransform(
                scaleX: ThoughtBubbleMotion.collapsedScale,
                y: ThoughtBubbleMotion.collapsedScale
            )
            UIView.animate(
                withDuration: ThoughtBubbleMotion.bodyPopDuration,
                delay: 0.0,
                usingSpringWithDamping: ThoughtBubbleMotion.bodyPopDamping,
                initialSpringVelocity: 0.0,
                options: [.allowUserInteraction]
            ) {
                backgroundView.transform = .identity
            }
            UIView.animate(
                withDuration: ThoughtBubbleMotion.bodyStretchDuration,
                delay: 0.0,
                usingSpringWithDamping: ThoughtBubbleMotion.bodyStretchDamping,
                initialSpringVelocity: 0.0,
                options: [.allowUserInteraction]
            ) {
                self.applyCapsuleFrame(finalFrames[index], at: index)
            } completion: { _ in
                self.isRunningThoughtBubbleMotion = false
                self.setNeedsLayout()
            }
        }
        UIView.animate(
            withDuration: ThoughtBubbleMotion.fadeDuration,
            delay: ThoughtBubbleMotion.bodyStretchDuration * 0.5,
            options: [.allowUserInteraction]
        ) {
            self.shadowView.alpha = 1.0
        }
    }

    /// The thought bubble's disappearance: its body shrinks back into the circle at its tail's end and the whole of it
    /// toward the tail, fading as the menu does
    func animateThoughtBubbleOut() {
        self.layer.addContextMenuAlphaAnimation(
            from: 1.0,
            to: 0.0,
            duration: ThoughtBubbleMotion.disappearDuration,
            removeOnCompletion: false
        )
        guard !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        guard ContextMenuVisuals.supportsNativeGlass else {
            self.layer.addContextMenuBasicAnimation(
                keyPath: "transform",
                from: NSValue(caTransform3D: CATransform3DIdentity),
                to: NSValue(caTransform3D: self.getScaleTowardTail(0.5)),
                duration: ThoughtBubbleMotion.disappearDuration,
                timingFunction: .easeIn,
                removeOnCompletion: false
            )
            return
        }
        self.isRunningThoughtBubbleMotion = true
        let frames = self.capsuleFrames
        UIView.animate(
            withDuration: ThoughtBubbleMotion.disappearDuration,
            delay: 0.0,
            options: [.beginFromCurrentState, .curveEaseIn]
        ) {
            self.shadowView.alpha = 0.0
            for index in self.backgroundViews.indices {
                if self.tailCapsuleIndices.contains(index) {
                    self.backgroundViews[index].transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                } else {
                    self.applyCapsuleFrame(self.getStartCircle(of: frames[index]), at: index)
                    self.backgroundViews[index].transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                }
            }
        }
    }

    /// A scale by `scale` toward the tail's smallest capsule, about the layer's anchor at its bottom middle
    private func getScaleTowardTail(_ scale: CGFloat) -> CATransform3D {
        let tail = self.tailCapsuleIndices
            .map { self.capsuleFrames[$0] }
            .min { $0.width * $0.height < $1.width * $1.height }
        let center = tail.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: self.bounds.midX, y: self.bounds.maxY)
        let offset = CGPoint(x: center.x - self.bounds.midX, y: center.y - self.bounds.maxY)
        var transform = CATransform3DMakeScale(scale, scale, 1.0)
        transform.m41 = offset.x * (1.0 - scale)
        transform.m42 = offset.y * (1.0 - scale)
        return transform
    }

    /// The circle at the end of `frame` that its tail is on, the trailing end
    private func getStartCircle(of frame: CGRect) -> CGRect {
        let side = min(frame.width, frame.height)
        return CGRect(
            x: self.isRightToLeft ? frame.minX : frame.maxX - side,
            y: frame.minY,
            width: side,
            height: frame.height
        )
    }

    private func layoutShadow(around capsuleFrames: [CGRect]) {
        guard let shadow, self.shadowView.superview != nil, let shape = Self.makeUnionShape(of: capsuleFrames) else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.shadowView.frame = self.bounds
        let layer = self.shadowView.layer
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = self.getShadowOpacity(shadow)
        layer.shadowRadius = shadow.radius
        layer.shadowOffset = shadow.offset
        layer.shadowPath = shape
        let reach = shadow.radius * 3 + max(abs(shadow.offset.width), abs(shadow.offset.height))
        let maskPath = CGMutablePath()
        maskPath.addRect(self.bounds.insetBy(dx: -reach, dy: -reach))
        maskPath.addPath(shape)
        self.shadowMaskLayer.frame = self.bounds
        self.shadowMaskLayer.path = maskPath
        CATransaction.commit()
    }

    private static func makeUnionShape(of capsuleFrames: [CGRect]) -> CGPath? {
        capsuleFrames
            .map { frame in
                let cornerRadius = Self.cornerRadius(of: frame)
                return CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            }
            .reduce(nil as CGPath?) { union, capsule in union?.union(capsule) ?? capsule }
    }

    private static func cornerRadius(of capsule: CGRect) -> CGFloat {
        min(capsule.width, capsule.height) * 0.5
    }
}
