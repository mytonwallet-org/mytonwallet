import UIKit

@MainActor
final class ContextMenuGlassBackgroundView: UIView {
    private let effectView = UIVisualEffectView(effect: nil)
    private let legacyTintView: UIView?
    private let legacyStrokeView: UIView?
    let contentView = UIView()

    override init(frame: CGRect) {
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

        super.init(frame: frame)

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

    func update(size: CGSize, cornerRadius: CGFloat, traits: UITraitCollection, isInteractive: Bool) {
        self.effectView.frame = CGRect(origin: .zero, size: size)
        self.effectView.overrideUserInterfaceStyle = traits.userInterfaceStyle
        self.effectView.layer.cornerRadius = cornerRadius
        self.contentView.frame = CGRect(origin: .zero, size: size)

        if #available(iOS 26.0, *) {
            self.effectView.effect = ContextMenuVisuals.nativePanelEffect(for: traits, interactive: isInteractive)
        } else {
            self.effectView.effect = ContextMenuVisuals.legacyPanelEffect()

            if let legacyTintView {
                legacyTintView.frame = self.effectView.contentView.bounds
                legacyTintView.backgroundColor = ContextMenuVisuals.legacyPanelTintColor(for: traits)
                legacyTintView.layer.cornerRadius = cornerRadius
                legacyTintView.layer.cornerCurve = .continuous
            }
            if let legacyStrokeView {
                legacyStrokeView.frame = self.effectView.contentView.bounds
                legacyStrokeView.layer.cornerRadius = cornerRadius
                legacyStrokeView.layer.borderWidth = 1.0 / max(traits.displayScale, 1.0)
                legacyStrokeView.layer.borderColor = ContextMenuVisuals.legacyPanelStrokeColor(for: traits).cgColor
            }
        }
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

    init(style: ContextMenuStyle) {
        if #available(iOS 26.0, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = style.containerSpacing
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

    func update(size: CGSize, traits: UITraitCollection) {
        self.frame = CGRect(origin: .zero, size: size)
        if let nativeEffectView {
            nativeEffectView.frame = self.bounds
            nativeEffectView.overrideUserInterfaceStyle = traits.userInterfaceStyle
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
        self.backgroundContainer = ContextMenuGlassContainerView(style: style)
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
        self.backgroundContainer.update(size: containerSize, traits: traits)
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
            isInteractive: true
        )
        self.contentView.frame = self.backgroundView.contentView.bounds

        if ContextMenuVisuals.supportsNativeGlass {
            self.layer.shadowOpacity = 0.0
            self.layer.shadowPath = nil
        } else {
            self.layer.shadowColor = UIColor.black.cgColor
            self.layer.shadowOpacity = traits.userInterfaceStyle == .dark ? 0.22 : 0.12
            self.layer.shadowRadius = 24.0
            self.layer.shadowOffset = CGSize(width: 0.0, height: 12.0)
            self.layer.shadowPath = UIBezierPath(
                roundedRect: self.backgroundView.frame,
                cornerRadius: panelCornerRadius
            ).cgPath
        }
    }
}
