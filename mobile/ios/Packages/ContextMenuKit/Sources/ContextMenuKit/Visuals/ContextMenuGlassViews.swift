import UIKit

@MainActor
final class ContextMenuGlassBackgroundView: UIView {
    private let effectView = UIVisualEffectView(effect: nil)
    private let legacyTintView: UIView?
    private let legacyStrokeView: UIView?
    private var legacyShapeMaskView: ContextMenuShapeView?
    private var legacyShapeStrokeLayer: CAShapeLayer?
    let contentView = UIView()

    init() {
        if ContextMenuVisuals.supportsNativeGlass {
            self.legacyTintView = nil
            self.legacyStrokeView = nil
        } else {
            let legacyTintView = UIView()
            legacyTintView.isUserInteractionEnabled = false
            self.legacyTintView = legacyTintView

            let legacyStrokeView = UIView()
            legacyStrokeView.isUserInteractionEnabled = false
            legacyStrokeView.layer.cornerCurve = .continuous
            self.legacyStrokeView = legacyStrokeView
        }

        super.init(frame: .zero)

        self.effectView.clipsToBounds = true
        self.effectView.layer.cornerCurve = .continuous
        self.addSubview(self.effectView)
        if let legacyTintView {
            self.effectView.contentView.addSubview(legacyTintView)
        }
        self.effectView.contentView.addSubview(self.contentView)
        if let legacyStrokeView {
            self.effectView.contentView.addSubview(legacyStrokeView)
        }
        self.contentView.clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `legacyShape`, in the view's coordinates, cuts the pre-glass material to a path other than a rounded rect, such as
    /// the union of overlapping capsules. Native glass merges overlapping shapes in a `ContextMenuGlassContainerView`
    /// instead and ignores it.
    func update(
        size: CGSize,
        cornerRadius: CGFloat,
        legacyShape: CGPath? = nil,
        traits: UITraitCollection,
        isInteractive: Bool,
        glassTint: ContextMenuGlassTint
    ) {
        self.effectView.frame = CGRect(origin: .zero, size: size)
        self.effectView.layer.cornerRadius = cornerRadius
        self.contentView.frame = CGRect(origin: .zero, size: size)

        if #available(iOS 26.0, *) {
            self.effectView.effect = ContextMenuVisuals.nativePanelEffect(
                for: traits,
                interactive: isInteractive,
                tint: glassTint
            )
        } else {
            self.effectView.effect = ContextMenuVisuals.legacyPanelEffect(for: traits)

            if let legacyTintView {
                legacyTintView.frame = self.effectView.contentView.bounds
                legacyTintView.backgroundColor = ContextMenuVisuals.legacyPanelTintColor(for: traits)
                legacyTintView.layer.cornerRadius = cornerRadius
                legacyTintView.layer.cornerCurve = .continuous
            }
            if let legacyStrokeView {
                legacyStrokeView.frame = self.effectView.contentView.bounds
                legacyStrokeView.layer.cornerRadius = cornerRadius
                legacyStrokeView.layer.borderWidth = legacyShape == nil ? 1.0 / max(traits.displayScale, 1.0) : 0.0
                legacyStrokeView.layer.borderColor = ContextMenuVisuals.legacyPanelStrokeColor(for: traits).cgColor
            }
            self.updateLegacyShape(legacyShape, traits: traits)
        }
    }

    private func updateLegacyShape(_ shape: CGPath?, traits: UITraitCollection) {
        guard let shape, let legacyStrokeView else {
            self.effectView.mask = nil
            self.legacyShapeStrokeLayer?.path = nil
            return
        }

        let maskView = self.legacyShapeMaskView ?? ContextMenuShapeView()
        maskView.frame = self.effectView.bounds
        maskView.shapeLayer.path = shape
        self.legacyShapeMaskView = maskView
        self.effectView.mask = maskView

        let strokeLayer = self.legacyShapeStrokeLayer ?? CAShapeLayer()
        if strokeLayer.superlayer == nil {
            strokeLayer.fillColor = nil
            legacyStrokeView.layer.addSublayer(strokeLayer)
        }
        strokeLayer.frame = legacyStrokeView.bounds
        strokeLayer.path = shape
        strokeLayer.strokeColor = ContextMenuVisuals.legacyPanelStrokeColor(for: traits).cgColor
        // The mask clips the outer half of the line, leaving the hairline the border draws around a rounded rect
        strokeLayer.lineWidth = 2.0 / max(traits.displayScale, 1.0)
        self.legacyShapeStrokeLayer = strokeLayer
    }
}

