import UIComponents
import UIKit
import WalletContext

public struct UniversalSearchAutocomplete: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case standard
        case agent
    }

    public var suggestion: String
    public var actionTitle: String
    public var style: Style

    public init(
        suggestion: String,
        actionTitle: String,
        style: Style = .standard
    ) {
        self.suggestion = suggestion
        self.actionTitle = actionTitle
        self.style = style
    }
}

public struct UniversalSearchFieldConfiguration: Equatable, Sendable {
    public var text: String
    public var placeholder: String
    public var shortPlaceholder: String?
    public var autocomplete: UniversalSearchAutocomplete?
    public var showsMicrophone: Bool

    public init(
        text: String = "",
        placeholder: String,
        shortPlaceholder: String? = nil,
        autocomplete: UniversalSearchAutocomplete? = nil,
        showsMicrophone: Bool = true
    ) {
        self.text = text
        self.placeholder = placeholder
        self.shortPlaceholder = shortPlaceholder
        self.autocomplete = autocomplete
        self.showsMicrophone = showsMicrophone
    }
}

public enum UniversalSearchFieldPresentation: Equatable, Sendable {
    case homeToolbar
    case sideToolbar
    case compactToolbar
    case search
    case empty
}

/// The active Universal Search input and its adjacent close control.
///
/// The view owns presentation and text editing only. Search results and autocomplete
/// decisions remain the responsibility of its host through `configuration` and callbacks.
@MainActor
public final class UniversalSearchFieldView: UIView {
    private struct PresentationTransition {
        let id = UUID()
        let navigationOperation: UINavigationController.Operation
        let source: UniversalSearchFieldPresentation
        let target: UniversalSearchFieldPresentation
        let sourceActions: [SharedBottomToolbarAction]
        let targetActions: [SharedBottomToolbarAction]
    }

    public var onActivate: (() -> Void)?
    public var onTextChange: ((String) -> Void)?
    public var onEditingChange: ((Bool) -> Void)?
    public var onReturn: ((String) -> Void)?
    public var onMicrophoneTap: (() -> Void)?
    public var onActionsTap: (() -> Void)?
    public var onAccountsTap: (() -> Void)?
    /// A tap on one of the home toolbar's own buttons other than the accounts and the actions buttons
    public var onHomeItemTap: ((HomeToolbarItem) -> Void)?
    /// A navigation transition took the toolbar away from under a drag
    public var onHomeEditInterruption: (() -> Void)?
    public var onToolbarActionTap: ((String) -> Void)?
    public var onCloseTap: (() -> Void)?
    public var onHomeConfigurationLayoutChange: (() -> Void)?

    /// Extra space below the root toolbar that accepts toolbar gestures.
    public var bottomHitAreaExtension: CGFloat = 0

    /// The host's visible panel, independent of the toolbar's maximum width.
    /// Hosts should clip at this boundary, leaving the toolbar's glass unclipped.
    public weak var transitionViewportView: UIView? {
        didSet { setNeedsLayout() }
    }

    public var configuration: UniversalSearchFieldConfiguration {
        get { storedConfiguration }
        set {
            storedConfiguration = newValue
            fieldView.configure(with: newValue)
        }
    }

    public var microphoneAccessibilityLabel: String = lang("$universal_search_dictate") {
        didSet { fieldView.microphoneAccessibilityLabel = microphoneAccessibilityLabel }
    }

    public var clearAccessibilityLabel: String = lang("$universal_search_clear_text") {
        didSet { fieldView.clearAccessibilityLabel = clearAccessibilityLabel }
    }

    public var closeAccessibilityLabel: String = lang("Close") {
        didSet { updateTrailingButtonAccessibilityLabel() }
    }

    public var actionsAccessibilityLabel: String = lang("Actions") {
        didSet { updateTrailingButtonAccessibilityLabel() }
    }

    /// Accessibility identifier of the collapsed field in the compact toolbar
    public var compactAccessibilityIdentifier: String? {
        get { fieldView.compactAccessibilityIdentifier }
        set { fieldView.compactAccessibilityIdentifier = newValue }
    }

