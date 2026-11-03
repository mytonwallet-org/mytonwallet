import UIKit

@MainActor
final class ContextMenuAccessoryView: UIView {
    private static let legacyShadowRadius: CGFloat = 12.0
    private static let legacyShadowOffset = CGSize(width: 0.0, height: 4.0)

    private let capsules: [CGRect]
    // Native glass merges the capsules that overlap into one shape, while the ones apart stay apart
    private let glassContainer = ContextMenuGlassContainerView(spacing: 0.0)
    private let backgroundViews: [ContextMenuGlassBackgroundView]
    private let glassTint: ContextMenuGlassTint
    private let shadow: ContextMenuAccessoryShadow?
    /// Draws `shadow` around native glass, cut out where the glass is, which would show it through
    private let shadowView = UIView()
    private let shadowMaskLayer = CAShapeLayer()
    private let isRightToLeft: Bool
    private let contentView: UIView
    /// The capsule whose glass holds the content and answers touches, when the glass is interactive
    private let interactiveCapsuleIndex: Int?

    init(
        capsules: [CGRect],
        contentView: UIView,
        glassTint: ContextMenuGlassTint,
        shadow: ContextMenuAccessoryShadow? = nil,
        isGlassInteractive: Bool = false,
        sourceUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection
    ) {
        self.capsules = capsules
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
        for (index, backgroundView) in self.backgroundViews.enumerated() {
            backgroundView.isUserInteractionEnabled = index == self.interactiveCapsuleIndex
            self.glassContainer.contentView.addSubview(backgroundView)
        }
        if let index = self.interactiveCapsuleIndex {
            // Inside the glass the content moves with it as it stretches, and its touches reach the glass too
            self.backgroundViews[index].contentView.addSubview(contentView)
        } else {
            self.addSubview(contentView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let capsuleFrames = self.capsules.map { capsule in
            self.isRightToLeft
                ? CGRect(x: self.bounds.width - capsule.maxX, y: capsule.minY, width: capsule.width, height: capsule.height)
                : capsule
        }
        self.glassContainer.update(size: self.bounds.size)
        if let index = self.interactiveCapsuleIndex {
            let capsule = capsuleFrames[index]
            self.contentView.frame = self.bounds.offsetBy(dx: -capsule.minX, dy: -capsule.minY)
        } else {
            self.contentView.frame = self.bounds
        }

        // Native glass draws its own depth, as it does for the menu panel, under an accessory's own shadow
        if ContextMenuVisuals.supportsNativeGlass {
            self.layoutShadow(around: capsuleFrames)
            for (index, (frame, backgroundView)) in zip(capsuleFrames, self.backgroundViews).enumerated() {
                backgroundView.frame = frame
                backgroundView.update(
                    size: frame.size,
                    cornerRadius: Self.cornerRadius(of: frame),
                    traits: self.traitCollection,
                    isInteractive: index == self.interactiveCapsuleIndex,
                    glassTint: self.glassTint
                )
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
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = self.traitCollection.userInterfaceStyle == .dark ? 0.22 : 0.12
        self.layer.shadowRadius = Self.legacyShadowRadius
        self.layer.shadowOffset = Self.legacyShadowOffset
        self.layer.shadowPath = shape
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
        layer.shadowOpacity = self.traitCollection.userInterfaceStyle == .dark ? shadow.darkOpacity : shadow.lightOpacity
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