/// A view drawn as a path, for a mask that is not a rounded rect
private final class ContextMenuShapeView: UIView {
    override class var layerClass: AnyClass {
        CAShapeLayer.self
    }

    var shapeLayer: CAShapeLayer {
        self.layer as! CAShapeLayer
    }
}

@MainActor
final class ContextMenuGlassContainerView: UIView {
    private let nativeEffectView: UIVisualEffectView?
    private let legacyContentView: UIView?

    var contentView: UIView {
        if let nativeEffectView {
            return nativeEffectView.contentView
        } else {
            return self.legacyContentView!
        }
    }

    /// Glass shapes closer than `spacing` merge into one
    init(spacing: CGFloat) {
        if #available(iOS 26.0, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = spacing
            self.nativeEffectView = UIVisualEffectView(effect: effect)
            self.legacyContentView = nil
        } else {
            self.nativeEffectView = nil
            self.legacyContentView = UIView()
        }

        super.init(frame: .zero)

        if let nativeEffectView {
            self.addSubview(nativeEffectView)
        }
        if let legacyContentView {
            self.addSubview(legacyContentView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(size: CGSize) {
        self.frame = CGRect(origin: .zero, size: size)
        if let nativeEffectView {
            nativeEffectView.frame = self.bounds
        } else if let legacyContentView {
            legacyContentView.frame = self.bounds
        }
    }
}

@MainActor
final class ContextMenuPanelView: UIView {
    private let style: ContextMenuStyle
    private let backgroundContainer: ContextMenuGlassContainerView
    private let backgroundView: ContextMenuGlassBackgroundView
    let contentView = UIView()

    init(style: ContextMenuStyle) {
        self.style = style
        self.backgroundContainer = ContextMenuGlassContainerView(spacing: style.containerSpacing)
        self.backgroundView = ContextMenuGlassBackgroundView()

        super.init(frame: .zero)

        self.addSubview(self.backgroundContainer)
        self.backgroundContainer.contentView.addSubview(self.backgroundView)
        self.backgroundView.contentView.addSubview(self.contentView)
        self.contentView.clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyLayout(panelSize: CGSize, traits: UITraitCollection) {
        let containerSize = CGSize(
            width: panelSize.width + self.style.panelInset * 2.0,
            height: panelSize.height + self.style.panelInset * 2.0
        )
        let panelCornerRadius = min(self.style.panelCornerRadius, panelSize.height * 0.5)

        self.frame = CGRect(origin: .zero, size: containerSize)
        self.backgroundContainer.update(size: containerSize)
        self.backgroundView.frame = CGRect(
            x: self.style.panelInset,
            y: self.style.panelInset,
            width: panelSize.width,
            height: panelSize.height
        )
        self.backgroundView.update(
            size: panelSize,
            cornerRadius: panelCornerRadius,
            traits: traits,
            isInteractive: true,
            glassTint: self.style.glassTint
        )
        self.contentView.frame = self.backgroundView.contentView.bounds

        if ContextMenuVisuals.supportsNativeGlass {
            self.layer.shadowOpacity = 0.0
            self.layer.shadowPath = nil
        } else {
            ContextMenuVisuals.applyLegacyPanelShadow(
                to: self.layer,
                path: UIBezierPath(roundedRect: self.backgroundView.frame, cornerRadius: panelCornerRadius).cgPath,
                traits: traits
            )
        }
    }
}