    public var text: String { fieldView.text }
    public var isEditing: Bool { fieldView.isEditing }
    public var searchButtonPresentationSourceView: UIView { fieldView }
    public var trailingButtonView: UIView { closeButton.interactionView }
    /// What a presentation grows out of at the trailing button. A zoom gets a plain view in the button's place, as
    /// `getHomeItemZoomSourceView` does.
    public var trailingButtonPresentationSourceView: UIView {
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            return getZoomAnchorView(for: .actions)
        }
        return closeButton.presentationSourceView
    }
    public let accountsButton = WalletAccountButton()
    /// The home toolbar's button for `item` while it shows, such as for a presentation that grows out of it
    public func getHomeItemSourceView(for item: HomeToolbarItem) -> UIView? {
        guard showsHomeActions(in: presentation), presentation != .empty, isHomeItemShown(item) else { return nil }
        return getHomeItemView(item)
    }
    public var scanButtonPresentationSourceView: UIView? { getHomeItemSourceView(for: .scan) }

    /// What a zoom transition grows out of at the button for `item`: a plain view in the button's place, outside
    /// the toolbar's glass. A zoom takes over the glass around its source for its own morph and can hand it back
    /// changed.
    public func getHomeItemZoomSourceView(for item: HomeToolbarItem) -> UIView? {
        guard getHomeItemSourceView(for: item) != nil else { return nil }
        return getZoomAnchorView(for: item)
    }
    public private(set) var homeConfiguration = HomeToolbarConfiguration()
    /// The drag that is rearranging the home toolbar
    public private(set) var homeEdit: HomeToolbarEdit?
    public private(set) var compactActions: [SharedBottomToolbarAction] = []
    public private(set) var presentation: UniversalSearchFieldPresentation = .search
    public private(set) var searchOverlayAppearance: ContentOverlayAppearance = .standard
    public private(set) var actionsOverlayAppearance: ContentOverlayAppearance = .standard

    public func setOverlayAppearance(search: ContentOverlayAppearance, actions: ContentOverlayAppearance, animated: Bool) {
        let animated = animated && window != nil && !UIAccessibility.isReduceMotionEnabled
        if search != searchOverlayAppearance {
            searchOverlayAppearance = search
            fieldView.setOverlayAppearance(search, animated: animated)
        }
        if actions != actionsOverlayAppearance {
            actionsOverlayAppearance = actions
            closeButton.setOverlayAppearance(actions, animated: animated)
            itemButtons.values.forEach { $0.setOverlayAppearance(actions) }
            accountsButton.overrideUserInterfaceStyle = actions.userInterfaceStyle
            for glass in [leadingGroupGlass, trailingGroupGlass] {
                glass.overrideUserInterfaceStyle = actions.userInterfaceStyle
                glass.setUsesClearGlass(actions.usesClearGlass)
            }
        }
    }

    private var storedConfiguration: UniversalSearchFieldConfiguration
    private let fieldView = UniversalSearchFieldCapsuleView()
    private let closeButton = UniversalSearchCloseButton()
    private var itemButtons: [HomeToolbarItem: UniversalSearchIconButton] = [:]
    /// The buttons whose glass shows. A button on its way out keeps its glass until it has merged into its neighbor.
    private var materialItems: Set<HomeToolbarItem> = []
    /// The glass that the buttons before the field share, and the glass of the buttons after it. Buttons that share
    /// a background are inside one piece of glass, which reacts to a touch as a whole.
    private let leadingGroupGlass = UniversalSearchInteractiveGlassView()
    private let trailingGroupGlass = UniversalSearchInteractiveGlassView()
    /// The sides of the field whose buttons are inside their shared glass, by whether the side is before the field.
    /// A side keeps its shared glass through a change that leaves it one button, until the change has finished.
    private var groupedSides: Set<Bool> = []
    private var zoomAnchorViews: [HomeToolbarItem: UIView] = [:]
    /// The item a drag just dropped, whose button stays empty until the dragged copy has landed on it
    private var homeLandingItem: HomeToolbarItem?
    /// The items the buttons were last shown for. A toolbar that changes width may show others.
    private var laidOutHomeItems: [HomeToolbarItem] = []
    private var fieldLeadingConstraint: NSLayoutConstraint!
    private var fieldTopConstraint: NSLayoutConstraint!
    private var fieldTrailingConstraint: NSLayoutConstraint!
    private var fieldWidthConstraint: NSLayoutConstraint!
    private var pendingHomeConfiguration: HomeToolbarConfiguration?
    private var configurationAnimationID: UUID?
    // Mirrors an owning animator's fraction without rendering anything. The
    // display link uses it to keep content blur interactive with push/pop.
    private let transitionProgressView = UIView()
    private let glassContainerView: UIVisualEffectView?
    private let contentView: UIView
    private var compactActionButtons: [String: UniversalSearchToolbarActionButton] = [:]
    private var compactActionButtonOrder: [UniversalSearchToolbarActionButton] = []
    private var compactActionConstraints: [NSLayoutConstraint] = []
    private var outgoingCompactActionButtons: [UniversalSearchToolbarActionButton] = []
    private var outgoingCompactActionConstraints: [NSLayoutConstraint] = []
    /// Out of the hierarchy, reused for later actions for the same reason as `reusableHomeActionGlassViews`
    private var reusableCompactActionButtons: [UniversalSearchToolbarActionButton] = []
    /// Glass views that joined the glass container since its effect was last set
    private var joinedGlassViews: Set<ObjectIdentifier> = []
    private var emptyBasePresentation: UniversalSearchFieldPresentation = .homeToolbar
    private var presentationTransition: PresentationTransition?
    private var transitionDisplayLink: CADisplayLink?
    private var trailingHandoffProgress: CGFloat = 0

    public init(configuration: UniversalSearchFieldConfiguration) {
        storedConfiguration = configuration

        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = Self.defaultGlassMergeSpacing
            let glassContainerView = UIVisualEffectView(effect: effect)
            self.glassContainerView = glassContainerView
            contentView = glassContainerView.contentView
        } else {
            glassContainerView = nil
            contentView = UIView()
        }

        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        setupLayout()
        setupCallbacks()
        fieldView.configure(with: configuration)
        fieldView.microphoneAccessibilityLabel = microphoneAccessibilityLabel
        fieldView.clearAccessibilityLabel = clearAccessibilityLabel
        updateTrailingButtonAccessibilityLabel()
        prepareHomeItemViews(for: homeConfiguration.visibleItems)
        updatePresentationConstraints()
        applyStaticVisualState(for: presentation)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: presentation == .sideToolbar ? sideToolbarHeight : 48)
    }

    /// The side toolbar is a column of every configured button, whatever fits the toolbar as a row
    public var sideToolbarHeight: CGFloat {
        let layout = HomeToolbarLayout(
            items: homeOrder.filter(isHomeItemConfigured),
            sharesBackground: usesSharedActionsBackground
        )
        return HomeToolbarLayout.buttonSize + layout.buttonsSpan
    }

    public override var center: CGPoint {
        didSet {
            // A capped toolbar can move during a resize without changing bounds.
            if center != oldValue { setNeedsLayout() }
        }
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Hosted glass reaching past this view, such as the recording's pause button standing above the Agent's field,
        // takes its touches through containers that ask this view
        if super.point(inside: point, with: event) || getHostedGlassHit(at: point, with: event) != nil { return true }
        guard presentation == .homeToolbar, bottomHitAreaExtension > 0, let window else {
            return false
        }
        // Keep the lowest 20 points outside the extra hit area for system gestures.
        let bottomLimit = convert(
            CGPoint(x: window.bounds.midX, y: window.bounds.maxY - 20),
            from: window
        ).y
        let extensionHeight = max(0, min(bottomHitAreaExtension, bottomLimit - bounds.maxY))
        return CGRect(
            x: bounds.minX,
            y: bounds.maxY,
            width: bounds.width,
            height: extensionHeight
        ).contains(point)
    }

    @discardableResult
    public func focus() -> Bool {
        fieldView.focus()
    }

    @discardableResult
    public func endEditing() -> Bool {
        fieldView.endEditing()
    }

    public func setCompactActions(_ actions: [SharedBottomToolbarAction]) {
        guard actions != compactActions else { return }
        compactActions = actions

        UIView.performWithoutAnimation {
            rebuildCompactActions(with: actions)
            layoutIfNeeded()
        }
    }

    /// Collapses the home toolbar into its leading search circle, folds its scan and accounts buttons into the
    /// trailing button and hides the trailing button.
    ///
    /// `progress` runs from 0, the regular toolbar, to 1, where only the circle remains. A screen whose own bar
    /// grows out of the field and takes the trailing button's place drives it, for example while paging toward that
    /// screen. It applies while the field shows the home toolbar, including while that toolbar slides away with a
    /// navigation transition.
    public func setTrailingHandoffProgress(_ progress: CGFloat) {
        let progress = min(1, max(0, progress))
        guard progress != trailingHandoffProgress else { return }
        trailingHandoffProgress = progress
        applyTrailingHandoff()
    }

    /// The distance within which the toolbar's own glass pieces flow into each other
    nonisolated static let defaultGlassMergeSpacing: CGFloat = 4

    /// Leaves room under UIKit's 63 glass tag bits for glass that joins between checks
    private static let glassTagBudget = 48

    /// The content view of the toolbar's glass container. A host can place its own glass here so it merges with
    /// the toolbar's; such glass must be listed by `hostedGlassViews` to receive touches.
    public var glassContentView: UIView { contentView }

    /// Glass a host placed in `glassContentView`. It receives touches even where it reaches past this view.
    public var hostedGlassViews: () -> [UIView] = { [] }

    /// While set, the empty presentation leaves the toolbar in place instead of sliding it away. A host whose glass
    /// here turns into the next screen's controls sets it, and dismisses the toolbar's own field itself with
    /// `setFieldHandoffAppearance(scale:alpha:)`.
    public var shouldKeepPlaceWhenEmpty = false {
        didSet {
            if shouldKeepPlaceWhenEmpty != oldValue { setNeedsLayout() }
        }
    }

    /// While set, the trailing button stays hidden: a host's control in its place turns into it, and hands it back
    public var isTrailingButtonHandedOff = false {
        didSet {
            if isTrailingButtonHandedOff != oldValue { applyTrailingHandoff() }
        }
    }

    /// Scales the toolbar's own field around its center, moves it sideways by `offset` and fades it, for a host's
    /// handoff morph
    public func setFieldHandoffAppearance(scale: CGFloat, alpha: CGFloat, offset: CGFloat = 0) {
        fieldView.transform = scale == 1 && offset == 0
            ? .identity
            : CGAffineTransform(translationX: offset, y: 0).scaledBy(x: scale, y: scale)
        fieldView.setHandoffAlpha(alpha)
    }

    /// Scales the trailing button around its center for a host's morph, such as the slight bounce of a host's bar
    /// folding back into it
    public func setTrailingButtonHandoffScale(_ scale: CGFloat) {
        closeButton.transform = scale == 1 ? .identity : CGAffineTransform(scaleX: scale, y: scale)
    }

    /// The distance within which the container's glass pieces flow into each other
    public func setGlassMergeSpacing(_ spacing: CGFloat) {
        guard IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *), let glassContainerView,
              (glassContainerView.effect as? UIGlassContainerEffect)?.spacing != spacing else { return }
        let effect = UIGlassContainerEffect()
        effect.spacing = spacing
        glassContainerView.effect = effect
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        getHostedGlassHit(at: point, with: event) ?? super.hitTest(point, with: event)
    }

    /// The view in the hosted glass that takes a touch at `point`
    private func getHostedGlassHit(at point: CGPoint, with event: UIEvent?) -> UIView? {
        for view in hostedGlassViews().reversed() where !view.isHidden && view.alpha > 0.01 && view.isUserInteractionEnabled {
            let localPoint = view.convert(point, from: self)
            if view.point(inside: localPoint, with: event), let hit = view.hitTest(localPoint, with: event) {
                return hit
            }
        }
        return nil
    }

    /// How much wider than the trailing button the home toolbar's buttons after the field are. A trailing handoff
    /// folds them into the trailing button as the field collapses.
    public var homeActionsWidth: CGFloat {
        max(0, homeLayout.fieldTrailingInset - HomeToolbarLayout.fieldGap - HomeToolbarLayout.buttonSize)
    }

    /// The space the home toolbar's buttons before the field take, with their gap to it. A trailing handoff folds
    /// them into the search circle as the field collapses.
    public var homeFieldLeadingInset: CGFloat { homeLayout.fieldLeadingInset }

    private var isTrailingHandoffActive: Bool {
        trailingHandoffProgress > 0 && contentPresentation(for: presentation) == .homeToolbar
    }

    /// The fold at which the buttons' content has shrunk away
    private static let homeActionsContentSwapEnd: CGFloat = 0.75

    /// How far a trailing handoff has folded the buttons into the search circle and the trailing button
    private var homeActionsFold: CGFloat {
        isTrailingHandoffActive ? trailingHandoffProgress : 0
    }

    /// Whether a trailing handoff had the buttons out of reach when it last applied
    private var areHomeActionsHandedOff = false

    private func applyTrailingHandoff() {
        let isActive = isTrailingHandoffActive
        updateFieldConstraints()
        let fold = homeActionsFold
        // The buttons' glass slides into the search circle or the trailing button's place, merging with the host's
        // control there, and their content shrinks away on the way, as the trailing button's own glyph does on the
        // host's control. Folded all the way, their glass lies under the host's control, which stands in for it.
        let isFolded = fold > 0.99
        let contentSwap = min(1, fold / Self.homeActionsContentSwapEnd)
        let contentScale = 1 + (GlassMotion.matchScale - 1) * contentSwap
        for item in materialItems {
            guard let view = getOptionalItemView(item) else { continue }
            view.alpha = isFolded ? 0 : 1
            view.setHandoffContent(alpha: 1 - contentSwap, scale: contentScale)
        }
        leadingGroupGlass.alpha = isFolded ? 0 : 1
        trailingGroupGlass.alpha = isFolded ? 0 : 1
        let isTrailingGlassShared = closeButton.superview !== contentView
        closeButton.alpha = isTrailingButtonHandedOff || (isActive && (!isTrailingGlassShared || isFolded)) ? 0 : 1
        closeButton.setHandoffContentHidden(isActive)
        let isHandedOff = fold > 0
        if isHandedOff != areHomeActionsHandedOff {
            areHomeActionsHandedOff = isHandedOff
            updateHomeItemsAppearance(for: presentation)
        }
        updateTrailingButtonAccessibilityLabel()
        fieldView.setHandoff(
            progress: isActive ? trailingHandoffProgress : 0,
            isCollapsed: isActive && fieldWidthConstraint.constant < 110
        )
        setNeedsLayout()
    }

    public func setHomeConfiguration(_ configuration: HomeToolbarConfiguration, animated: Bool) {
        // Navigation owns the geometry until an interactive transition completes or cancels.
        guard presentationTransition == nil else {
            pendingHomeConfiguration = configuration
            return
        }
        guard configuration != homeConfiguration else { return }
        prepareHomeItemViews(for: configuration.visibleItems)
        homeConfiguration = configuration
        applyHomeItemsChange(animated: animated)
    }

    /// Shows the toolbar as a drag arranges it: its other buttons make room where `edit` would drop its item and
    /// wiggle, as Home Screen icons do while they are edited. `nil` puts the toolbar back as it is configured.
    public func setHomeEdit(_ edit: HomeToolbarEdit?, animated: Bool) {
        guard edit != homeEdit, presentationTransition == nil else { return }
        if let edit { prepareHomeItemViews(for: [edit.item]) }
        let isEditing = edit != nil
        let hasEditingChanged = isEditing != (homeEdit != nil)
        homeEdit = edit
        applyHomeItemsChange(animated: animated, usesSpring: true)
        if hasEditingChanged { setHomeItemsEditing(isEditing) }
    }

    /// Ends the drag and takes `configuration` in one move. The button of `landingItem` stays empty until
    /// `finishHomeItemLanding`, for the dragged copy to land on it.
    public func endHomeEdit(
        with configuration: HomeToolbarConfiguration,
        landingItem: HomeToolbarItem? = nil,
        animated: Bool
    ) {
        setHomeItemsEditing(false)
        guard presentationTransition == nil else {
            homeEdit = nil
            pendingHomeConfiguration = configuration
            return
        }
        prepareHomeItemViews(for: configuration.visibleItems)
        homeEdit = nil
        homeLandingItem = landingItem
        homeConfiguration = configuration
        applyHomeItemsChange(animated: animated, usesSpring: true)
    }

    public func finishHomeItemLanding() {
        guard homeLandingItem != nil else { return }
        homeLandingItem = nil
        UIView.performWithoutAnimation {
            updateHomeItemsAppearance(for: presentation)
        }
    }

    /// The frame of the place `item` has in the home toolbar as it is being laid out, in this view's coordinates
    public func getHomeItemFrame(_ item: HomeToolbarItem) -> CGRect? {
        guard contentPresentation(for: presentation) == .homeToolbar else { return nil }
        let layout = homeLayout
        if item == .search {
            return getDirectionalFrame(
                start: layout.fieldLeadingInset,
                length: max(HomeToolbarLayout.buttonSize, bounds.width - layout.buttonsSpan)
            )
        }
        guard let slot = layout.slot(for: item) else { return nil }
        return getDirectionalFrame(start: layout.getStart(of: slot, length: bounds.width), length: HomeToolbarLayout.buttonSize)
    }

    /// The home toolbar's button under `point`, in this view's coordinates
    public func getHomeItem(at point: CGPoint) -> HomeToolbarItem? {
        guard presentation == .homeToolbar, homeActionsFold == 0 else { return nil }
        return homeOrder.first { isHomeItemShown($0) && getHomeItemFrame($0)?.contains(point) == true }
    }

    /// The order with `item` moved to the place nearest to `x`, in this view's coordinates
    public func getHomeOrder(moving item: HomeToolbarItem, toward x: CGFloat) -> [HomeToolbarItem] {
        var shownItems = Set(homeOrder.filter(isHomeItemShown))
        shownItems.insert(item)
        return HomeToolbarLayout.getOrder(
            moving: item,
            in: homeOrder,
            shownItems: shownItems,
            sharesBackground: usesSharedActionsBackground,
            toward: effectiveUserInterfaceLayoutDirection == .rightToLeft ? bounds.width - x : x,
            length: bounds.width
        )
    }

    /// Whether the toolbar keeps a usable search field with `item` shown too, beside the buttons `configuration`
    /// shows, or the ones the toolbar shows now
    public func canHoldHomeItem(_ item: HomeToolbarItem, in configuration: HomeToolbarConfiguration? = nil) -> Bool {
        var configuration = configuration ?? homeConfiguration
        configuration.sharesBackground = configuration.sharesBackground && Self.supportsSharedBackground
        return HomeToolbarLayout.canHold(item, in: configuration, length: bounds.width)
    }

    /// A copy of what the button of `item` shows, for a view that stands in for it while it is dragged
    public func makeHomeItemContentCopy(_ item: HomeToolbarItem) -> UIView {
        if item == .accounts { return accountsButton.makeContentCopy() }
        let imageView = UIImageView(image: item.makeToolbarImage())
        imageView.tintColor = actionsOverlayAppearance.foregroundColor ?? .label
        imageView.contentMode = .center
        imageView.frame = CGRect(x: 0, y: 0, width: HomeToolbarLayout.buttonSize, height: HomeToolbarLayout.buttonSize)
        return imageView
    }

    private func applyHomeItemsChange(animated: Bool, usesSpring: Bool = false) {
        let shouldAnimate = animated && window != nil && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
        invalidateIntrinsicContentSize()
        let animationID = UUID()
        configurationAnimationID = animationID
        beginHomeItemsChange(to: presentation)
        updateFieldConstraints()
        let updates = {
            self.updateHomeItemsAppearance(for: self.presentation)
            self.onHomeConfigurationLayoutChange?()
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, self.configurationAnimationID == animationID else { return }
            self.configurationAnimationID = nil
            self.finishHomeItemsAppearance()
        }
        if shouldAnimate, usesSpring {
            UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction], animations: updates, completion: completion)
        } else if shouldAnimate {
            UIView.animate(withDuration: 0.4, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: updates, completion: completion)
        } else {
            UIView.performWithoutAnimation(updates)
            completion(true)
        }
    }

    public func setPresentation(
        _ presentation: UniversalSearchFieldPresentation,
        animated: Bool,
        duration: TimeInterval = 0.4
    ) {
        guard animated && !UIAccessibility.isReduceMotionEnabled else {
            applyStaticPresentation(presentation)
            layoutIfNeeded()
            return
        }

        layoutIfNeeded()
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeInOut)
        setPresentation(presentation, animator: animator, duration: duration)
        animator.addAnimations {
            self.layoutIfNeeded()
        }
        animator.startAnimation()
    }

    /// Adds this view's presentation changes to a host-owned animator.
    ///
    /// Use this overload when constraints outside this view also change. The host
    /// should lay out its source state, call this method, update its constraints,
    /// add `layoutIfNeeded()` on their common ancestor, and start the animator.
    public func setPresentation(
        _ presentation: UniversalSearchFieldPresentation,
        animator: UIViewPropertyAnimator,
        duration _: TimeInterval = 0.4
    ) {
        guard preparePresentationTransition(to: presentation) != nil else { return }
        applyPresentation(presentation, animator: animator)
    }

    /// Stages a presentation change for an externally owned transition, such as
    /// an interactive navigation push or pop. The returned ID binds animation
    /// callbacks to this transition, even if another update supersedes it.
    @discardableResult
    public func preparePresentationTransition(
        to presentation: UniversalSearchFieldPresentation,
        compactActions: [SharedBottomToolbarAction]? = nil,
        navigationOperation: UINavigationController.Operation = .push
    ) -> UUID? {
        let targetActions = compactActions ?? self.compactActions
        guard presentation != self.presentation || targetActions != self.compactActions else { return nil }

        configurationAnimationID = nil

        if presentationTransition != nil {
            finishPresentationTransition(at: self.presentation)
        }
        layoutIfNeeded()
        updateEmptyBasePresentation(for: presentation)
        if homeEdit != nil {
            homeEdit = nil
            setHomeItemsEditing(false)
            onHomeEditInterruption?()
        }

        let transition = PresentationTransition(
            navigationOperation: navigationOperation,
            source: self.presentation,
            target: presentation,
            sourceActions: self.compactActions,
            targetActions: targetActions
        )
        presentationTransition = transition
        beginHomeItemsChange(to: presentation)
        let actionsChanged = targetActions != self.compactActions
        if actionsChanged {
            // Keep the source controls alive until the navigation finishes or
            // reverses. Rebuilding them now would make an interactive pop jump.
            outgoingCompactActionButtons = compactActionButtonOrder
            outgoingCompactActionConstraints = compactActionConstraints
            for button in outgoingCompactActionButtons {
                button.isUserInteractionEnabled = false
                button.accessibilityElementsHidden = true
            }
            compactActionButtons = [:]
            compactActionButtonOrder = []
            compactActionConstraints = []
            setCompactActions(targetActions)
        }
        transitionProgressView.layer.removeAllAnimations()
        transitionProgressView.alpha = 0
        let sourceContentPresentation = contentPresentation(for: self.presentation)
        let targetContentPresentation = contentPresentation(for: presentation)
        let transitionUsesCompactActions = sourceContentPresentation == .compactToolbar
            || targetContentPresentation == .compactToolbar
        setCompactActionsHidden(!transitionUsesCompactActions)
        let incomingTransform: CGAffineTransform
        if self.presentation == .empty {
            // The whole toolbar slides back in; its actions must not slide a second time.
            incomingTransform = compactActionsTransform(for: presentation)
        } else if sourceContentPresentation != .compactToolbar {
            // Presentation changes hide actions at the trailing edge in either navigation direction.
            incomingTransform = compactActionsOffscreenTransform(for: compactActionButtonOrder, toward: .trailing)
        } else {
            incomingTransform = compactActionsOffscreenTransform(
                for: compactActionButtonOrder,
                toward: navigationOperation == .pop ? .leading : .trailing
            )
        }
        setCompactActionsTransform(actionsChanged ? incomingTransform : compactActionsTransform(for: self.presentation))
        closeButton.prepareTransition(from: sourceContentPresentation)
        updateHomeItemsAppearance(for: self.presentation)
        startTrackingTransitionProgress()
        return transition.id
    }

    /// Applies the destination state inside the animation block owned by the
    /// external transition coordinator.
    @discardableResult
    public func applyPreparedPresentationTransition(_ transitionID: UUID) -> Bool {
        guard let presentationTransition, presentationTransition.id == transitionID else { return false }
        applyPresentation(
            presentationTransition.target,
            animator: nil
        )
        return true
    }

    /// Finishes only the requested transition; superseded callbacks have no effect.
    @discardableResult
    public func finishPreparedPresentationTransition(_ transitionID: UUID, isCancelled: Bool) -> Bool {
        guard let transition = presentationTransition, transition.id == transitionID else { return false }
        setCompactActions(isCancelled ? transition.sourceActions : transition.targetActions)
        setPresentation(isCancelled ? transition.source : transition.target, animated: false)
        return true
    }

    private func applyPresentation(
        _ presentation: UniversalSearchFieldPresentation,
        animator: UIViewPropertyAnimator?
    ) {
        guard let transition = presentationTransition else { return }
        let contentPresentation = contentPresentation(for: presentation)
        self.presentation = presentation

        updatePresentationConstraints()
        fieldView.setPresentation(contentPresentation, animator: animator)
        closeButton.setPresentation(
            contentPresentation,
            animator: animator
        )

        let updates = {
            guard self.presentationTransition?.id == transition.id else { return }
            self.transform = self.toolbarTransform(for: presentation)
            self.animateHomeItemsAppearance(from: transition.source, to: presentation)
            self.setCompactActionsTransform(self.compactActionsTransform(for: presentation))
            let outgoingTransform = self.compactActionsOffscreenTransform(
                for: self.outgoingCompactActionButtons,
                toward: transition.navigationOperation == .push ? .leading : .trailing
            )
            for button in self.outgoingCompactActionButtons {
                button.transform = presentation == .empty ? .identity : outgoingTransform
            }
            self.transitionProgressView.alpha = 1
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        if let animator {
            animator.addAnimations(updates)
            animator.addCompletion { [weak self] position in
                self?.finishPreparedPresentationTransition(transition.id, isCancelled: position != .end)
            }
        } else {
            updates()
        }
        updateCompactActionsAccessibility(for: presentation)
        updateTrailingButtonAccessibilityLabel()
        updateEmptyAccessibility(for: presentation)
    }

    private func applyStaticPresentation(
        _ presentation: UniversalSearchFieldPresentation
    ) {
        defer { renewGlassTagsIfNeeded() }
        updateEmptyBasePresentation(for: presentation)
        finishPresentationTransition(at: presentation, appliesVisualState: false)

        guard presentation != self.presentation else {
            applyStaticVisualState(for: presentation)
            return
        }
        let contentPresentation = contentPresentation(for: presentation)
        self.presentation = presentation

        updatePresentationConstraints()
        fieldView.setPresentation(contentPresentation, animator: nil)
        applyStaticVisualState(for: presentation)
        updateTrailingButtonAccessibilityLabel()
        updateEmptyAccessibility(for: presentation)
    }

    private func applyStaticVisualState(
        for presentation: UniversalSearchFieldPresentation
    ) {
        let contentPresentation = contentPresentation(for: presentation)
        transitionProgressView.layer.removeAllAnimations()
        transitionProgressView.alpha = 0
        transform = toolbarTransform(for: presentation)
        setCompactActionsHidden(contentPresentation != .compactToolbar)
        setCompactActionsTransform(compactActionsTransform(for: presentation))
        closeButton.applyStaticPresentation(contentPresentation)
        finishHomeItemsAppearance()
        updateCompactActionsAccessibility(for: presentation)
        updateEmptyAccessibility(for: presentation)
    }

    private func updatePresentationConstraints() {
        applyTrailingHandoff()
    }

    /// Places the field for the presentation, between the home toolbar's buttons or as the leading circle a
    /// trailing handoff collapses it into
    private func updateFieldConstraints() {
        let layout = homeLayout
        var leading: CGFloat = 0
        var top: CGFloat = 0
        var trailing: CGFloat?
        var width: CGFloat?
        switch contentPresentation(for: presentation) {
        case .homeToolbar:
            let progress = isTrailingHandoffActive ? trailingHandoffProgress : 0
            leading = layout.fieldLeadingInset * (1 - progress)
            if progress > 0 {
                let fullWidth = max(HomeToolbarLayout.buttonSize, bounds.width - layout.buttonsSpan)
                width = fullWidth + (HomeToolbarLayout.buttonSize - fullWidth) * progress
            } else {
                trailing = layout.fieldTrailingInset
            }
        case .sideToolbar:
            top = layout.fieldLeadingInset
            width = HomeToolbarLayout.buttonSize
        case .compactToolbar:
            width = HomeToolbarLayout.buttonSize
        case .search, .empty:
            trailing = HomeToolbarLayout.buttonSize + 8
        }
        fieldLeadingConstraint.constant = leading
        fieldTopConstraint.constant = top
        if let width {
            fieldTrailingConstraint.isActive = false
            fieldWidthConstraint.constant = width
            fieldWidthConstraint.isActive = true
        } else if let trailing {
            fieldWidthConstraint.isActive = false
            fieldTrailingConstraint.constant = -trailing
            fieldTrailingConstraint.isActive = true
        }
    }

    private func finishPresentationTransition(
        at presentation: UniversalSearchFieldPresentation,
        appliesVisualState: Bool = true
    ) {
        stopTrackingTransitionProgress()
        presentationTransition = nil
        NSLayoutConstraint.deactivate(outgoingCompactActionConstraints)
        outgoingCompactActionConstraints = []
        outgoingCompactActionButtons.forEach { $0.removeFromSuperview() }
        reusableCompactActionButtons.append(contentsOf: outgoingCompactActionButtons)
        outgoingCompactActionButtons = []
        transitionProgressView.layer.removeAllAnimations()
        transitionProgressView.alpha = 0

        guard appliesVisualState, presentation == self.presentation else { return }
        applyStaticVisualState(for: presentation)
    }

    /// Buttons share a background only as glass
    private static var supportsSharedBackground: Bool {
        if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
            return true
        }
        return false
    }

    private var usesSharedActionsBackground: Bool {
        Self.supportsSharedBackground && homeConfiguration.sharesBackground
    }

    private var homeOrder: [HomeToolbarItem] { homeEdit?.order ?? homeConfiguration.order }

    private func isHomeItemConfigured(_ item: HomeToolbarItem) -> Bool {
        if let homeEdit, homeEdit.item == item { return homeEdit.reservesSlot || !item.isHideable }
        return homeConfiguration.isShown(item)
    }

    /// The configured items that fit the home toolbar. A toolbar narrower than the one the configuration was made
    /// on, such as after a rotation, leaves out the buttons last in order rather than squeeze the field away.
    private var shownHomeItems: [HomeToolbarItem] {
        let items = homeOrder.filter(isHomeItemConfigured)
        // The side toolbar is a column, as long as it needs to be
        guard bounds.width > 0, contentPresentation(for: presentation) != .sideToolbar else { return items }
        return HomeToolbarLayout.getFittingItems(items, sharesBackground: usesSharedActionsBackground, length: bounds.width)
    }

    private func isHomeItemShown(_ item: HomeToolbarItem) -> Bool {
        shownHomeItems.contains(item)
    }

    private var homeLayout: HomeToolbarLayout {
        HomeToolbarLayout(items: shownHomeItems, sharesBackground: usesSharedActionsBackground)
    }

    /// The buttons that come and go with the configuration: every item but the field and the actions button
    private static let optionalItems = HomeToolbarItem.allCases.filter(\.isHideable)

    private func getOptionalItemView(_ item: HomeToolbarItem) -> (any HomeToolbarItemView)? {
        item == .accounts ? accountsButton : itemButtons[item]
    }

    private func getHomeItemView(_ item: HomeToolbarItem) -> UIView? {
        switch item {
        case .search: fieldView
        case .actions: closeButton
        default: getOptionalItemView(item)
        }
    }

    /// Creates the buttons of `items` that the toolbar has not shown before, where they wait hidden, so that they
    /// come out of their neighbors when the layout that shows them is applied
    private func prepareHomeItemViews(for items: [HomeToolbarItem]) {
        var hasNewButton = false
        for item in items where item.isHideable && item != .accounts && itemButtons[item] == nil {
            let button = UniversalSearchIconButton(item: item)
            button.onTap = { [weak self] in self?.onHomeItemTap?(item) }
            button.setOverlayAppearance(actionsOverlayAppearance)
            button.setHomeAppearance(showsGlass: false, showsContent: false)
            button.isHidden = true
            contentView.insertSubview(button, aboveSubview: trailingGroupGlass)
            itemButtons[item] = button
            hasNewButton = true
        }
        layoutIfNeeded()
        if hasNewButton {
            UIView.performWithoutAnimation { layoutHomeItems() }
        }
    }

    /// Before an animated change: the buttons the change shows get their glass where they wait, merged into a
    /// neighbor, and the buttons it hides keep theirs until `finishHomeItemsAppearance`. A side that will hold two
    /// buttons or more moves them into its shared glass.
    private func beginHomeItemsChange(to presentation: UniversalSearchFieldPresentation) {
        let visibleItems = materialItems.filter { getOptionalItemView($0)?.isHidden == false }
        if showsHomeActions(in: presentation) {
            materialItems.formUnion(Self.optionalItems.filter(isHomeItemShown))
        }
        UIView.performWithoutAnimation {
            for item in materialItems {
                guard let view = getOptionalItemView(item), view.isHidden else { continue }
                view.isHidden = false
                view.setHomeAppearance(showsGlass: true, showsContent: false)
            }
            for isBeforeField in [true, false] {
                let isGrouped = groupedSides.contains(isBeforeField)
                if wantsGroup(isBeforeField: isBeforeField, in: presentation) {
                    if !isGrouped { enterGroup(isBeforeField: isBeforeField, visibleItems: visibleItems) }
                } else if isGrouped, showsHomeActions(in: presentation), getGroupItems(isBeforeField: isBeforeField).count > 1 {
                    // The buttons part into pieces of their own, which materialize as the shared glass goes
                    groupedSides.remove(isBeforeField)
                }
            }
            updateHomeItemHosts()
        }
        noteJoinedGlass()
    }

    /// The shown buttons on a side of the field, in order
    private func getGroupItems(isBeforeField: Bool) -> [HomeToolbarItem] {
        homeLayout.slots.filter { $0.isBeforeField == isBeforeField }.map(\.item)
    }

    private func getGroupGlass(isBeforeField: Bool) -> UniversalSearchInteractiveGlassView {
        isBeforeField ? leadingGroupGlass : trailingGroupGlass
    }

    private func wantsGroup(isBeforeField: Bool, in presentation: UniversalSearchFieldPresentation) -> Bool {
        usesSharedActionsBackground && showsHomeActions(in: presentation)
            && getGroupItems(isBeforeField: isBeforeField).count > 1
    }

    private func isOnSide(_ item: HomeToolbarItem, isBeforeField: Bool) -> Bool {
        let order = homeOrder
        let isItemBeforeField = (order.firstIndex(of: item) ?? order.count) < (order.firstIndex(of: .search) ?? 0)
        return isItemBeforeField == isBeforeField
    }

    /// Moves a side's buttons into its shared glass, which starts where their own glass is. One piece of glass or
    /// none hands over at once; several pieces merge with the change that follows.
    private func enterGroup(isBeforeField: Bool, visibleItems: Set<HomeToolbarItem>) {
        let glass = getGroupGlass(isBeforeField: isBeforeField)
        let layout = homeLayout
        let items = HomeToolbarItem.allCases.filter {
            $0 != .search && isOnSide($0, isBeforeField: isBeforeField)
                && ($0 == .actions ? belongsInGroup($0, layout: layout) : materialItems.contains($0))
        }
        let pieces = items.filter { $0 == .actions ? closeButton.isBackgroundVisible : visibleItems.contains($0) }
        // Buttons that are not showing wait under the ones that are
        let views = (pieces.isEmpty ? items : pieces).compactMap(getHomeItemView)
        glass.isHidden = false
        glass.frame = views.reduce(CGRect.null) { $0.union($1.convert($1.bounds, to: contentView)) }
        glass.layoutIfNeeded()
        groupedSides.insert(isBeforeField)
        updateHomeItemHosts()
        if pieces.count <= 1 {
            glass.setEffectVisible(true)
            updateOwnGlass()
        } else {
            glass.setEffectVisible(false)
        }
    }

    /// Puts every button where it belongs: inside its side's shared glass, or straight in the toolbar
    private func updateHomeItemHosts() {
        let layout = homeLayout
        var hasMovedView = false
        for item in HomeToolbarItem.allCases where item != .search {
            guard let view = getHomeItemView(item) else { continue }
            let isBeforeField = isOnSide(item, isBeforeField: true)
            let isHosted = groupedSides.contains(isBeforeField) && belongsInGroup(item, layout: layout)
            let host = isHosted ? getGroupGlass(isBeforeField: isBeforeField).contentView : contentView
            guard let superview = view.superview, superview !== host else { continue }
            let center = host.convert(view.center, from: superview)
            host.addSubview(view)
            view.center = center
            hasMovedView = true
        }
        if hasMovedView {
            // The trailing button stays above the ones that gather under it
            closeButton.superview?.bringSubviewToFront(closeButton)
        }
    }

    /// Whether the button for `item` goes inside its side's shared glass while the side has one
    private func belongsInGroup(_ item: HomeToolbarItem, layout: HomeToolbarLayout) -> Bool {
        if item == .actions { return !isTrailingButtonApart }
        return layout.slot(for: item) != nil || materialItems.contains(item)
    }

    /// Whether the trailing button keeps out of the shared glass of the buttons before the field: search has it at
    /// the end of the toolbar, so on its way there it parts from them in its own glass, and on its way back joins
    /// them once it is in its place
    private var isTrailingButtonApart: Bool {
        let presentations = presentationTransition.map { [$0.source, $0.target] } ?? [presentation]
        return isOnSide(.actions, isBeforeField: true)
            && presentations.contains { contentPresentation(for: $0) == .search }
    }

    private func isInSharedGlass(_ view: UIView) -> Bool {
        view.superview !== contentView
    }

    /// A button's own glass shows while it is not inside a shared one
    private func updateOwnGlass() {
        for item in Self.optionalItems {
            guard let view = getOptionalItemView(item) else { continue }
            view.setHomeAppearance(
                showsGlass: materialItems.contains(item) && !isInSharedGlass(view),
                showsContent: view.showsHomeContent
            )
        }
        updateTrailingButtonGlass(for: presentation)
    }

    private func updateTrailingButtonGlass(for presentation: UniversalSearchFieldPresentation) {
        closeButton.setBackgroundVisible(
            (contentPresentation(for: presentation) != .compactToolbar || presentationTransition != nil)
                && !isInSharedGlass(closeButton)
        )
    }

    private func updateHomeItemsAppearance(for presentation: UniversalSearchFieldPresentation) {
        let isHome = showsHomeActions(in: presentation)
        let isHandingOff = homeActionsFold > 0
        for item in Self.optionalItems {
            guard let view = getOptionalItemView(item) else { continue }
            let isShown = isHome && isHomeItemShown(item)
            let isEmpty = homeEdit?.item == item || homeLandingItem == item
            view.setHomeAppearance(
                showsGlass: materialItems.contains(item) && !isInSharedGlass(view),
                showsContent: isShown && !isEmpty
            )
            view.isUserInteractionEnabled = isShown && presentation != .empty && !isHandingOff && homeEdit == nil
            view.accessibilityElementsHidden = !view.isUserInteractionEnabled
        }
        updateTrailingButtonGlass(for: presentation)
        for isBeforeField in [true, false] {
            getGroupGlass(isBeforeField: isBeforeField)
                .setEffectVisible(groupedSides.contains(isBeforeField), inheritsAnimation: true)
        }
    }

    /// Inside a presentation change's animation: the buttons' content leaves in its first half and arrives in its
    /// second, so that it doesn't cross the field's content while their glass merges into what they gather under
    private func animateHomeItemsAppearance(
        from source: UniversalSearchFieldPresentation,
        to target: UniversalSearchFieldPresentation
    ) {
        let isArriving = showsHomeActions(in: target) && !showsHomeActions(in: source)
        UIView.animateKeyframes(withDuration: 0, delay: 0) {
            UIView.addKeyframe(withRelativeStartTime: isArriving ? 0.5 : 0, relativeDuration: 0.5) {
                self.updateHomeItemsAppearance(for: target)
            }
        }
    }

    private func finishHomeItemsAppearance() {
        materialItems = showsHomeActions(in: presentation) ? Set(Self.optionalItems.filter(isHomeItemShown)) : []
        UIView.performWithoutAnimation {
            groupedSides = Set([true, false].filter { wantsGroup(isBeforeField: $0, in: presentation) })
            updateHomeItemHosts()
            for isBeforeField in [true, false] {
                getGroupGlass(isBeforeField: isBeforeField).isHidden = !groupedSides.contains(isBeforeField)
            }
            updateHomeItemsAppearance(for: presentation)
            for item in Self.optionalItems {
                getOptionalItemView(item)?.isHidden = !materialItems.contains(item)
            }
            layoutHomeItems()
        }
        noteJoinedGlass()
        if let configuration = pendingHomeConfiguration, presentationTransition == nil {
            pendingHomeConfiguration = nil
            setHomeConfiguration(configuration, animated: window != nil)
        }
    }

    /// Places the buttons: on the home toolbar in their order around the field, and otherwise gathered under the
    /// field's leading end or the trailing button, which they come out of when the home toolbar returns. A side's
    /// shared glass spans its shown buttons.
    private func layoutHomeItems() {
        UIView.performWithoutAnimation { updateHomeItemHosts() }
        let content = contentPresentation(for: presentation)
        let isVertical = content == .sideToolbar
        let isHome = content == .homeToolbar || isVertical
        let layout = homeLayout
        let order = homeOrder
        let size = HomeToolbarLayout.buttonSize
        let length = isVertical ? bounds.height : bounds.width
        let fold = content == .homeToolbar ? homeActionsFold : 0
        let fieldIndex = order.firstIndex(of: .search) ?? 0
        var starts: [HomeToolbarItem: CGFloat] = [:]
        // A side's shared glass goes wherever its buttons do, so that it merges into what they gather under
        var groupSpans: [Bool: ClosedRange<CGFloat>] = [:]
        for item in HomeToolbarItem.allCases where item != .search {
            let isBeforeField = (order.firstIndex(of: item) ?? order.count) < fieldIndex
            let start: CGFloat
            if isHome, let slot = layout.slot(for: item) {
                let restingStart = layout.getStart(of: slot, length: length)
                let foldedStart = slot.isBeforeField ? 0 : length - size
                start = restingStart + (foldedStart - restingStart) * fold
            } else if isHome {
                start = getWaitingStart(of: item, in: order, layout: layout, length: length)
            } else if content == .search, item == .actions || !isBeforeField {
                start = length - size
            } else {
                start = 0
            }
            starts[item] = start
            // A trailing button on its way to join the shared glass already has its place in it
            let isInSpan = item == .actions && isHome || belongsInGroup(item, layout: layout)
            if isInSpan {
                let span = groupSpans[isBeforeField] ?? start...start
                groupSpans[isBeforeField] = min(span.lowerBound, start)...max(span.upperBound, start + size)
            }
        }
        for isBeforeField in [true, false] where groupedSides.contains(isBeforeField) {
            let glass = getGroupGlass(isBeforeField: isBeforeField)
            let span = groupSpans[isBeforeField] ?? (isBeforeField ? 0...size : (length - size)...length)
            glass.frame = getItemFrame(start: span.lowerBound, length: span.upperBound - span.lowerBound, isVertical: isVertical)
            glass.layoutIfNeeded()
        }
        for (item, start) in starts {
            guard let view = getHomeItemView(item), let superview = view.superview else { continue }
            let frame = getItemFrame(start: start, length: size, isVertical: isVertical)
            view.bounds.size = frame.size
            view.center = superview.convert(CGPoint(x: frame.midX, y: frame.midY), from: contentView)
            view.layoutIfNeeded()
            getZoomAnchorView(for: item).frame = frame
        }
    }

    /// The plain view that keeps the place of the button for `item`, behind the toolbar's glass
    private func getZoomAnchorView(for item: HomeToolbarItem) -> UIView {
        if let view = zoomAnchorViews[item] { return view }
        let view = UIView()
        view.isUserInteractionEnabled = false
        contentView.insertSubview(view, at: 0)
        zoomAnchorViews[item] = view
        return view
    }

    /// The frame in the toolbar of a span of buttons along its axis
    private func getItemFrame(start: CGFloat, length: CGFloat, isVertical: Bool) -> CGRect {
        let size = HomeToolbarLayout.buttonSize
        if isVertical {
            return CGRect(x: 0, y: start, width: size, height: length)
        }
        var frame = getDirectionalFrame(start: start, length: length)
        frame.size.height = size
        return frame
    }

    /// Where a hidden button waits: on the shown button after it on its side of the field, else on the one before
    /// it, else under the field's end
    private func getWaitingStart(
        of item: HomeToolbarItem,
        in order: [HomeToolbarItem],
        layout: HomeToolbarLayout,
        length: CGFloat
    ) -> CGFloat {
        let fieldIndex = order.firstIndex(of: .search) ?? 0
        let index = order.firstIndex(of: item) ?? order.count
        let isBeforeField = index < fieldIndex
        let side = isBeforeField ? Array(order[..<fieldIndex]) : Array(order[(fieldIndex + 1)...])
        let sideIndex = isBeforeField ? index : index - fieldIndex - 1
        let neighbors = side.suffix(from: min(side.count, sideIndex + 1)) + side.prefix(max(0, sideIndex)).reversed()
        if let slot = neighbors.lazy.compactMap({ layout.slot(for: $0) }).first {
            return layout.getStart(of: slot, length: length)
        }
        return isBeforeField ? 0 : length - HomeToolbarLayout.buttonSize
    }

    private func getDirectionalFrame(start: CGFloat, length: CGFloat) -> CGRect {
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        return CGRect(x: isRightToLeft ? bounds.width - start - length : start, y: 0, width: length, height: bounds.height)
    }

    private static let jiggleAnimationKey = "homeToolbarJiggle"

    /// While a drag rearranges the toolbar its buttons wiggle, and their glass stops reacting to the finger
    private func setHomeItemsEditing(_ isEditing: Bool) {
        fieldView.setGlassInteractive(!isEditing)
        closeButton.setGlassInteractive(!isEditing)
        leadingGroupGlass.setInteractive(!isEditing)
        trailingGroupGlass.setInteractive(!isEditing)
        for item in Self.optionalItems {
            getOptionalItemView(item)?.setGlassInteractive(!isEditing)
        }
        setHomeItemsJiggling(isEditing)
    }

    private func setHomeItemsJiggling(_ isJiggling: Bool) {
        let layers = Self.optionalItems.compactMap { getOptionalItemView($0)?.jiggleLayer } + [closeButton.jiggleLayer]
        for (index, layer) in layers.enumerated() {
            guard isJiggling, !UIAccessibility.isReduceMotionEnabled else {
                layer.removeAnimation(forKey: Self.jiggleAnimationKey)
                continue
            }
            guard layer.animation(forKey: Self.jiggleAnimationKey) == nil else { continue }
            let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            animation.values = [-0.07, 0.07, -0.07]
            animation.duration = 0.26
            animation.repeatCount = .infinity
            animation.timeOffset = 0.26 * Double(index % 3) / 3
            animation.timingFunctions = [
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .easeInEaseOut),
            ]
            layer.add(animation, forKey: Self.jiggleAnimationKey)
        }
    }

    private func showsHomeActions(in presentation: UniversalSearchFieldPresentation) -> Bool {
        let content = contentPresentation(for: presentation)
        return content == .homeToolbar || content == .sideToolbar
    }

    private func compactActionsTransform(
        for presentation: UniversalSearchFieldPresentation
    ) -> CGAffineTransform {
        guard contentPresentation(for: presentation) != .compactToolbar else { return .identity }
        return compactActionsOffscreenTransform(for: compactActionButtonOrder, toward: .trailing)
    }

    private enum HorizontalEdge {
        case leading, trailing
    }

    private func compactActionsOffscreenTransform(
        for buttons: [UniversalSearchToolbarActionButton],
        toward edge: HorizontalEdge
    ) -> CGAffineTransform {
        let contentBounds = buttons.reduce(CGRect.null) { result, button in
            // Ignore the previous transition's transform when measuring the group.
            let frame = button.bounds.offsetBy(
                dx: button.center.x - button.bounds.midX,
                dy: button.center.y - button.bounds.midY
            )
            return result.union(contentView.convert(frame, to: self))
        }
        guard !contentBounds.isNull else { return .identity }
        return offscreenTransform(for: contentBounds, toward: edge)
    }

    private func offscreenTransform(for contentBounds: CGRect, toward edge: HorizontalEdge) -> CGAffineTransform {
        let viewportBounds: CGRect
        if let superview {
            let viewport = transitionViewportView ?? window ?? superview
            // Convert through the parent so an already hidden toolbar does not
            // feed its own translation back into the next layout calculation.
            viewportBounds = superview.convert(viewport.bounds, from: viewport).offsetBy(
                dx: bounds.midX - center.x,
                dy: bounds.midY - center.y
            )
        } else {
            viewportBounds = bounds
        }
        let exitsLeft = (edge == .leading) != (effectiveUserInterfaceLayoutDirection == .rightToLeft)
        let shadowClearance: CGFloat = 32
        return CGAffineTransform(
            translationX: exitsLeft
                ? viewportBounds.minX - contentBounds.maxX - shadowClearance
                : viewportBounds.maxX - contentBounds.minX + shadowClearance,
            y: 0
        )
    }

    private func contentPresentation(
        for presentation: UniversalSearchFieldPresentation
    ) -> UniversalSearchFieldPresentation {
        presentation == .empty ? emptyBasePresentation : presentation
    }

    private func updateEmptyBasePresentation(
        for targetPresentation: UniversalSearchFieldPresentation
    ) {
        guard targetPresentation == .empty, presentation != .empty else { return }
        emptyBasePresentation = contentPresentation(for: presentation)
    }

    private func toolbarTransform(
        for presentation: UniversalSearchFieldPresentation
    ) -> CGAffineTransform {
        guard presentation == .empty, !shouldKeepPlaceWhenEmpty else { return .identity }
        return offscreenTransform(for: bounds, toward: .leading)
    }

    private func setCompactActionsTransform(_ transform: CGAffineTransform) {
        for button in compactActionButtonOrder {
            button.transform = transform
        }
    }

    private func setCompactActionsHidden(_ isHidden: Bool) {
        for button in compactActionButtonOrder {
            button.isHidden = isHidden
        }
    }

    private func updateCompactActionsAccessibility(
        for presentation: UniversalSearchFieldPresentation
    ) {
        let isCompact = presentation == .compactToolbar
        for button in compactActionButtonOrder {
            button.isUserInteractionEnabled = isCompact
            button.accessibilityElementsHidden = !isCompact
        }
    }

    private func updateEmptyAccessibility(
        for presentation: UniversalSearchFieldPresentation
    ) {
        let isEmpty = presentation == .empty
        isUserInteractionEnabled = !isEmpty
        accessibilityElementsHidden = isEmpty
    }

    private func startTrackingTransitionProgress() {
        stopTrackingTransitionProgress()
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(updateTransitionProgress)
        )
        displayLink.add(to: .main, forMode: .common)
        transitionDisplayLink = displayLink
    }

    private func stopTrackingTransitionProgress() {
        transitionDisplayLink?.invalidate()
        transitionDisplayLink = nil
    }

    @objc private func updateTransitionProgress() {
        guard let transition = presentationTransition else {
            stopTrackingTransitionProgress()
            return
        }
        guard let opacity = transitionProgressView.layer.presentation()?.opacity else {
            return
        }
        closeButton.setTransitionProgress(
            min(1, max(0, CGFloat(opacity))),
            from: contentPresentation(for: transition.source),
            to: contentPresentation(for: transition.target)
        )
    }

    private func setupLayout() {
        if let glassContainerView {
            glassContainerView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glassContainerView)
            NSLayoutConstraint.activate([
                glassContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                glassContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                glassContainerView.topAnchor.constraint(equalTo: topAnchor),
                glassContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        } else {
            contentView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(contentView)
            NSLayoutConstraint.activate([
                contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
                contentView.topAnchor.constraint(equalTo: topAnchor),
                contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        fieldView.translatesAutoresizingMaskIntoConstraints = false
        transitionProgressView.translatesAutoresizingMaskIntoConstraints = false
        transitionProgressView.isUserInteractionEnabled = false
        contentView.addSubview(fieldView)
        for glass in [leadingGroupGlass, trailingGroupGlass] {
            glass.translatesAutoresizingMaskIntoConstraints = true
            glass.setEffectVisible(false)
            glass.isHidden = true
            contentView.addSubview(glass)
        }
        // `layoutHomeItems` places the buttons. The trailing button stays above the ones that gather under it.
        accountsButton.translatesAutoresizingMaskIntoConstraints = true
        accountsButton.isHidden = true
        accountsButton.setToolbarAppearance(showsBackground: false, showsContent: false)
        contentView.addSubview(accountsButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = true
        contentView.addSubview(closeButton)
        contentView.addSubview(transitionProgressView)

        fieldLeadingConstraint = fieldView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        fieldTopConstraint = fieldView.topAnchor.constraint(equalTo: contentView.topAnchor)
        fieldTrailingConstraint = fieldView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        fieldWidthConstraint = fieldView.widthAnchor.constraint(equalToConstant: HomeToolbarLayout.buttonSize)
        NSLayoutConstraint.activate([
            fieldLeadingConstraint,
            fieldTopConstraint,
            fieldTrailingConstraint,
            fieldView.heightAnchor.constraint(equalToConstant: 48),

            transitionProgressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            transitionProgressView.topAnchor.constraint(equalTo: contentView.topAnchor),
            transitionProgressView.widthAnchor.constraint(equalToConstant: 1),
            transitionProgressView.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    public override func layoutSubviews() {
        if isTrailingHandoffActive {
            let fullWidth = max(HomeToolbarLayout.buttonSize, bounds.width - homeLayout.buttonsSpan)
            let width = fullWidth + (HomeToolbarLayout.buttonSize - fullWidth) * trailingHandoffProgress
            if abs(fieldWidthConstraint.constant - width) > 0.25 { updateFieldConstraints() }
        }
        if presentationTransition == nil, configurationAnimationID == nil {
            let items = shownHomeItems
            if items != laidOutHomeItems {
                laidOutHomeItems = items
                updateFieldConstraints()
                finishHomeItemsAppearance()
            }
        }
        super.layoutSubviews()
        layoutHomeItems()
        if presentationTransition == nil {
            transform = toolbarTransform(for: presentation)
            setCompactActionsTransform(compactActionsTransform(for: presentation))
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopTrackingTransitionProgress()
        }
    }

    private func setupCallbacks() {
        accountsButton.accessibilityIdentifier = "home_accounts_button"
        accountsButton.addAction(UIAction { [weak self] _ in self?.onAccountsTap?() }, for: .touchUpInside)
        fieldView.onTextChange = { [weak self] text in
            guard let self else { return }
            storedConfiguration.text = text
            onTextChange?(text)
        }
        fieldView.onReturn = { [weak self] text in
            self?.onReturn?(text)
        }
        fieldView.onEditingChange = { [weak self] isEditing in
            self?.onEditingChange?(isEditing)
        }
        fieldView.onMicrophoneTap = { [weak self] in
            self?.onMicrophoneTap?()
        }
        fieldView.onActivate = { [weak self] in
            self?.onActivate?()
        }
        closeButton.onTap = { [weak self] in
            guard let self else { return }
            switch presentation {
            case .homeToolbar, .sideToolbar:
                onActionsTap?()
            case .compactToolbar:
                break
            case .search:
                onCloseTap?()
            case .empty:
                break
            }
        }
    }

    private func updateTrailingButtonAccessibilityLabel() {
        switch presentation {
        case .homeToolbar, .sideToolbar:
            closeButton.buttonAccessibilityLabel = actionsAccessibilityLabel
            closeButton.buttonAccessibilityIdentifier = "home_more_actions_button"
            closeButton.accessibilityElementsHidden = false
            closeButton.isUserInteractionEnabled = true
        case .compactToolbar:
            closeButton.buttonAccessibilityLabel = nil
            closeButton.buttonAccessibilityIdentifier = nil
            closeButton.accessibilityElementsHidden = true
            closeButton.isUserInteractionEnabled = false
        case .search:
            closeButton.buttonAccessibilityLabel = closeAccessibilityLabel
            closeButton.buttonAccessibilityIdentifier = nil
            closeButton.accessibilityElementsHidden = false
            closeButton.isUserInteractionEnabled = true
        case .empty:
            closeButton.buttonAccessibilityLabel = nil
            closeButton.buttonAccessibilityIdentifier = nil
            closeButton.accessibilityElementsHidden = true
            closeButton.isUserInteractionEnabled = false
        }
        if isTrailingHandoffActive {
            closeButton.accessibilityElementsHidden = true
            closeButton.isUserInteractionEnabled = false
        }
    }

    private func rebuildCompactActions(with actions: [SharedBottomToolbarAction]) {
        NSLayoutConstraint.deactivate(compactActionConstraints)
        compactActionConstraints.removeAll()
        compactActionButtonOrder.forEach { $0.removeFromSuperview() }
        compactActionButtonOrder.removeAll()

        let desiredIDs = Set(actions.map(\.id))
        let removedIDs = compactActionButtons.keys.filter { !desiredIDs.contains($0) }
        for id in removedIDs {
            guard let button = compactActionButtons.removeValue(forKey: id) else { continue }
            button.removeFromSuperview()
            reusableCompactActionButtons.append(button)
        }

        for action in actions {
            let button = compactActionButtons[action.id] ?? dequeueCompactActionButton()
            compactActionButtons[action.id] = button
            button.configure(with: action)
            button.onTap = { [weak self] in
                self?.onToolbarActionTap?(action.id)
            }
            button.translatesAutoresizingMaskIntoConstraints = false
            contentView.insertSubview(button, aboveSubview: fieldView)
            compactActionButtonOrder.append(button)
        }
        noteJoinedGlass()

        guard let firstButton = compactActionButtonOrder.first else { return }
        for (index, button) in compactActionButtonOrder.enumerated() {
            compactActionConstraints.append(contentsOf: [
                button.topAnchor.constraint(equalTo: contentView.topAnchor),
                button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
            if index == 0 {
                compactActionConstraints.append(
                    button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 56)
                )
            } else {
                let previousButton = compactActionButtonOrder[index - 1]
                compactActionConstraints.append(contentsOf: [
                    button.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 8),
                    button.widthAnchor.constraint(equalTo: firstButton.widthAnchor),
                ])
            }
        }
        compactActionConstraints.append(
            compactActionButtonOrder.last!.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        )
        NSLayoutConstraint.activate(compactActionConstraints)

        let isCompact = presentation == .compactToolbar
        setCompactActionsHidden(!isCompact && presentationTransition == nil)
        updateCompactActionsAccessibility(for: presentation)
        if presentationTransition == nil {
            setCompactActionsTransform(compactActionsTransform(for: presentation))
        }
    }

    private func dequeueCompactActionButton() -> UniversalSearchToolbarActionButton {
        guard let button = reusableCompactActionButtons.popLast() else { return UniversalSearchToolbarActionButton() }
        removeAnimations(in: button.layer)
        button.transform = .identity
        return button
    }

    /// Clears animations a superseded transition left on a view it no longer shows
    private func removeAnimations(in layer: CALayer) {
        layer.removeAllAnimations()
        layer.sublayers?.forEach(removeAnimations)
    }

    private func noteJoinedGlass() {
        guard glassContainerView != nil else { return }
        joinedGlassViews.formUnion(effectViewIDs(in: contentView))
    }

    /// Gives the glass container a new tag table once enough glass views joined it. UIKit tags each glass view that
    /// joins a container with one of 63 bits and never frees them; tinted glass that joins without a free bit draws its
    /// tint over every shape in the container. Setting the effect again starts a new table, so this waits until no
    /// tinted glass or morph is on screen.
    private func renewGlassTagsIfNeeded() {
        guard let glassContainerView, let effect = glassContainerView.effect else { return }
        noteJoinedGlass()
        guard joinedGlassViews.count >= Self.glassTagBudget, presentationTransition == nil, configurationAnimationID == nil,
              showsHomeActions(in: presentation), !isTrailingHandoffActive, !isTrailingButtonHandedOff,
              !shouldKeepPlaceWhenEmpty, hostedGlassViews().isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            glassContainerView.effect = nil
            glassContainerView.effect = effect
        }
        CATransaction.commit()
        joinedGlassViews = effectViewIDs(in: contentView)
    }

    private func effectViewIDs(in view: UIView) -> Set<ObjectIdentifier> {
        view.subviews.reduce(into: Set<ObjectIdentifier>()) { ids, subview in
            if subview is UIVisualEffectView { ids.insert(ObjectIdentifier(subview)) }
            ids.formUnion(effectViewIDs(in: subview))
        }
    }
}

@MainActor
private final class UniversalSearchFieldCapsuleView: UIView, UITextFieldDelegate {
    var onActivate: (() -> Void)?
    var onTextChange: ((String) -> Void)?
    var onEditingChange: ((Bool) -> Void)?
    var onReturn: ((String) -> Void)?
    var onMicrophoneTap: (() -> Void)?

    func setOverlayAppearance(_ appearance: ContentOverlayAppearance, animated: Bool) {
        let updates = {
            self.overrideUserInterfaceStyle = appearance.userInterfaceStyle
            self.glassView.setUsesClearGlass(appearance.usesClearGlass)
            self.magnifyingGlass.tintColor = appearance.foregroundColor ?? .label
        }
        if animated {
            UIView.transition(with: magnifyingGlass, duration: 0.25,
                              options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent], animations: updates)
        } else { updates() }
    }

    func setGlassInteractive(_ isInteractive: Bool) {
        glassView.setInteractive(isInteractive)
    }

    var compactAccessibilityIdentifier: String? {
        didSet { updatePresentationAccessibility() }
    }

    var microphoneAccessibilityLabel: String = lang("$universal_search_dictate") {
        didSet {
            if !microphoneButton.isHidden {
                microphoneButton.accessibilityLabel = microphoneAccessibilityLabel
            }
        }
    }

    var clearAccessibilityLabel: String = lang("$universal_search_clear_text") {
        didSet {
            if !clearButton.isHidden {
                clearButton.accessibilityLabel = clearAccessibilityLabel
            }
        }
    }

    var text: String { textField.text ?? "" }
    var isEditing: Bool { textField.isFirstResponder }

    // Figma's SF Pro `tracking: -0.45px` resolves to this Core Text kern.
    private static let textKern: CGFloat = 0.05

    private var configuration = UniversalSearchFieldConfiguration(placeholder: "")
    private var suppressesAutocompleteUntilNextInsertion = false
    private var ignoredSelectionChangeCount = 0
    private var expectedTextAfterUserEdit: String?
    private var expectedSelectionAfterUserEdit: NSRange?
    private let glassView = UniversalSearchInteractiveGlassView()
    private let magnifyingGlass = UIImageView(image: UIImage(
        systemName: "magnifyingglass",
        withConfiguration: UIImage.SymbolConfiguration(
            font: WTypography.uiFont(.supportingEmphasized, content: .technical)
        )
    ))
    private let textField = UITextField()
    private let fullPlaceholderView = UIView()
    private let shortPlaceholderView = UIView()
    private let fullPlaceholderLabel = UILabel()
    private let shortPlaceholderLabel = UILabel()
    private let autocompleteView = UniversalSearchAutocompleteView()
    private let microphoneButton = UniversalSearchSymbolButton()
    private let clearButton = UniversalSearchSymbolButton()

    private var textToMicrophoneConstraint: NSLayoutConstraint!
    private var textToClearConstraint: NSLayoutConstraint!
    private var textToTrailingConstraint: NSLayoutConstraint!
    private var textFieldLeadingConstraint: NSLayoutConstraint!
    private var textFieldCompactWidthConstraint: NSLayoutConstraint!
    private var presentation: UniversalSearchFieldPresentation = .search
    private var handoffProgress: CGFloat = 0
    private var isHandoffCollapsed = false

    private var textAlphaForPresentation: CGFloat {
        let isCompact = presentation == .compactToolbar || presentation == .sideToolbar
        return isCompact ? 0 : max(0, 1 - handoffProgress / 0.4)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with configuration: UniversalSearchFieldConfiguration) {
        self.configuration = configuration
        if textField.text != configuration.text {
            suppressesAutocompleteUntilNextInsertion = false
            ignoreSelectionChangesUntilNextRunLoop()
            textField.attributedText = attributedText(configuration.text, color: .label)
        }
        updateDefaultTextAttributes()
        updatePlaceholder()
        updateAccessory()
        updateAutocomplete()
    }

    @discardableResult
    func focus() -> Bool {
        ignoreSelectionChangesUntilNextRunLoop()
        return textField.becomeFirstResponder()
    }

    @discardableResult
    func endEditing() -> Bool {
        textField.resignFirstResponder()
    }

    /// Fades the capsule for a host's handoff: its content by alpha, its glass by materializing
    func setHandoffAlpha(_ alpha: CGFloat) {
        glassView.contentView.alpha = alpha
        glassView.setMaterialized(alpha > 0.5)
    }

    /// The magnifying glass grows as the field becomes the search circle, to the circle's icon size
    private var handoffIconTransform: CGAffineTransform {
        let scale = 1 + 0.2 * min(1, max(0, handoffProgress))
        return scale == 1 ? .identity : CGAffineTransform(scaleX: scale, y: scale)
    }

    func setHandoff(progress: CGFloat, isCollapsed: Bool) {
        handoffProgress = progress
        if presentation != .search {
            magnifyingGlass.transform = handoffIconTransform
        }
        let alpha = textAlphaForPresentation
        textField.alpha = alpha
        autocompleteView.alpha = alpha
        microphoneButton.alpha = alpha
        clearButton.alpha = alpha
        if isHandoffCollapsed != isCollapsed {
            isHandoffCollapsed = isCollapsed
            updateAccessory()
        }
    }

    func setPresentation(
        _ presentation: UniversalSearchFieldPresentation,
        animator: UIViewPropertyAnimator?
    ) {
        guard presentation != self.presentation else { return }
        self.presentation = presentation
        let isSearch = presentation == .search
        let isCompact = presentation == .compactToolbar || presentation == .sideToolbar
        textFieldLeadingConstraint.constant = isSearch ? 16 : 44
        updateAccessory()
        textField.isUserInteractionEnabled = isSearch
        magnifyingGlass.isHidden = false

        let transformDirection: CGFloat = effectiveUserInterfaceLayoutDirection == .rightToLeft ? 1 : -1
        let updates = {
            self.magnifyingGlass.alpha = isSearch ? 0 : 1
            self.magnifyingGlass.transform = isSearch
                ? CGAffineTransform(translationX: transformDirection * 12, y: 0)
                : self.handoffIconTransform
            let textAlpha = self.textAlphaForPresentation
            self.textField.alpha = textAlpha
            self.textField.transform = isCompact
                ? CGAffineTransform(translationX: -transformDirection * 10, y: 0)
                : .identity
            self.autocompleteView.alpha = textAlpha
            self.microphoneButton.alpha = textAlpha
            self.clearButton.alpha = textAlpha
            self.layoutIfNeeded()
        }
        updatePresentationAccessibility()

        guard let animator else {
            updates()
            magnifyingGlass.isHidden = isSearch
            return
        }
        animator.addAnimations(updates)
        animator.addCompletion { [weak self] _ in
            guard let self, self.presentation == presentation else { return }
            magnifyingGlass.isHidden = isSearch
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView.layoutIfNeeded()
        updatePlaceholder()
        updateAutocompleteGeometry()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        textField.tintColor = autocompleteView.isShowingAutocomplete ? .clear : tintColor
        autocompleteView.actionTintColor = tintColor
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)

        textField.translatesAutoresizingMaskIntoConstraints = false
        // The buttons beside the field decide its width; a long placeholder must not widen the toolbar
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.delegate = self
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.clearButtonMode = .never
        textField.textAlignment = .natural
        textField.keyboardType = .webSearch
        textField.returnKeyType = .go
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.smartInsertDeleteType = .no
        textField.accessibilityTraits.insert(.searchField)
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)

        for (view, label) in [(fullPlaceholderView, fullPlaceholderLabel), (shortPlaceholderView, shortPlaceholderLabel)] {
            view.isUserInteractionEnabled = false
            label.isAccessibilityElement = false
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(label)
            textField.addSubview(view)
        }

        autocompleteView.translatesAutoresizingMaskIntoConstraints = false
        autocompleteView.isUserInteractionEnabled = false

        configureAccessoryButton(
            microphoneButton,
            systemName: "microphone",
            weight: .medium,
            action: #selector(microphoneTapped)
        )
        microphoneButton.tintColor = .secondaryLabel

        configureAccessoryButton(
            clearButton,
            systemName: "xmark.circle.fill",
            weight: .regular,
            action: #selector(clearTapped)
        )
        clearButton.tintColor = .label

        glassView.contentView.addSubview(textField)
        glassView.contentView.addSubview(magnifyingGlass)
        glassView.contentView.addSubview(autocompleteView)
        glassView.contentView.addSubview(microphoneButton)
        glassView.contentView.addSubview(clearButton)

        let focusGesture = UITapGestureRecognizer(target: self, action: #selector(fieldTapped))
        focusGesture.cancelsTouchesInView = false
        addGestureRecognizer(focusGesture)

        textToMicrophoneConstraint = textField.trailingAnchor.constraint(
            equalTo: microphoneButton.leadingAnchor,
            constant: -8
        )
        textToClearConstraint = textField.trailingAnchor.constraint(
            equalTo: clearButton.leadingAnchor,
            constant: -8
        )
        textToTrailingConstraint = textField.trailingAnchor.constraint(
            equalTo: glassView.contentView.trailingAnchor,
            constant: -14
        )

        magnifyingGlass.translatesAutoresizingMaskIntoConstraints = false
        magnifyingGlass.tintColor = .label
        magnifyingGlass.contentMode = .scaleAspectFit
        textFieldLeadingConstraint = textField.leadingAnchor.constraint(
            equalTo: glassView.contentView.leadingAnchor,
            constant: 16
        )
        textFieldCompactWidthConstraint = textField.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            textFieldLeadingConstraint,
            textField.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 24),

            magnifyingGlass.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 14),
            // The symbol's image sits a little low for its glyph
            magnifyingGlass.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor, constant: -1),
            magnifyingGlass.widthAnchor.constraint(equalToConstant: 20),
            magnifyingGlass.heightAnchor.constraint(equalToConstant: 20),

            autocompleteView.leadingAnchor.constraint(equalTo: textField.leadingAnchor),
            autocompleteView.trailingAnchor.constraint(equalTo: textField.trailingAnchor),
            autocompleteView.topAnchor.constraint(equalTo: textField.topAnchor),
            autocompleteView.bottomAnchor.constraint(equalTo: textField.bottomAnchor),

            microphoneButton.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -14),
            microphoneButton.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),
            microphoneButton.widthAnchor.constraint(equalToConstant: 18),
            microphoneButton.heightAnchor.constraint(equalToConstant: 20),

            clearButton.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -12),
            clearButton.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 20),
            clearButton.heightAnchor.constraint(equalToConstant: 22),
        ])

        microphoneButton.accessibilityLabel = microphoneAccessibilityLabel
        clearButton.accessibilityLabel = clearAccessibilityLabel
        updateDefaultTextAttributes()
        magnifyingGlass.isHidden = true
    }

    private func configureAccessoryButton(
        _ button: UniversalSearchSymbolButton,
        systemName: String,
        weight: UIImage.SymbolWeight,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setSymbol(
            systemName,
            configuration: UIImage.SymbolConfiguration(pointSize: 17, weight: weight)
        )
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func updateDefaultTextAttributes() {
        textField.defaultTextAttributes = [
            .font: WTypography.uiFont(.body),
            .foregroundColor: UIColor.label,
            .kern: Self.textKern,
        ]
        textField.tintColor = tintColor
    }

    private func updatePlaceholder() {
        let fullPlaceholder = attributedText(configuration.placeholder, color: .tertiaryLabel)
        let shortPlaceholder = attributedText(configuration.shortPlaceholder ?? configuration.placeholder, color: .tertiaryLabel)
        // Glass may defer laying out its content view until the transition ends.
        // Measure with the field's destination constraints, not its stale bounds.
        let trailingInset: CGFloat = textToMicrophoneConstraint.isActive || textToClearConstraint.isActive ? 40 : 14
        let textWidth = textFieldCompactWidthConstraint.isActive
            ? 0 : max(0, bounds.width - textFieldLeadingConstraint.constant - trailingInset)
        let textBounds = CGRect(x: 0, y: 0, width: textWidth, height: textField.bounds.height)
        let rect = textField.placeholderRect(forBounds: textBounds)
        let showsShortPlaceholder = configuration.shortPlaceholder != nil
            && rect.width > 0 && ceil(fullPlaceholder.size().width) > rect.width

        // Keep both text layers alive so their crossfade belongs to the owning
        // navigation animation, including interactive progress and cancellation.
        // A nested UIView.transition would also snapshot/reset the field's fade.
        for (view, label, placeholder) in [(fullPlaceholderView, fullPlaceholderLabel, fullPlaceholder), (shortPlaceholderView, shortPlaceholderLabel, shortPlaceholder)] {
            if label.attributedText?.isEqual(to: placeholder) != true {
                label.attributedText = placeholder
            }
            let width = ceil(placeholder.size().width)
            let x = effectiveUserInterfaceLayoutDirection == .rightToLeft ? rect.maxX - width : rect.minX
            view.frame = CGRect(x: x, y: rect.minY, width: width, height: rect.height)
            label.frame = view.bounds
            view.isHidden = !text.isEmpty
        }
        fullPlaceholderView.alpha = showsShortPlaceholder ? 0 : 1
        shortPlaceholderView.alpha = showsShortPlaceholder ? 1 : 0

        // Retain the native placeholder for accessibility while the labels draw it.
        let placeholder = attributedText(showsShortPlaceholder ? shortPlaceholder.string : fullPlaceholder.string, color: .clear)
        if textField.attributedPlaceholder?.isEqual(to: placeholder) != true {
            textField.attributedPlaceholder = placeholder
        }
        updatePresentationAccessibility()
    }

    private func updateAccessory() {
        let hasText = !(textField.text ?? "").isEmpty
        let showsMicrophone = configuration.showsMicrophone && !hasText
        let showsClear = hasText

        microphoneButton.isHidden = !showsMicrophone
        microphoneButton.isAccessibilityElement = showsMicrophone
        microphoneButton.accessibilityElementsHidden = !showsMicrophone
        microphoneButton.isUserInteractionEnabled = showsMicrophone
        microphoneButton.accessibilityLabel = showsMicrophone ? microphoneAccessibilityLabel : nil
        clearButton.isHidden = !showsClear
        clearButton.isAccessibilityElement = showsClear
        clearButton.accessibilityElementsHidden = !showsClear
        clearButton.isUserInteractionEnabled = showsClear
        clearButton.accessibilityLabel = showsClear ? clearAccessibilityLabel : nil
        let isCompact = presentation == .compactToolbar || presentation == .sideToolbar || isHandoffCollapsed
        NSLayoutConstraint.deactivate([
            textToMicrophoneConstraint, textToClearConstraint,
            textToTrailingConstraint, textFieldCompactWidthConstraint,
        ])
        textFieldCompactWidthConstraint.isActive = isCompact
        textToMicrophoneConstraint.isActive = !isCompact && showsMicrophone
        textToClearConstraint.isActive = !isCompact && showsClear
        textToTrailingConstraint.isActive = !isCompact && !showsMicrophone && !showsClear
        updatePresentationAccessibility()
    }

    private func updateAutocomplete() {
        autocompleteView.actionTintColor = tintColor
        autocompleteView.configure(
            typedText: textField.text ?? "",
            autocomplete: shouldShowAutocomplete ? configuration.autocomplete : nil
        )
        textField.tintColor = autocompleteView.isShowingAutocomplete ? .clear : tintColor
        setNeedsLayout()
    }

    private func updateAutocompleteGeometry() {
        guard autocompleteView.isShowingAutocomplete else { return }
        textField.layoutIfNeeded()

        let textRect = textField.bounds
        let endPosition = textField.endOfDocument
        var caretX = textField.caretRect(for: endPosition).minX
        if !caretX.isFinite || caretX <= textRect.minX {
            caretX = fallbackCaretX(in: textRect)
        }

        let writingDirection = textField.baseWritingDirection(for: endPosition, in: .backward)
        let isRightToLeft = if writingDirection == .rightToLeft {
            true
        } else if writingDirection == .leftToRight {
            false
        } else {
            effectiveUserInterfaceLayoutDirection == .rightToLeft
        }

        autocompleteView.updateGeometry(
            caretX: caretX,
            textViewport: textRect,
            isRightToLeft: isRightToLeft
        )
    }

    private func fallbackCaretX(in textRect: CGRect) -> CGFloat {
        let width = attributedText(textField.text ?? "", color: .label).size().width
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            return max(textRect.minX, textRect.maxX - width)
        }
        return min(textRect.maxX, textRect.minX + width)
    }

    private func attributedText(_ text: String, color: UIColor) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: WTypography.uiFont(.body),
                .foregroundColor: color,
                .kern: Self.textKern,
            ]
        )
    }

    @objc private func textDidChange() {
        configuration.text = textField.text ?? ""
        if let expectedText = expectedTextAfterUserEdit,
           configuration.text == expectedText,
           selectedRange == expectedSelectionAfterUserEdit {
            clearExpectedUserEdit()
        }
        updateAccessory()
        updatePlaceholder()
        updateAutocomplete()
        onTextChange?(configuration.text)
    }

    @objc private func microphoneTapped() {
        onMicrophoneTap?()
    }

    @objc private func clearTapped() {
        suppressesAutocompleteUntilNextInsertion = true
        textField.attributedText = attributedText("", color: .label)
        textDidChange()
        textField.becomeFirstResponder()
    }

    @objc private func fieldTapped() {
        if presentation != .search {
            onActivate?()
        } else {
            textField.becomeFirstResponder()
        }
    }

    private func updatePresentationAccessibility() {
        let isSearch = presentation == .search
        isAccessibilityElement = !isSearch
        accessibilityLabel = isSearch ? nil : (textField.attributedPlaceholder?.string ?? configuration.placeholder)
        accessibilityTraits = isSearch ? [] : .button
        // One element carries the id at a time: the capsule while collapsed, the text field while searching
        let identifier: String? = switch presentation {
        case .homeToolbar, .sideToolbar: "home_search_input"
        case .compactToolbar: compactAccessibilityIdentifier
        case .search, .empty: nil
        }
        accessibilityIdentifier = identifier
        textField.isAccessibilityElement = isSearch
        textField.accessibilityIdentifier = isSearch ? (compactAccessibilityIdentifier ?? "home_search_input") : nil
        microphoneButton.isAccessibilityElement = isSearch && !microphoneButton.isHidden
        clearButton.isAccessibilityElement = isSearch && !clearButton.isHidden
        microphoneButton.isUserInteractionEnabled = isSearch && !microphoneButton.isHidden
        clearButton.isUserInteractionEnabled = isSearch && !clearButton.isHidden
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        onEditingChange?(true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        onEditingChange?(false)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onReturn?(textField.text ?? "")
        return false
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        let isDeleting = string.isEmpty && range.length > 0
        if isDeleting,
           autocompleteView.isShowingAutocomplete,
           hasSelectionAtTextEnd {
            suppressesAutocompleteUntilNextInsertion = true
            updateAutocomplete()
            return false
        }

        if !string.isEmpty {
            suppressesAutocompleteUntilNextInsertion = false
        }
        let currentText = (textField.text ?? "") as NSString
        if range.location <= currentText.length,
           NSMaxRange(range) <= currentText.length {
            expectedTextAfterUserEdit = currentText.replacingCharacters(
                in: range,
                with: string
            )
            expectedSelectionAfterUserEdit = NSRange(
                location: range.location + (string as NSString).length,
                length: 0
            )
        } else {
            expectedTextAfterUserEdit = nil
            expectedSelectionAfterUserEdit = nil
        }
        return true
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
        guard ignoredSelectionChangeCount == 0 else {
            updateAutocomplete()
            return
        }

        if let expectedText = expectedTextAfterUserEdit,
           textField.text == expectedText {
            let expectedSelection = expectedSelectionAfterUserEdit
            clearExpectedUserEdit()
            if selectedRange == expectedSelection {
                updateAutocomplete()
                return
            }
        }

        if expectedTextAfterUserEdit != nil {
            // Some input methods update selection before committing the text.
            // Keep the edit intent alive until `editingChanged` observes it.
            return
        }

        // UIKit reports taps, drag selection, and keyboard-trackpad movement here.
        // Once the user positions the cursor, wait for another insertion before
        // showing autocomplete again—even when the cursor returns to the end.
        suppressesAutocompleteUntilNextInsertion = true
        updateAutocomplete()
    }

    private func clearExpectedUserEdit() {
        expectedTextAfterUserEdit = nil
        expectedSelectionAfterUserEdit = nil
    }

    private func ignoreSelectionChangesUntilNextRunLoop() {
        ignoredSelectionChangeCount += 1
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            ignoredSelectionChangeCount = max(0, ignoredSelectionChangeCount - 1)
        }
    }

    private var shouldShowAutocomplete: Bool {
        !suppressesAutocompleteUntilNextInsertion
            && hasSelectionAtTextEnd
            && textField.markedTextRange == nil
    }

    private var hasSelectionAtTextEnd: Bool {
        guard let selection = textField.selectedTextRange else { return true }
        return selection.isEmpty
            && textField.compare(selection.end, to: textField.endOfDocument) == .orderedSame
    }

    private var selectedRange: NSRange? {
        guard let selection = textField.selectedTextRange else { return nil }
        return NSRange(
            location: textField.offset(from: textField.beginningOfDocument, to: selection.start),
            length: textField.offset(from: selection.start, to: selection.end)
        )
    }
}

