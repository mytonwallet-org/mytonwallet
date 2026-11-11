import SwiftUI
import UIKit
import WalletContext

public struct WAlertAction {
    public enum Style {
        case normal
        case primary
        case destructive
    }

    public var title: String
    public var style: Style
    public var isEnabled: Bool
    public var dismissAutomatically: Bool
    public var handler: () -> Void

    public init(
        title: String,
        style: Style = .normal,
        isEnabled: Bool = true,
        dismissAutomatically: Bool = true,
        handler: @escaping () -> Void = {}
    ) {
        self.title = title
        self.style = style
        self.isEnabled = isEnabled
        self.dismissAutomatically = dismissAutomatically
        self.handler = handler
    }
}

/// Adapts Telegram's AlertComponent/AlertScreen presentation to UIKit and hosted SwiftUI content.
/// Source: Telegram-iOS, submodules/TelegramUI/Components/AlertComponent (f1dd7a2).
public final class WAlertController: UIViewController {
    public struct Configuration {
        public var wide: Bool
        public var dismissOnOutsideTap: Bool

        public init(wide: Bool = false, dismissOnOutsideTap: Bool = true) {
            self.wide = wide
            self.dismissOnOutsideTap = dismissOnOutsideTap
        }
    }

    private let configuration: Configuration
    private let contentView: UIView
    private var contentController: UIViewController?
    private var actions: [WAlertAction]
    private var isPerformingAction = false
    fileprivate let dimView = UIControl()
    fileprivate let glassContainer = WAlertGlassContainer()
    fileprivate let panel = UIView()
    private let panelBackground = UIVisualEffectView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let actionStack = UIStackView()
    private var actionButtons: [WAlertActionButton] = []
    private var highlightedAction: Int?
    private let selectionFeedback = UISelectionFeedbackGenerator()

    public init(
        configuration: Configuration = .init(),
        actions: [WAlertAction],
        contentView: UIView
    ) {
        self.configuration = configuration
        self.actions = actions
        self.contentView = contentView
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    /// Hosts rich SwiftUI content, including charts, images and interactive controls
    public convenience init<Content: View>(
        title: String? = nil,
        kind: TipView.Kind = .info,
        configuration: Configuration = .init(),
        actions: [WAlertAction],
        @ViewBuilder content: () -> Content
    ) {
        let controller = UIHostingController(rootView: AnyView(
            content().textStyle(.body, scaling: .dynamic)
                .foregroundStyle(Color.air.primaryLabel)
                .tint(Color(uiColor: AirTintColor))
                .multilineTextAlignment(.leading)
                .lineSpacing(TipView.lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        ))
        controller.view.backgroundColor = .clear
        controller.sizingOptions = .intrinsicContentSize
        controller.disableSafeArea()
        let contentView = title.map { TipView(title: $0, kind: kind, contentView: controller.view) } ?? controller.view!
        self.init(configuration: configuration, actions: actions, contentView: contentView)
        contentController = controller
    }

    public convenience init(
        title: String,
        message: String?,
        configuration: Configuration = .init(),
        actions: [WAlertAction]
    ) {
        self.init(configuration: configuration, actions: actions, contentView: TipView(title: title, message: message))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        view.tintColor = AirTintColor
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        dimView.isAccessibilityElement = false
        dimView.addTarget(self, action: #selector(dismissFromOutside), for: .touchUpInside)
        view.addSubview(dimView)
        view.addSubview(glassContainer)
        glassContainer.contentView.addSubview(panel)
        panel.addSubview(panelBackground)
        updateSurface()

        let actionSelection = WAlertActionSelectionGestureRecognizer(target: self, action: #selector(selectAction(_:)))
        actionSelection.delegate = self
        panel.addGestureRecognizer(actionSelection)

        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.clipsToBounds = true
        scrollView.layer.cornerRadius = 34
        scrollView.layer.cornerCurve = .continuous
        panelBackground.contentView.addSubview(scrollView)
        stack.axis = .vertical
        scrollView.addSubview(stack)

        if let contentController { addChild(contentController) }
        let contentContainer = UIView()
        contentContainer.addSubview(contentView)
        stack.addArrangedSubview(contentContainer)
        contentController?.didMove(toParent: self)
        actionStack.axis = .vertical
        actionStack.spacing = 8
        actionStack.isLayoutMarginsRelativeArrangement = true
        actionStack.directionalLayoutMargins = .init(top: 0, leading: 14, bottom: 14, trailing: 14)
        stack.addArrangedSubview(actionStack)
        rebuildActions()

        let available = UILayoutGuide()
        view.addLayoutGuide(available)
        for subview in [dimView, glassContainer, panel, panelBackground, scrollView, stack, contentView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        let width = panel.widthAnchor.constraint(equalToConstant: configuration.wide ? 560 : 300)
        width.priority = .init(999)
        let height = panel.heightAnchor.constraint(equalTo: stack.heightAnchor)
        height.priority = .defaultLow
        NSLayoutConstraint.activate([
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            available.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            available.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
            available.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            available.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: configuration.wide ? 32 : 16),
            available.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: configuration.wide ? -32 : -16),
            glassContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glassContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            glassContainer.topAnchor.constraint(equalTo: view.topAnchor),
            glassContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.centerXAnchor.constraint(equalTo: available.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: available.centerYAnchor),
            panel.widthAnchor.constraint(lessThanOrEqualTo: available.widthAnchor),
            panel.heightAnchor.constraint(lessThanOrEqualTo: available.heightAnchor),
            width, height,
            panelBackground.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            panelBackground.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            panelBackground.topAnchor.constraint(equalTo: panel.topAnchor),
            panelBackground.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: panelBackground.contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: panelBackground.contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: panelBackground.contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: panelBackground.contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 22),
            contentView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -22),
            contentView.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 22),
            contentView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -24),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(updateSurface), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection), isViewLoaded {
            updateSurface()
        }
    }

