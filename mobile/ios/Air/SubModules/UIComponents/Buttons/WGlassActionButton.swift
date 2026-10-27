import UIKit
import WalletContext

@available(iOS 26, *)
public final class WGlassActionButton: UIButton, ButtonsToolbarItem {
    private static let iconSize = CGSize(width: 26, height: 26)
    private let baseFont = WTypography.uiFont(.footnoteEmphasized)
    private var configuredTitleFont: UIFont?

    public init(title: String, image: UIImage?, onTap: (() -> Void)? = nil) {
        super.init(frame: .zero)

        var config = UIButton.Configuration.clearGlass()
        config.title = title
        if let image {
            config.image = image.isSymbolImage || image.size != Self.iconSize
                ? image.resizedToFit(size: Self.iconSize).withRenderingMode(image.renderingMode)
                : image
        }
        config.imagePlacement = .top
        config.imagePadding = 4
        config.contentInsets = .init(top: 9, leading: 8, bottom: 9, trailing: 8)
        config.cornerStyle = .fixed
        config.background.cornerRadius = WScalableButton.preferredCornerRadius
        config.titleLineBreakMode = .byTruncatingTail
        configuration = config
        setTitleFont(baseFont)

        translatesAutoresizingMaskIntoConstraints = false
        accessibilityLabel = title
        if let onTap {
            addAction(UIAction { _ in onTap() }, for: .touchUpInside)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var menuReturnDisplayLink: CADisplayLink?
    private var menuReturnOrigin: CGPoint?
    private var menuReturnGeneration = 0

    public override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                                willEndFor configuration: UIContextMenuConfiguration,
                                                animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        stopTrackingMenuReturn()
        guard let animator, let window else { return }
        menuReturnGeneration += 1
        let generation = menuReturnGeneration
        menuReturnOrigin = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
        let link = CADisplayLink(target: MenuReturnTarget(button: self), selector: #selector(MenuReturnTarget.tick))
        link.add(to: .main, forMode: .common)
        menuReturnDisplayLink = link
        animator.addCompletion { [weak self] in
            guard let self, menuReturnGeneration == generation else { return }
            stopTrackingMenuReturn()
        }
    }

    fileprivate func updateMenuReturn() {
        guard let window, let origin = menuReturnOrigin else {
            stopTrackingMenuReturn()
            return
        }
        let position = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
        guard hypot(position.x - origin.x, position.y - origin.y) > 0.5 else { return }
        stopTrackingMenuReturn()
        // UIKit keeps the lifted glass in a return spring after the menu closes.
        // That spring chases a moving scroll-view source. End only this transient
        // presentation when the source moves; at rest the native morph completes.
        // Reapplying the public configuration releases the lifted background and
        // renders the same glass in the button's own hierarchy in this frame.
        let saved = configuration
        UIView.performWithoutAnimation {
            configuration = nil
            layoutIfNeeded()
            configuration = saved
            layoutIfNeeded()
        }
    }

    private func stopTrackingMenuReturn() {
        menuReturnDisplayLink?.invalidate()
        menuReturnDisplayLink = nil
        menuReturnOrigin = nil
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopTrackingMenuReturn() }
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: WScalableButton.preferredHeight)
    }

    public func onToolbarLayout(layoutContext: ButtonsToolbarLayoutContext) {
        guard let title = configuration?.title else { return }
        switch layoutContext.pass {
        case .draft:
            let availableWidth = max(1, layoutContext.itemWidth - 16)
            var font = baseFont
            while font.pointSize > 6,
                  (title as NSString).size(withAttributes: [.font: font]).width > availableWidth {
                font = baseFont.withSize(max(6, font.pointSize - 0.5))
            }
            if layoutContext.font == nil || layoutContext.font!.pointSize > font.pointSize {
                layoutContext.font = font
            }
        case .finalizing:
            setTitleFont(layoutContext.font ?? baseFont)
        }
    }

    private func setTitleFont(_ font: UIFont) {
        guard configuredTitleFont != font, var config = configuration else { return }
        configuredTitleFont = font
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = font
            return outgoing
        }
        configuration = config
    }
}

@available(iOS 26, *)
@MainActor
private final class MenuReturnTarget: NSObject {
    weak var button: WGlassActionButton?
    init(button: WGlassActionButton) { self.button = button }
    @objc func tick(_ link: CADisplayLink) {
        guard let button else { link.invalidate(); return }
        button.updateMenuReturn()
    }
}