@MainActor
private final class UniversalSearchAutocompleteView: UIView {
    var actionTintColor: UIColor = .tintColor {
        didSet { refreshAppearance() }
    }

    private(set) var isShowingAutocomplete = false

    // These Core Text values reproduce Figma's measured SF Pro widths.
    private static let mainKern: CGFloat = 0.05
    private static let actionKern: CGFloat = -0.1

    private var autocomplete: UniversalSearchAutocomplete?
    private var fullAttributedText: NSAttributedString?
    private var suffixAttributedText: NSAttributedString?
    private var displayedAttributedText: NSAttributedString?
    private var actionRange = NSRange(location: 0, length: 0)
    private let clippingView = UIView()
    private let backgroundView = UniversalSearchAutocompleteBackgroundView()
    private let standardLabel = UILabel()
    private let actionTextView = UniversalSearchGradientTextView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = true
        clippingView.clipsToBounds = true
        backgroundView.isUserInteractionEnabled = false
        addSubview(backgroundView)
        addSubview(clippingView)

        standardLabel.numberOfLines = 1
        standardLabel.isUserInteractionEnabled = false
        clippingView.addSubview(standardLabel)

        actionTextView.isUserInteractionEnabled = false
        clippingView.addSubview(actionTextView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        actionTintColor = tintColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            refreshAppearance()
        }
    }

    func configure(typedText: String, autocomplete: UniversalSearchAutocomplete?) {
        self.autocomplete = autocomplete
        guard !typedText.isEmpty,
              let autocomplete,
              autocomplete.suggestion.hasPrefix(typedText) else {
            isShowingAutocomplete = false
            isHidden = true
            fullAttributedText = nil
            suffixAttributedText = nil
            displayedAttributedText = nil
            return
        }

        let remainingSuggestion = String(autocomplete.suggestion.dropFirst(typedText.count))
        let action = " — \(autocomplete.actionTitle)"
        guard !remainingSuggestion.isEmpty || !action.isEmpty else {
            isShowingAutocomplete = false
            isHidden = true
            suffixAttributedText = nil
            return
        }

        let suggestionAttributes: [NSAttributedString.Key: Any] = [
            .font: WTypography.uiFont(.body),
            .foregroundColor: UIColor.label,
            .kern: Self.mainKern,
        ]
        let actionAttributes: [NSAttributedString.Key: Any] = [
            .font: WTypography.uiFont(.subheadline),
            .foregroundColor: autocomplete.style == .agent ? UIColor.black : actionTintColor,
            .kern: Self.actionKern,
        ]
        let fullAttributedText = NSMutableAttributedString(
            string: autocomplete.suggestion,
            attributes: suggestionAttributes
        )
        fullAttributedText.append(NSAttributedString(
            string: action,
            attributes: actionAttributes
        ))
        let suffixAttributedText = NSMutableAttributedString(
            string: remainingSuggestion,
            attributes: suggestionAttributes
        )
        suffixAttributedText.append(NSAttributedString(
            string: action,
            attributes: actionAttributes
        ))

        self.fullAttributedText = fullAttributedText
        self.suffixAttributedText = suffixAttributedText
        actionRange = NSRange(
            location: fullAttributedText.length - (action as NSString).length,
            length: (action as NSString).length
        )
        displayedAttributedText = fullAttributedText
        isShowingAutocomplete = true
        isHidden = false
        refreshAppearance()
    }

    func updateGeometry(
        caretX: CGFloat,
        textViewport: CGRect,
        isRightToLeft: Bool
    ) {
        guard isShowingAutocomplete,
              let fullAttributedText,
              let suffixAttributedText else { return }

        let attributedText = isRightToLeft ? suffixAttributedText : fullAttributedText
        if displayedAttributedText != attributedText {
            displayedAttributedText = attributedText
            refreshAppearance()
        }

        let contentWidth = attributedText.boundingRect(
            with: CGSize(width: .greatestFiniteMagnitude, height: bounds.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).width
        guard contentWidth > 0 else {
            isHidden = true
            return
        }

        let viewport = textViewport.intersection(bounds)
        let leadingBackgroundPadding: CGFloat = autocomplete?.style == .agent ? 1 : 0
        let trailingBackgroundPadding: CGFloat = 3
        let availableWidth: CGFloat
        let clippingOriginX: CGFloat
        let textOriginX: CGFloat
        let backgroundWidth: CGFloat
        if isRightToLeft {
            backgroundWidth = ceil(contentWidth) + leadingBackgroundPadding + trailingBackgroundPadding
            availableWidth = max(0, caretX - viewport.minX + leadingBackgroundPadding)
            let visibleWidth = min(backgroundWidth, availableWidth)
            clippingOriginX = caretX - visibleWidth + leadingBackgroundPadding
            textOriginX = visibleWidth - contentWidth - trailingBackgroundPadding
        } else {
            clippingOriginX = caretX - leadingBackgroundPadding
            availableWidth = max(0, viewport.maxX - clippingOriginX)
            backgroundWidth = max(
                0,
                ceil(contentWidth) + trailingBackgroundPadding - clippingOriginX
            )
            textOriginX = -clippingOriginX
        }

        let visibleWidth = min(backgroundWidth, availableWidth)
        guard visibleWidth > 0 else {
            isHidden = true
            return
        }
        isHidden = false
        let semanticContentAttribute: UISemanticContentAttribute =
            isRightToLeft ? .forceRightToLeft : .forceLeftToRight
        standardLabel.semanticContentAttribute = semanticContentAttribute
        actionTextView.semanticContentAttribute = semanticContentAttribute

        clippingView.frame = CGRect(
            x: clippingOriginX,
            y: 0,
            width: visibleWidth,
            height: bounds.height
        )
        let isAgent = autocomplete?.style == .agent
        let backgroundLeadingAdjustment: CGFloat = isAgent ? 2 : 0
        let backgroundTrailingAdjustment: CGFloat = isAgent ? 1 : 0
        let backgroundX = if isRightToLeft {
            clippingOriginX - backgroundTrailingAdjustment
        } else {
            clippingOriginX + backgroundLeadingAdjustment
        }
        backgroundView.frame = CGRect(
            x: backgroundX,
            y: (bounds.height - 21) / 2 + (isAgent ? 1 : 0),
            width: max(
                0,
                visibleWidth + backgroundTrailingAdjustment - backgroundLeadingAdjustment
            ),
            height: 21
        )

        let textFrame = CGRect(
            x: textOriginX,
            y: 0,
            width: contentWidth,
            height: bounds.height
        )
        standardLabel.frame = textFrame
        actionTextView.frame = textFrame
        actionTextView.gradientFrame = actionGradientFrame(
            in: attributedText,
            isRightToLeft: isRightToLeft
        )
        actionTextView.setNeedsLayout()
    }

    private func actionGradientFrame(
        in attributedText: NSAttributedString,
        isRightToLeft: Bool
    ) -> CGRect {
        let displayedActionRange = isRightToLeft
            ? NSRange(
                location: attributedText.length - actionRange.length,
                length: actionRange.length
            )
            : actionRange
        guard displayedActionRange.location >= 0,
              NSMaxRange(displayedActionRange) <= attributedText.length
        else { return .zero }

        let prefixWidth = attributedText.attributedSubstring(
            from: NSRange(location: 0, length: displayedActionRange.location)
        ).size().width
        let actionWidth = attributedText.attributedSubstring(from: displayedActionRange).size().width
        return CGRect(x: prefixWidth, y: 0, width: actionWidth, height: bounds.height)
    }

    private func refreshAppearance() {
        guard let autocomplete, let displayedAttributedText else { return }

        backgroundView.configure(style: autocomplete.style, tintColor: actionTintColor)
        let suggestionText = NSMutableAttributedString(attributedString: displayedAttributedText)
        let actionLength = (" — \(autocomplete.actionTitle)" as NSString).length
        if suggestionText.length >= actionLength {
            suggestionText.addAttribute(
                .foregroundColor,
                value: UIColor.clear,
                range: NSRange(
                    location: suggestionText.length - actionLength,
                    length: actionLength
                )
            )
        }
        standardLabel.attributedText = suggestionText
        actionTextView.attributedText = displayedAttributedText
        actionTextView.gradientColors = autocomplete.style == .agent
            ? autocompleteGradientColors
            : standardActionColors
        standardLabel.isHidden = false
        actionTextView.isHidden = false
    }

    private var standardActionColors: [CGColor] {
        let color = actionTintColor.resolvedColor(with: traitCollection).cgColor
        return [color, color]
    }

    private var autocompleteGradientColors: [CGColor] {
        [
            actionTintColor.resolvedColor(with: traitCollection).cgColor,
            UIColor(hex: "#00BEFF").cgColor,
            UIColor(hex: "#B656FF").cgColor,
        ]
    }
}