    @objc private func updateSurface() {
        if UIAccessibility.isReduceTransparencyEnabled {
            panelBackground.effect = nil
            panelBackground.backgroundColor = .air.modularBackground
        } else if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            effect.tintColor = UIColor(white: 1, alpha: traitCollection.userInterfaceStyle == .dark ? 0.025 : 0.1)
            panelBackground.effect = effect
            panelBackground.backgroundColor = .clear
        } else {
            panelBackground.effect = UIBlurEffect(style: .systemMaterial)
            panelBackground.backgroundColor = .clear
        }
        if #available(iOS 26.0, *) {
            panelBackground.cornerConfiguration = .corners(radius: 34)
            panelBackground.clipsToBounds = false
        } else {
            panelBackground.clipsToBounds = true
        }
        panelBackground.layer.cornerRadius = 34
        panelBackground.layer.cornerCurve = .continuous
    }

    public func setActions(_ actions: [WAlertAction]) {
        self.actions = actions
        if isViewLoaded { rebuildActions() }
    }

    private func rebuildActions() {
        highlightedAction = nil
        actionButtons.removeAll()
        for view in actionStack.arrangedSubviews { view.removeFromSuperview() }
        actionStack.isHidden = actions.isEmpty
        for (index, action) in actions.enumerated() {
            let button = WAlertActionButton(action: action)
            button.tag = index
            button.addTarget(self, action: #selector(performAction(_:)), for: .touchUpInside)
            actionStack.addArrangedSubview(button)
            actionButtons.append(button)
        }
    }

    @objc private func selectAction(_ gesture: UIGestureRecognizer) {
        trackAction(at: gesture.location(in: view), state: gesture.state)
    }

    // Selection lives on the panel, so a single touch can move between actions.
    func trackAction(at point: CGPoint, state: UIGestureRecognizer.State) {
        switch state {
        case .began, .changed:
            let index = actionIndex(at: point)
            if index != highlightedAction {
                setHighlightedAction(index)
                if state == .changed, index != nil { selectionFeedback.selectionChanged() }
            }
            if state == .began { selectionFeedback.prepare() }
        case .ended:
            let index = actionIndex(at: point)
            setHighlightedAction(nil)
            if let index { performAction(actionButtons[index]) }
        case .cancelled, .failed:
            setHighlightedAction(nil)
        default:
            break
        }
    }

    fileprivate func actionIndex(at point: CGPoint) -> Int? {
        guard !isPerformingAction, !isBeingDismissed,
              scrollView.bounds.contains(scrollView.convert(point, from: view)) else { return nil }
        return actionButtons.firstIndex { button in
            button.isEnabled && button.bounds.contains(button.convert(point, from: view))
        }
    }

    private func setHighlightedAction(_ index: Int?) {
        highlightedAction = index
        for (buttonIndex, button) in actionButtons.enumerated() {
            button.isHighlighted = buttonIndex == index
        }
    }

    @objc private func performAction(_ sender: UIControl) {
        guard actions.indices.contains(sender.tag), !isPerformingAction, !isBeingDismissed else { return }
        let action = actions[sender.tag]
        guard action.isEnabled else { return }
        if action.dismissAutomatically {
            isPerformingAction = true
            view.endEditing(true)
            dismiss(animated: true, completion: action.handler)
        } else {
            action.handler()
        }
    }

    @objc private func dismissFromOutside() {
        guard configuration.dismissOnOutsideTap, !isPerformingAction, !isBeingDismissed else { return }
        view.endEditing(true)
        dismiss(animated: true)
    }

    public override func accessibilityPerformEscape() -> Bool {
        guard configuration.dismissOnOutsideTap else { return false }
        dismissFromOutside()
        return true
    }

    public override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(dismissFromOutside)),
         UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(moveSelection(_:))),
         UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(moveSelection(_:))),
         UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(activateSelection))]
    }

    @objc private func moveSelection(_ command: UIKeyCommand) {
        let enabled = actions.indices.filter { actions[$0].isEnabled }
        guard !enabled.isEmpty else { return }
        let step = command.input == UIKeyCommand.inputUpArrow ? -1 : 1
        if let highlightedAction, let position = enabled.firstIndex(of: highlightedAction) {
            setHighlightedAction(enabled[(position + step + enabled.count) % enabled.count])
        } else {
            setHighlightedAction(enabled.first(where: { actions[$0].style == .primary }) ?? enabled[0])
        }
        if let highlightedAction {
            scrollView.scrollRectToVisible(actionButtons[highlightedAction].convert(actionButtons[highlightedAction].bounds, to: scrollView), animated: true)
        }
    }

    @objc private func activateSelection() {
        if let highlightedAction { performAction(actionButtons[highlightedAction]) }
    }
}

