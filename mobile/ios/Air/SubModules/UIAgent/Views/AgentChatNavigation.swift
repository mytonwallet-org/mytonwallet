import UIKit
import UIComponents
import WalletContext

/// A pushed Agent screen whose navigation buttons the root header's tabs and wallet avatar turn into during a push or pop
@MainActor
public protocol AgentChatNavigationHandoff: AnyObject {
    /// The chat's leading threads button and trailing more button, for the root header's morph
    var navigationHandoffLeadingView: UIView? { get }
    var navigationHandoffTrailingView: UIView? { get }
    /// The glass pill behind the chat's title, and the title inside it
    var navigationHandoffTitlePill: UIView? { get }
    var navigationHandoffTitleContent: UIView? { get }
    /// Hides both while the root's morphing stand-ins cover them
    func setNavigationHandoffHidden(_ isHidden: Bool)
}

extension AgentChatNavigationHandoff where Self: UIViewController {
    public var navigationHandoffTitlePill: UIView? {
        ((navigationItem.titleView as? NavigationHeader2)?.contentView as? AgentChatTitlePill)
    }

    public var navigationHandoffTitleContent: UIView? {
        (navigationHandoffTitlePill as? AgentChatTitlePill)?.contentView
    }
}

/// The header's capsules morphing between two Agent screens through a push or a pop between them, such as from the
/// News feed into a news item's discussion, as the root header's capsules morph into a chat's
@MainActor
public enum AgentChatHeaderMorph {
    public typealias Runner = @MainActor (
        _ outgoing: any AgentChatNavigationHandoff,
        _ incoming: any AgentChatNavigationHandoff,
        _ coordinator: any UIViewControllerTransitionCoordinator
    ) -> Void

    /// Draws the morph; the root installs it
    public static var runner: Runner?

    /// Call from `viewWillAppear` and `viewWillDisappear` of a screen that pushes other Agent screens: a push to or a
    /// pop from one of them morphs the capsules, while the root handles its own pushes and pops
    static func runIfNeeded(for screen: UIViewController & AgentChatNavigationHandoff, isAppearing: Bool) {
        guard let runner, let coordinator = screen.transitionCoordinator, coordinator.isAnimated,
              coordinator.viewController(forKey: isAppearing ? .to : .from) === screen,
              let other = coordinator.viewController(forKey: isAppearing ? .from : .to) as? any AgentChatNavigationHandoff
        else { return }
        runner(isAppearing ? other : screen, isAppearing ? screen : other, coordinator)
    }
}

/// The header transitions drawing over the bar at the moment. A screen that replaces its bar's screen, such as a chat
/// that finished loading, waits for them: the transition hides the bar's capsules it stands in for and shows them again
/// as it ends.
@MainActor
public enum AgentHeaderTransitionTracker {
    /// A transition runs well under this; a screen waits no longer for one that never ends
    private static let maximumWait: TimeInterval = 1.5
    private static var activeCount = 0
    private static var waiters: [Int: @MainActor () -> Void] = [:]
    private static var nextWaiterId = 0

    public static func begin() {
        activeCount += 1
    }

    public static func end() {
        activeCount = max(0, activeCount - 1)
        guard activeCount == 0 else { return }
        let pending = waiters.sorted { $0.key < $1.key }.map(\.value)
        waiters = [:]
        pending.forEach { $0() }
    }

    static var isIdle: Bool { activeCount == 0 }

    /// Runs `action` once no header transition is drawing
    static func runWhenIdle(_ action: @escaping @MainActor () -> Void) {
        guard activeCount > 0 else {
            action()
            return
        }
        let id = nextWaiterId
        nextWaiterId += 1
        waiters[id] = action
        DispatchQueue.main.asyncAfter(deadline: .now() + maximumWait) {
            MainActor.assumeIsolated {
                waiters.removeValue(forKey: id)?()
            }
        }
    }
}

/// The header shared by chats and the news feed: a transparent bar over the chat background's edge effect, the title,
/// and circular buttons that sit apart like the system back button
@MainActor
enum AgentChatNavigation {
    static let buttonSize = WGlassButtonMetrics.size
    static let threadsButtonIdentifier = "agent_threads_button"
    static let menuButtonIdentifier = "agent_menu_button"
    static let digestSettingsButtonIdentifier = "agent_digest_settings_button"
    static let supportButtonIdentifier = "agent_support_button"
    /// The headset as large as the "…" glyph beside it looks
    private static let supportIconSize: CGFloat = 22

    /// The back chevron of the button that returns to the chat list, drawn as the "…" button's glyph is. It points
    /// toward the leading edge, so it turns around in right-to-left layouts.
    static let backImage = UIImage(systemName: "chevron.backward", withConfiguration: WGlassButtonMetrics.symbolConfiguration)