@MainActor
private final class UniversalSearchAutocompleteBackgroundView: UIView {
    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        clipsToBounds = true
        // Figma's vector runs from (0, 0) to (91.9539, 27.7743) in a 94×21 rect.
        // These normalized endpoints preserve that direction without clipping its end colors.
        gradientLayer.startPoint = CGPoint(x: -0.0313, y: 0.4641)
        gradientLayer.endPoint = CGPoint(x: 1.0313, y: 0.5359)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(style: UniversalSearchAutocomplete.Style, tintColor: UIColor) {
        let alpha: CGFloat = traitCollection.userInterfaceStyle == .dark ? 0.3 : 0.2
        switch style {
        case .standard:
            let color = tintColor.withAlphaComponent(alpha).cgColor
            gradientLayer.colors = [color, color]
            gradientLayer.locations = [0, 1]
        case .agent:
            gradientLayer.colors = [
                tintColor.withAlphaComponent(alpha).cgColor,
                UIColor(hex: "#00BEFF").withAlphaComponent(alpha).cgColor,
                UIColor(hex: "#B656FF").withAlphaComponent(alpha).cgColor,
            ]
            gradientLayer.locations = [0, 0.48, 1]
        }
    }
}

@MainActor
private final class UniversalSearchGradientTextView: UIView {
    var attributedText: NSAttributedString? {
        didSet { maskLabel.attributedText = attributedText }
    }