extension WAlertController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        actionIndex(at: gestureRecognizer.location(in: view)) != nil
    }
}

private final class WAlertGlassContainer: UIView {
    let contentView: UIView
    private let effectView: UIVisualEffectView?

    init() {
        if #available(iOS 26.0, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = 7
            let effectView = UIVisualEffectView(effect: effect)
            self.effectView = effectView
            contentView = effectView.contentView
        } else {
            effectView = nil
            contentView = UIView()
        }
        super.init(frame: .zero)
        let container = effectView ?? contentView
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self || result === effectView || result === contentView ? nil : result
    }
}

/// Telegram's immediate action selection recognizer, independent of button tracking/layout.
private final class WAlertActionSelectionGestureRecognizer: UIGestureRecognizer {
    private weak var trackedTouch: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard trackedTouch == nil, touches.count == 1 else {
            state = .cancelled
            return
        }
        trackedTouch = touches.first
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        if let trackedTouch, touches.contains(trackedTouch) { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        if let trackedTouch, touches.contains(trackedTouch) { state = .ended }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
    }
}

final class WAlertActionButton: UIControl {
    private let fillView = UIView()
    private let label = UILabel()

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
                self.fillView.alpha = self.isEnabled ? (self.isHighlighted ? 0.35 : 1) : 0.2
            }
        }
    }

    init(action: WAlertAction) {
        super.init(frame: .zero)
        fillView.backgroundColor = action.style == .primary ? AirTintColor : .secondarySystemFill
        fillView.alpha = action.isEnabled ? 1 : 0.2
        fillView.layer.cornerCurve = .continuous
        fillView.isUserInteractionEnabled = false
        addSubview(fillView)
        label.text = action.title
        label.textColor = action.style == .primary ? .white : action.style == .destructive ? .air.error : .label
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.isAccessibilityElement = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        isAccessibilityElement = true
        accessibilityLabel = action.title
        accessibilityTraits = action.isEnabled ? .button : [.button, .notEnabled]
        isEnabled = action.isEnabled
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        fillView.frame = bounds
        fillView.layer.cornerRadius = bounds.height / 2
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { false }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        sendActions(for: .touchUpInside)
        return true
    }
}

extension WAlertController: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        WAlertPresentationController(presentedViewController: presented, presenting: presenting)
    }

    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        WAlertTransition(presenting: true)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        WAlertTransition(presenting: false)
    }
}

private final class WAlertPresentationController: UIPresentationController {
    override var shouldRemovePresentersView: Bool { false }
    override var frameOfPresentedViewInContainerView: CGRect { containerView?.bounds ?? .zero }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        presentedView?.frame = frameOfPresentedViewInContainerView
    }
}

private final class WAlertTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let presenting: Bool

    init(presenting: Bool) { self.presenting = presenting }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        presenting && !UIAccessibility.isReduceMotionEnabled ? 0.4 : 0.2
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let alert = context.viewController(forKey: presenting ? .to : .from) as? WAlertController else {
            context.completeTransition(false)
            return
        }
        if presenting {
            context.containerView.addSubview(alert.view)
            alert.view.frame = context.finalFrame(for: alert)
            alert.view.layoutIfNeeded()
        }
        let toAlpha: CGFloat = presenting ? 1 : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock {
            let completed = !context.transitionWasCancelled
            if !completed {
                let restoredAlpha: Float = self.presenting ? 0 : 1
                alert.dimView.layer.opacity = restoredAlpha
                alert.glassContainer.layer.opacity = restoredAlpha
            }
            context.completeTransition(completed)
            if self.presenting && completed {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
        for view in [alert.dimView, alert.glassContainer] {
            let fromAlpha = presenting ? 0 : CGFloat(view.layer.presentation()?.opacity ?? view.layer.opacity)
            view.layer.opacity = Float(toAlpha)
            view.layer.animateAlpha(from: fromAlpha, to: toAlpha, duration: 0.2,
                                    timingFunction: CAMediaTimingFunctionName.linear.rawValue)
        }
        if presenting && !UIAccessibility.isReduceMotionEnabled {
            let spring = makeSpringAnimation("transform.scale")
            if #available(iOS 26.0, *) {
                // Telegram's iOS 26 spring from UIKitRuntimeUtils/make26SpringAnimationImpl.
                spring.mass = 1
                spring.stiffness = 555.027
                spring.damping = 47.118
                spring.allowsOverdamping = false
                spring.duration = 0.4
            } else {
                spring.speed = Float(spring.duration / 0.4)
            }
            spring.fromValue = 1.15
            spring.toValue = 1
            spring.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
            alert.panel.layer.add(spring, forKey: "alertEntrance")
        }
        CATransaction.commit()
    }
}