    /// Makes the bar transparent in every state, puts the edge-effect background behind it and shows `titleView` as the
    /// title, on a glass pill. The background covers the views added before it, so the screen adds its content first.
    @discardableResult
    static func installHeader(
        in viewController: WViewController,
        titleView: UIView,
        scrollView: UIScrollView? = nil
    ) -> UIView {
        let background = installHeaderBackground(in: viewController, scrollView: scrollView)
        let header = NavigationHeader2()
        header.isAccessibilityElement = false
        header.accessibilityElementsHidden = false
        header.setContentView(AgentChatTitlePill(titleView: titleView))
        viewController.navigationItem.titleView = header
        return background
    }

    /// The header without a title, for a screen that puts its own capsule in the title's place, as the News feed's
    /// switch. The background covers the views added before it, so the screen adds its content first.
    static func installHeaderBackground(in viewController: WViewController, scrollView: UIScrollView? = nil) -> UIView {
        if #available(iOS 26.0, *), let scrollView {
            scrollView.topEdgeEffect.isHidden = true
        }
        return viewController.addCustomNavigationBarBackground(color: .air.background)
    }

    /// Replaces the system back button of a pushed screen with the threads button, the back chevron on glass that
    /// returns to the chat list; a stack's root keeps the system navigation
    static func installThreadsButton(in viewController: UIViewController) {
        let navigationItem = viewController.navigationItem
        guard let navigationController = viewController.navigationController,
              navigationController.viewControllers.first !== viewController else {
            navigationItem.leftBarButtonItem = nil
            navigationItem.hidesBackButton = false
            return
        }
        navigationItem.hidesBackButton = true
        guard Self.findButton(in: navigationItem.leftBarButtonItem)?.accessibilityIdentifier != threadsButtonIdentifier else { return }
        let circle = makeButton(image: backImage, primaryAction: UIAction { [weak viewController] _ in
            guard let viewController, let navigationController = viewController.navigationController else { return }
            viewController.view.endEditing(true)
            navigationController.popViewController(animated: true)
        })
        circle.button.accessibilityLabel = lang("Back")
        circle.button.accessibilityIdentifier = threadsButtonIdentifier
        navigationItem.leftBarButtonItem = makeItem(with: circle)
    }

    /// The chat's trailing "…" button, which opens `menu`; without a menu it only holds the chat's place while it loads
    static func makeMenuItem(menu: UIMenu?) -> UIBarButtonItem {
        let image = UIImage(systemName: "ellipsis", withConfiguration: WGlassButtonMetrics.symbolConfiguration)
        let circle = makeButton(image: image, primaryAction: nil)
        let button = circle.button
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        circle.isUserInteractionEnabled = menu != nil
        button.isAccessibilityElement = menu != nil
        button.accessibilityLabel = lang("More")
        button.accessibilityIdentifier = menuButtonIdentifier
        return makeItem(with: circle)
    }

    /// The chat's headset before its "…" button, which offers Contact Support
    static func makeSupportItem(primaryAction: UIAction?) -> UIBarButtonItem {
        let circle = makeButton(image: AgentSupportIcon.makeImage(size: supportIconSize), primaryAction: primaryAction)
        circle.button.accessibilityLabel = lang("$agent_support_contact")
        circle.button.accessibilityIdentifier = supportButtonIdentifier
        return makeItem(with: circle)
    }

    /// Enables or dims a glyph button made here: on glass the button doesn't dim by itself
    static func setGlyphButtonEnabled(_ button: UIButton, isEnabled: Bool) {
        guard button.isEnabled != isEnabled || button.configuration?.baseForegroundColor != glyphColor(isEnabled) else {
            return
        }
        button.isEnabled = isEnabled
        button.configuration?.baseForegroundColor = glyphColor(isEnabled)
    }

    private static func glyphColor(_ isEnabled: Bool) -> UIColor {
        isEnabled ? .label : .tertiaryLabel
    }

    /// The News feed's trailing bell, which opens the digest and notifications sheet
    static func makeDigestSettingsItem(primaryAction: UIAction) -> UIBarButtonItem {
        let image = UIImage(systemName: "bell", withConfiguration: WGlassButtonMetrics.symbolConfiguration)
        let circle = makeButton(image: image, primaryAction: primaryAction)
        circle.button.accessibilityLabel = lang("$agent_digest_settings_title")
        circle.button.accessibilityIdentifier = digestSettingsButtonIdentifier
        return makeItem(with: circle)
    }

    /// The glass circle of an item made by `installThreadsButton` or `makeMenuItem`
    static func findCircle(in item: UIBarButtonItem?) -> AgentGlassCircleButton? {
        item?.customView?.subviews.first as? AgentGlassCircleButton
    }

    /// The button inside the glass circle of an item made by `installThreadsButton` or `makeMenuItem`
    static func findButton(in item: UIBarButtonItem?) -> UIButton? {
        findCircle(in: item)?.button
    }

    static func setButtonsHidden(_ isHidden: Bool, in navigationItem: UINavigationItem) {
        for item in [navigationItem.leftBarButtonItem, navigationItem.rightBarButtonItem] {
            findCircle(in: item)?.alpha = isHidden ? 0 : 1
        }
    }

    static func makeButton(image: UIImage?, primaryAction: UIAction?) -> AgentGlassCircleButton {
        AgentGlassCircleButton(button: makeGlyphButton(image: image, primaryAction: primaryAction))
    }

    /// The button of a round glass button: `image`, drawn in the label colour in its middle
    static func makeGlyphButton(image: UIImage?, primaryAction: UIAction?) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = image
        configuration.baseForegroundColor = .label
        configuration.contentInsets = .zero
        configuration.cornerStyle = .capsule
        return UIButton(configuration: configuration, primaryAction: primaryAction)
    }

    /// A fixed square slot keeps the button a circle, independent of its image's size
    private static func makeItem(with circle: AgentGlassCircleButton) -> UIBarButtonItem {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: buttonSize, height: buttonSize))
        circle.frame = container.bounds
        circle.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(circle)
        let item = UIBarButtonItem(customView: container)
        item.accessibilityIdentifier = circle.button.accessibilityIdentifier
        if #available(iOS 26.0, *) {
            item.hidesSharedBackground = true
        }
        return item
    }
}