    var gradientColors: [CGColor] = [] {
        didSet { setNeedsLayout() }
    }

    var gradientFrame = CGRect.zero

    private let gradientLayer = CAGradientLayer()
    private let maskLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        maskLabel.numberOfLines = 1
        layer.addSublayer(gradientLayer)
        gradientLayer.mask = maskLabel.layer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        maskLabel.semanticContentAttribute = semanticContentAttribute
        gradientLayer.frame = gradientFrame
        gradientLayer.colors = gradientColors
        maskLabel.frame = CGRect(
            x: -gradientFrame.minX,
            y: 0,
            width: bounds.width,
            height: bounds.height
        )
    }
}

@MainActor
private final class UniversalSearchToolbarActionButton: UIControl {
    var onTap: (() -> Void)?

    private let glassView = UniversalSearchInteractiveGlassView()
    private let titleLabel = UILabel()
    private var action: SharedBottomToolbarAction?

    override init(frame: CGRect) {
        super.init(frame: frame)

        isAccessibilityElement = true
        accessibilityTraits = .button

        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.isAccessibilityElement = false
        addSubview(glassView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = WButton.capsuleFont
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isUserInteractionEnabled = false
        glassView.contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            glassView.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(tapped))
            )
        } else {
            glassView.isUserInteractionEnabled = false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        if let action {
            applyAppearance(for: action)
        }
    }

    func configure(with action: SharedBottomToolbarAction) {
        self.action = action
        accessibilityLabel = action.accessibilityLabel
        accessibilityIdentifier = action.accessibilityIdentifier
        applyAppearance(for: action)
    }

    private func applyAppearance(for action: SharedBottomToolbarAction) {
        titleLabel.text = action.title
        let color: UIColor? = switch action.style {
        case .neutral: nil
        case .accent: tintColor
        case .positive: .air.positiveAmount
        case .negative: .air.negativeAmount
        }
        titleLabel.textColor = color?.foregroundForTintedBackground ?? .label
        glassView.setGlassTintColor(color, animator: nil)
    }

    override func accessibilityActivate() -> Bool {
        onTap?()
        return true
    }

    @objc private func tapped() {
        onTap?()
    }
}

/// A button of the home toolbar, apart from the field and the actions button
@MainActor
private protocol HomeToolbarItemView: UIView {
    func setHomeAppearance(showsGlass: Bool, showsContent: Bool)
    /// Fades and scales the content for a host's handoff morph, apart from `setHomeAppearance`'s visibility
    func setHandoffContent(alpha: CGFloat, scale: CGFloat)
    /// Whether the content shows, as `setHomeAppearance` last set it
    var showsHomeContent: Bool { get }
    /// The layer that wiggles while the toolbar is rearranged
    var jiggleLayer: CALayer { get }
    func setGlassInteractive(_ isInteractive: Bool)
}

extension WalletAccountButton: HomeToolbarItemView {
    fileprivate func setHomeAppearance(showsGlass: Bool, showsContent: Bool) {
        setToolbarAppearance(showsBackground: showsGlass, showsContent: showsContent)
    }

    fileprivate var showsHomeContent: Bool { showsToolbarContent }
    fileprivate var jiggleLayer: CALayer { contentLayer }
}

@MainActor
private final class UniversalSearchInteractiveGlassView: UIView {
    let contentView: UIView
    var presentationSourceView: UIView { effectView }
    var isEffectVisible: Bool { effectView.effect != nil }

    private let effectView: UIVisualEffectView
    private var materialEffect: UIVisualEffect
    private var usesClearGlass = false
    private var glassTintColor: UIColor?
    private var isInteractive: Bool