/// A round header button on interactive Liquid Glass. The button sits inside the glass, so the glass sees the touch as
/// well: it swells and stretches toward the finger, keeps following a finger that slides off it, and springs back with
/// a slight bounce once the finger lifts or a swipe takes the touch over, as on a release over the button. The glass
/// moves the glyph with it, so the button itself doesn't dim. Without Liquid Glass the button stands on a blur disc,
/// as the header's avatar and title pill stand on blur capsules there.
@MainActor
public final class AgentGlassCircleButton: UIView {
    /// Runs the action or opens the menu
    public let button: UIButton

    init(button: UIButton) {
        self.button = button
        super.init(frame: CGRect(x: 0, y: 0, width: AgentChatNavigation.buttonSize, height: AgentChatNavigation.buttonSize))
        var host: UIView = self
        if #available(iOS 26.0, *), IOS_26_MODE_ENABLED {
            let glassView = WGlassView(cornerRadius: nil)
            glassView.frame = bounds
            glassView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(glassView)
            host = glassView.contentView
            button.automaticallyUpdatesConfiguration = false
        } else {
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            blurView.frame = bounds
            blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blurView.layer.cornerRadius = AgentChatNavigation.buttonSize / 2
            blurView.clipsToBounds = true
            blurView.isUserInteractionEnabled = false
            addSubview(blurView)
        }
        button.frame = host.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Off for a placeholder that only holds the button's place, so the glass doesn't answer touches either
    public override var isUserInteractionEnabled: Bool {
        didSet { button.isUserInteractionEnabled = isUserInteractionEnabled }
    }
}

/// Keeps the swipe back on a pushed screen whose threads button replaces the system back button. UIKit's own gesture
/// delegates refuse to begin without the system back button, while the navigation controller allows the swipe whenever
/// there is a screen to return to.
@MainActor
final class AgentChatBackSwipe {
    private weak var navigationController: WNavigationController?
    private weak var previousDelegate: UIGestureRecognizerDelegate?
    private weak var previousContentDelegate: UIGestureRecognizerDelegate?

    /// Call when the screen has appeared, after the previous screen restored the delegates in its `viewWillDisappear`
    func install(for viewController: UIViewController) {
        guard navigationController == nil,
              viewController.navigationItem.hidesBackButton,
              let navigationController = viewController.navigationController as? WNavigationController,
              navigationController.viewControllers.first !== viewController else { return }
        self.navigationController = navigationController
        previousDelegate = navigationController.interactivePopGestureRecognizer?.delegate
        navigationController.interactivePopGestureRecognizer?.delegate = navigationController
        if #available(iOS 26.0, *) {
            previousContentDelegate = navigationController.interactiveContentPopGestureRecognizer?.delegate
            navigationController.interactiveContentPopGestureRecognizer?.delegate = navigationController
        }
    }

    /// A table that can still scroll back keeps the horizontal swipe; anywhere else it returns to the previous screen
    static func shouldAllowBackSwipe(in view: UIView, at point: CGPoint) -> Bool {
        let isRightToLeft = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        var candidate = view.hitTest(point, with: nil)
        while let current = candidate, current !== view {
            if let scrollView = current as? UIScrollView,
               scrollView.contentSize.width > scrollView.bounds.width + 0.5 {
                let inset = scrollView.adjustedContentInset
                let canScrollBack = isRightToLeft
                    ? scrollView.contentOffset.x < scrollView.contentSize.width - scrollView.bounds.width + inset.right - 0.5
                    : scrollView.contentOffset.x > -inset.left + 0.5
                if canScrollBack { return false }
            }
            candidate = current.superview
        }
        return true
    }

    func restore() {
        guard let navigationController else { return }
        navigationController.interactivePopGestureRecognizer?.delegate = previousDelegate
        if #available(iOS 26.0, *) {
            navigationController.interactiveContentPopGestureRecognizer?.delegate = previousContentDelegate
        }
        self.navigationController = nil
        previousDelegate = nil
        previousContentDelegate = nil
    }
}