    /// Glass that reacts to touches keeps reacting to a finger that a drag has taken for something else, so a host
    /// turns the reaction off while it rearranges the glass
    func setInteractive(_ isInteractive: Bool) {
        guard isInteractive != self.isInteractive else { return }
        self.isInteractive = isInteractive
        let isVisible = effectView.effect != nil
        if !isInteractive, isVisible {
            // The press the glass is showing ends only with the effect that shows it
            for recognizer in effectView.gestureRecognizers ?? [] where recognizer.isEnabled {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
            }
            UIView.performWithoutAnimation { effectView.effect = nil }
        }
        setGlassTintColor(glassTintColor, animator: nil)
        if isVisible {
            UIView.performWithoutAnimation { effectView.effect = materialEffect }
        }
    }

    func setUsesClearGlass(_ usesClearGlass: Bool) {
        guard usesClearGlass != self.usesClearGlass else { return }
        self.usesClearGlass = usesClearGlass
        setGlassTintColor(glassTintColor, animator: nil, inheritsAnimation: true)
    }

    init(isInteractive: Bool = true) {
        self.isInteractive = isInteractive
        let materialEffect: UIVisualEffect
        let effectView: UIVisualEffectView
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = isInteractive
            materialEffect = effect
            let configuredEffectView = UIVisualEffectView(effect: effect)
            configuredEffectView.cornerConfiguration = .capsule()
            effectView = configuredEffectView
        } else {
            let effect = UIBlurEffect(style: .systemMaterial)
            materialEffect = effect
            effectView = UIVisualEffectView(effect: effect)
        }
        self.materialEffect = materialEffect
        self.effectView = effectView
        contentView = effectView.contentView

        super.init(frame: .zero)

        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows or hides the glass by giving it its effect or taking it away, which UIKit animates as glass
    /// materializing; glass doesn't fade with its alpha
    func setMaterialized(_ isMaterialized: Bool) {
        let target: UIVisualEffect? = isMaterialized ? materialEffect : nil
        guard (effectView.effect == nil) != (target == nil) else { return }
        if UIView.inheritedAnimationDuration > 0 {
            effectView.effect = target
        } else {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.effectView.effect = target
            }
        }
    }

    func setEffectVisible(_ isVisible: Bool, inheritsAnimation: Bool = false) {
        let updates = {
            if isVisible {
                if self.effectView.effect == nil {
                    self.effectView.effect = self.materialEffect
                }
            } else if self.effectView.effect != nil {
                self.effectView.effect = nil
            }
        }
        if inheritsAnimation { updates() } else { UIView.performWithoutAnimation(updates) }
    }

    func setGlassTintColor(
        _ tintColor: UIColor?,
        animator: UIViewPropertyAnimator?,
        inheritsAnimation: Bool = false
    ) {
        glassTintColor = tintColor
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            let effect = UIGlassEffect(style: usesClearGlass ? .clear : .regular)
            effect.isInteractive = isInteractive
            effect.tintColor = tintColor
            materialEffect = effect
            let updates = {
                if self.effectView.effect != nil {
                    self.effectView.effect = effect
                }
            }
            if let animator {
                animator.addAnimations(updates)
            } else if inheritsAnimation {
                updates()
            } else {
                UIView.performWithoutAnimation(updates)
            }
        } else {
            let updates = {
                self.effectView.contentView.backgroundColor = tintColor
            }
            if let animator {
                animator.addAnimations(updates)
            } else {
                UIView.performWithoutAnimation(updates)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !IOS_26_MODE_ENABLED {
            effectView.layer.cornerRadius = bounds.height / 2
            effectView.layer.cornerCurve = .continuous
            effectView.clipsToBounds = true
        }
    }
}

@MainActor
private final class UniversalSearchIconButton: UIView, HomeToolbarItemView {
    var onTap: (() -> Void)?
    private let glassView = UniversalSearchInteractiveGlassView()
    private let button = UIButton(type: .system)

    var jiggleLayer: CALayer { button.layer }

    func setOverlayAppearance(_ appearance: ContentOverlayAppearance) {
        overrideUserInterfaceStyle = appearance.userInterfaceStyle
        glassView.setUsesClearGlass(appearance.usesClearGlass)
        button.configuration?.baseForegroundColor = appearance.foregroundColor ?? .label
    }

    init(item: HomeToolbarItem) {
        super.init(frame: CGRect(x: 0, y: 0, width: HomeToolbarLayout.buttonSize, height: HomeToolbarLayout.buttonSize))
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = .plain()
        button.configuration?.image = item.makeToolbarImage()
        button.configuration?.contentInsets = .zero
        button.configuration?.baseForegroundColor = .label
        button.accessibilityLabel = item == .scan ? lang("Scan QR Code") : item.title
        button.accessibilityIdentifier = item.toolbarAccessibilityIdentifier
        button.addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
        glassView.contentView.addSubview(button)
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
            button.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private(set) var showsHomeContent = true

    func setHomeAppearance(showsGlass: Bool, showsContent: Bool) {
        showsHomeContent = showsContent
        glassView.setEffectVisible(showsGlass, inheritsAnimation: true)
        button.alpha = showsContent ? 1 : 0
    }

    func setHandoffContent(alpha: CGFloat, scale: CGFloat) {
        glassView.contentView.alpha = alpha
        button.transform = scale == 1 ? .identity : CGAffineTransform(scaleX: scale, y: scale)
    }

    func setGlassInteractive(_ isInteractive: Bool) {
        glassView.setInteractive(isInteractive)
    }
}

@MainActor
private final class UniversalSearchCloseButton: UIView {
    private enum ContentKind {
        case action
        case close
    }

    private static let maximumContentBlurRadius: CGFloat = 10

    var onTap: (() -> Void)?

    var interactionView: UIView { button }
    var presentationSourceView: UIView { glassView.presentationSourceView }

    var isBackgroundVisible: Bool { glassView.isEffectVisible }

    func setBackgroundVisible(_ visible: Bool) {
        glassView.setEffectVisible(visible, inheritsAnimation: true)
    }

    /// Hides the glyph while a host's control stands in for the button, whose glass may still show
    func setHandoffContentHidden(_ isHidden: Bool) {
        glassView.contentView.alpha = isHidden ? 0 : 1
    }

    var jiggleLayer: CALayer { actionContentView.layer }

    func setGlassInteractive(_ isInteractive: Bool) {
        glassView.setInteractive(isInteractive)
    }

    var buttonAccessibilityLabel: String? {
        get { button.accessibilityLabel }
        set { button.accessibilityLabel = newValue }
    }

    var buttonAccessibilityIdentifier: String? {
        get { button.accessibilityIdentifier }
        set { button.accessibilityIdentifier = newValue }
    }

    private let glassView = UniversalSearchInteractiveGlassView()
    private let button = UIButton(type: .system)
    private let actionContentView = WBlurredContentView()
    private let closeContentView = WBlurredContentView()
    private var foregroundImageViews: [UIImageView] = []
    private var presentation: UniversalSearchFieldPresentation = .search

    func setOverlayAppearance(_ appearance: ContentOverlayAppearance, animated: Bool) {
        let updates = {
            self.overrideUserInterfaceStyle = appearance.userInterfaceStyle
            // Glass may adapt its content's traits independently. The menu uses
            // the interaction button as its appearance source.
            self.button.overrideUserInterfaceStyle = appearance.userInterfaceStyle
            self.glassView.setUsesClearGlass(appearance.usesClearGlass)
            self.foregroundImageViews.forEach { $0.tintColor = appearance.foregroundColor ?? .label }
        }
        if animated {
            UIView.transition(with: actionContentView, duration: 0.25,
                              options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent], animations: updates)
        } else { updates() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = .plain()
        button.configuration?.contentInsets = .zero
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        glassView.contentView.addSubview(button)

        configure(
            contentView: actionContentView,
            imageName: "UniversalSearchPlus"
        )
        configure(
            contentView: closeContentView,
            imageName: "UniversalSearchXmark"
        )
        glassView.contentView.addSubview(actionContentView)
        glassView.contentView.addSubview(closeContentView)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            button.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
            button.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),

            actionContentView.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
            actionContentView.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
            actionContentView.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            actionContentView.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),

            closeContentView.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
            closeContentView.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
            closeContentView.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            closeContentView.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
        ])

        applyStaticPresentation(.search)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPresentation(
        _ presentation: UniversalSearchFieldPresentation,
        animator: UIViewPropertyAnimator?
    ) {
        guard presentation != self.presentation else { return }
        self.presentation = presentation
        let updates = {
            self.applyContentOpacity(for: presentation)
        }
        if let animator {
            animator.addAnimations(updates)
        } else {
            updates()
        }
    }

    func applyStaticPresentation(
        _ presentation: UniversalSearchFieldPresentation
    ) {
        self.presentation = presentation
        glassView.setEffectVisible(presentation != .compactToolbar)
        UIView.performWithoutAnimation {
            applyContentOpacity(for: presentation)
            actionContentView.blurRadius = blurRadius(
                for: .action,
                presentation: presentation
            )
            closeContentView.blurRadius = blurRadius(
                for: .close,
                presentation: presentation
            )
        }
    }

    func prepareTransition(from presentation: UniversalSearchFieldPresentation) {
        applyStaticPresentation(presentation)
        // Re-materializing at the fully overlapped compact frame is visually
        // neutral and lets the container split the two shapes during a pop.
        glassView.setEffectVisible(true)
    }

    func setTransitionProgress(
        _ progress: CGFloat,
        from source: UniversalSearchFieldPresentation,
        to target: UniversalSearchFieldPresentation
    ) {
        actionContentView.blurRadius = interpolate(
            from: blurRadius(for: .action, presentation: source),
            to: blurRadius(for: .action, presentation: target),
            progress: progress
        )
        closeContentView.blurRadius = interpolate(
            from: blurRadius(for: .close, presentation: source),
            to: blurRadius(for: .close, presentation: target),
            progress: progress
        )
    }

    private func configure(
        contentView: WBlurredContentView,
        imageName: String
    ) {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.isUserInteractionEnabled = false
        let imageView = UIImageView()
        imageView.image = UIImage.airBundle(imageName).withRenderingMode(.alwaysTemplate)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .label
        imageView.contentMode = .center
        foregroundImageViews.append(imageView)
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func applyContentOpacity(
        for presentation: UniversalSearchFieldPresentation
    ) {
        let showsAction = presentation == .homeToolbar || presentation == .sideToolbar
        let showsClose = presentation == .search
        actionContentView.alpha = showsAction ? 1 : 0
        closeContentView.alpha = showsClose ? 1 : 0
    }

    private func blurRadius(
        for kind: ContentKind,
        presentation: UniversalSearchFieldPresentation
    ) -> CGFloat {
        let isVisible = switch kind {
        case .action: presentation == .homeToolbar || presentation == .sideToolbar
        case .close: presentation == .search
        }
        return isVisible ? 0 : Self.maximumContentBlurRadius
    }

    private func interpolate(
        from start: CGFloat,
        to end: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        start + (end - start) * progress
    }

    @objc private func tapped() {
        onTap?()
    }
}

@MainActor
private final class UniversalSearchSymbolButton: UIControl {
    private let imageView = UIImageView()

    override var isHighlighted: Bool {
        didSet { imageView.alpha = isHighlighted ? 0.45 : 1 }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        isAccessibilityElement = true
        accessibilityTraits = .button
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .center
        imageView.clipsToBounds = false
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSymbol(_ systemName: String, configuration: UIImage.SymbolConfiguration) {
        imageView.image = UIImage(systemName: systemName)
        imageView.preferredSymbolConfiguration = configuration
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        imageView.tintColor = tintColor
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let horizontalExpansion = max(0, (44 - bounds.width) / 2)
        let verticalExpansion = max(0, (44 - bounds.height) / 2)
        return bounds.insetBy(
            dx: -horizontalExpansion,
            dy: -verticalExpansion
        ).contains(point)
    }
}
