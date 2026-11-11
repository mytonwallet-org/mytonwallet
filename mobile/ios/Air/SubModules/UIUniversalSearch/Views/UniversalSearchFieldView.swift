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
    public var onScanTap: (() -> Void)?
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
    public var trailingButtonPresentationSourceView: UIView { closeButton.presentationSourceView }
    public let accountsButton = WalletAccountButton()
    public var scanButtonPresentationSourceView: UIView? {
        showsHomeActions(in: presentation) && presentation != .empty && homeConfiguration.showsScan ? scanButton : nil
    }
    public private(set) var homeConfiguration = HomeToolbarConfiguration()
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
            scanButton.setOverlayAppearance(actions)
            sharedActionsGlass.overrideUserInterfaceStyle = actions.userInterfaceStyle
            sharedActionsGlass.setUsesClearGlass(actions.usesClearGlass)
        }
    }

    private var storedConfiguration: UniversalSearchFieldConfiguration
    private let fieldView = UniversalSearchFieldCapsuleView()
    private let closeButton = UniversalSearchCloseButton()
    private let scanButton = UniversalSearchScanButton()
    private let sharedActionsGlass = UniversalSearchInteractiveGlassView()
    private var accountsLeadingConstraint: NSLayoutConstraint!
    private var scanLeadingConstraint: NSLayoutConstraint!
    private var sharedActionsLeadingConstraint: NSLayoutConstraint!
    private var accountsTopConstraint: NSLayoutConstraint!
    private var scanTopConstraint: NSLayoutConstraint!
    private var sharedActionsTopConstraint: NSLayoutConstraint!
    private var pendingHomeConfiguration: HomeToolbarConfiguration?
    private var configurationAnimationID: UUID?
    private var homeActionGlassViews: [UIVisualEffectView] = []
    /// Out of the hierarchy between transitions. The glass container keeps a tag for every glass view that ever
    /// joined it, so transitions reuse these instead of adding new glass.
    private var reusableHomeActionGlassViews: [UIVisualEffectView] = []
    private var homeActionGlassPresentation: UniversalSearchFieldPresentation = .homeToolbar
    // Mirrors an owning animator's fraction without rendering anything. The
    // display link uses it to keep content blur interactive with push/pop.
    private let transitionProgressView = UIView()
    private let glassContainerView: UIVisualEffectView?
    private let contentView: UIView
    private var closeButtonTopConstraint: NSLayoutConstraint!
    private var closeButtonLeadingConstraint: NSLayoutConstraint!
    private var closeButtonTrailingConstraint: NSLayoutConstraint!
    private var closeButtonCompactCenterXConstraint: NSLayoutConstraint!
    private var fieldCompactWidthConstraint: NSLayoutConstraint!
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
    private lazy var fieldHandoffWidthConstraint = fieldView.widthAnchor.constraint(equalToConstant: 48)

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
        updatePresentationConstraints(for: presentation)
        applyStaticVisualState(for: presentation)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: presentation == .sideToolbar ? sideToolbarHeight : 48)
    }

    public var sideToolbarHeight: CGFloat {
        108 + CGFloat((homeConfiguration.showsAccounts ? 1 : 0) + (homeConfiguration.showsScan ? 1 : 0))
            * (usesSharedActionsBackground ? 48 : 56)
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

    /// How much wider than the trailing button the home toolbar's buttons are: the scan and accounts buttons with
    /// their spacing. A trailing handoff folds them into the trailing button as the field collapses.
    public var homeActionsWidth: CGFloat { getHomeActionOffsets().width }

    private var isTrailingHandoffActive: Bool {
        trailingHandoffProgress > 0 && contentPresentation(for: presentation) == .homeToolbar
    }

    /// The fold at which the scan and accounts buttons' content has shrunk away
    private static let homeActionsContentSwapEnd: CGFloat = 0.75

    /// How far a trailing handoff has folded the scan and accounts buttons into the trailing button
    private var homeActionsFold: CGFloat {
        isTrailingHandoffActive ? trailingHandoffProgress : 0
    }

    /// Whether a trailing handoff had the scan and accounts buttons out of reach when it last applied
    private var areHomeActionsHandedOff = false

    private func applyTrailingHandoff() {
        let isActive = isTrailingHandoffActive
        if isActive {
            let fullWidth = max(48, bounds.width - 48 - closeButtonLeadingConstraint.constant)
            fieldHandoffWidthConstraint.constant = fullWidth + (48 - fullWidth) * trailingHandoffProgress
            closeButtonLeadingConstraint.isActive = false
            fieldHandoffWidthConstraint.isActive = true
        } else if fieldHandoffWidthConstraint.isActive {
            fieldHandoffWidthConstraint.isActive = false
            let contentPresentation = contentPresentation(for: presentation)
            closeButtonLeadingConstraint.isActive = contentPresentation != .compactToolbar
                && contentPresentation != .sideToolbar
        }
        closeButton.alpha = isActive || isTrailingButtonHandedOff ? 0 : 1
        applyHomeActionOffsets(for: contentPresentation(for: presentation))
        let fold = homeActionsFold
        // The buttons' glass slides into the trailing button's place, merging with the host's control there, and
        // their content shrinks away on the way, as the trailing button's own glyph does on the host's control. Folded
        // all the way, their glass lies under the host's control, which stands in for it.
        sharedActionsGlass.alpha = fold > 0.99 ? 0 : 1
        let contentSwap = min(1, fold / Self.homeActionsContentSwapEnd)
        let contentScale = 1 + (GlassMotion.matchScale - 1) * contentSwap
        accountsButton.setHandoffContent(alpha: 1 - contentSwap, scale: contentScale)
        scanButton.setHandoffContent(alpha: 1 - contentSwap, scale: contentScale)
        let isHandedOff = fold > 0
        if isHandedOff != areHomeActionsHandedOff {
            areHomeActionsHandedOff = isHandedOff
            updateHomeActionsAppearance(for: presentation)
        }
        updateTrailingButtonAccessibilityLabel()
        fieldView.setHandoff(
            progress: isActive ? trailingHandoffProgress : 0,
            isCollapsed: isActive && fieldHandoffWidthConstraint.constant < 110
        )
    }

    public func setHomeConfiguration(_ configuration: HomeToolbarConfiguration, animated: Bool) {
        // Navigation owns the geometry until an interactive transition completes or cancels.
        guard presentationTransition == nil else {
            pendingHomeConfiguration = configuration
            return
        }
        guard configuration != homeConfiguration else { return }
        layoutIfNeeded()
        let shouldAnimate = animated && window != nil && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
        if shouldAnimate, showsHomeActions(in: presentation) {
            prepareHomeActionsGlassTransition()
        }
        homeConfiguration = configuration
        invalidateIntrinsicContentSize()
        let animationID = UUID()
        configurationAnimationID = animationID
        accountsButton.isHidden = false
        scanButton.isHidden = false
        updatePresentationConstraints(for: contentPresentation(for: presentation))
        let updates = {
            self.updateHomeActionsAppearance(for: self.presentation)
            self.onHomeConfigurationLayoutChange?()
            self.layoutIfNeeded()
            self.layoutHomeActionsGlassTransition()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, self.configurationAnimationID == animationID else { return }
            self.configurationAnimationID = nil
            self.finishHomeActionsGlassTransition()
            self.finishHomeActionsAppearance()
        }
        if shouldAnimate {
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
        if showsHomeActions(in: self.presentation) || showsHomeActions(in: presentation) {
            prepareHomeActionsGlassTransition()
        }

        let transition = PresentationTransition(
            navigationOperation: navigationOperation,
            source: self.presentation,
            target: presentation,
            sourceActions: self.compactActions,
            targetActions: targetActions
        )
        presentationTransition = transition
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
        updateHomeActionsAppearance(for: self.presentation)
        accountsButton.isHidden = false
        scanButton.isHidden = false
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

        updatePresentationConstraints(for: contentPresentation)
        fieldView.setPresentation(contentPresentation, animator: animator)
        closeButton.setPresentation(
            contentPresentation,
            animator: animator
        )

        let updates = {
            guard self.presentationTransition?.id == transition.id else { return }
            self.transform = self.toolbarTransform(for: presentation)
            self.updateHomeActionsAppearance(for: presentation)
            self.setCompactActionsTransform(self.compactActionsTransform(for: presentation))
            let outgoingTransform = self.compactActionsOffscreenTransform(
                for: self.outgoingCompactActionButtons,
                toward: transition.navigationOperation == .push ? .leading : .trailing
            )
            for button in self.outgoingCompactActionButtons {
                button.transform = presentation == .empty ? .identity : outgoingTransform
            }
            self.transitionProgressView.alpha = 1
            self.layoutIfNeeded()
            self.layoutHomeActionsGlassTransition()
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

        updatePresentationConstraints(for: contentPresentation)
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
        finishHomeActionsGlassTransition()
        updateHomeActionsAppearance(for: presentation)
        finishHomeActionsAppearance()
        updateCompactActionsAccessibility(for: presentation)
        updateEmptyAccessibility(for: presentation)
    }

    private func updatePresentationConstraints(
        for presentation: UniversalSearchFieldPresentation
    ) {
        defer { applyTrailingHandoff() }
        fieldHandoffWidthConstraint.isActive = false
        applyHomeActionOffsets(for: presentation)
        if presentation == .compactToolbar || presentation == .sideToolbar {
            NSLayoutConstraint.deactivate([
                closeButtonLeadingConstraint,
                closeButtonTrailingConstraint,
            ])
            NSLayoutConstraint.activate([
                closeButtonCompactCenterXConstraint,
                fieldCompactWidthConstraint,
            ])
        } else {
            NSLayoutConstraint.deactivate([
                closeButtonCompactCenterXConstraint,
                fieldCompactWidthConstraint,
            ])
            NSLayoutConstraint.activate([
                closeButtonLeadingConstraint,
                closeButtonTrailingConstraint,
            ])
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

    /// How far the scan and accounts buttons, and their shared glass, reach before the trailing button
    private func getHomeActionOffsets() -> (scan: CGFloat, accounts: CGFloat, width: CGFloat) {
        let stride: CGFloat = usesSharedActionsBackground ? 48 : 56
        let scan: CGFloat = homeConfiguration.showsScan ? stride : 0
        let accounts: CGFloat = homeConfiguration.showsAccounts ? scan + stride : 0
        return (scan, accounts, max(scan, accounts))
    }

    private func applyHomeActionOffsets(for presentation: UniversalSearchFieldPresentation) {
        let isSide = presentation == .sideToolbar
        let isHome = presentation == .homeToolbar || isSide
        let offsets = isHome ? getHomeActionOffsets() : (scan: CGFloat(0), accounts: CGFloat(0), width: CGFloat(0))
        // A trailing handoff folds the buttons toward the trailing button; the field keeps its width beside them
        let shown = presentation == .homeToolbar ? 1 - homeActionsFold : 1
        closeButtonLeadingConstraint.constant = isHome ? 12 + offsets.width : 8
        scanLeadingConstraint.constant = isSide ? 0 : -offsets.scan * shown
        accountsLeadingConstraint.constant = isSide ? 0 : -offsets.accounts * shown
        sharedActionsLeadingConstraint.constant = isSide ? 0 : -offsets.width * shown
        scanTopConstraint.constant = isSide ? -offsets.scan : 0
        accountsTopConstraint.constant = isSide ? -offsets.accounts : 0
        sharedActionsTopConstraint.constant = isSide ? -offsets.width : 0
        closeButtonTopConstraint.constant = isSide ? 60 + offsets.width : 0
    }

    private var usesSharedActionsBackground: Bool {
        if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
            return homeConfiguration.sharesBackground
        }
        return false
    }

    private func updateHomeActionsAppearance(for presentation: UniversalSearchFieldPresentation) {
        homeActionGlassPresentation = presentation
        let isHome = showsHomeActions(in: presentation)
        let showsAccounts = isHome && homeConfiguration.showsAccounts
        let showsScan = isHome && homeConfiguration.showsScan
        let shared = isHome && usesSharedActionsBackground && (showsAccounts || showsScan)
        let showsMaterial = homeActionGlassViews.isEmpty
        let isHandingOff = homeActionsFold > 0
        // The invisible action wrapper overlaps Search when the toolbar is compact.
        sharedActionsGlass.isUserInteractionEnabled = presentation != .compactToolbar && presentation != .empty
        sharedActionsGlass.setEffectVisible(showsMaterial && shared, inheritsAnimation: true)
        accountsButton.setToolbarAppearance(showsBackground: showsMaterial && showsAccounts && !shared, showsContent: showsAccounts)
        scanButton.setAppearance(showsBackground: showsMaterial && showsScan && !shared, showsContent: showsScan)
        closeButton.setBackgroundVisible(showsMaterial && !shared && (contentPresentation(for: presentation) != .compactToolbar || presentationTransition != nil))
        accountsButton.isUserInteractionEnabled = showsAccounts && presentation != .empty && !isHandingOff
        accountsButton.accessibilityElementsHidden = !accountsButton.isUserInteractionEnabled
        scanButton.isUserInteractionEnabled = showsScan && presentation != .empty && !isHandingOff
        scanButton.accessibilityElementsHidden = !scanButton.isUserInteractionEnabled
    }

    private func homeActionGlassFrames(for presentation: UniversalSearchFieldPresentation) -> [CGRect] {
        let closeFrame = closeButton.convert(closeButton.bounds, to: contentView)
        let isHome = showsHomeActions(in: presentation)
        if isHome, usesSharedActionsBackground, homeConfiguration.showsAccounts || homeConfiguration.showsScan {
            let sharedFrame = sharedActionsGlass.convert(sharedActionsGlass.bounds, to: contentView)
            return Array(repeating: sharedFrame, count: 3)
        }
        return [
            isHome && homeConfiguration.showsAccounts ? accountsButton.convert(accountsButton.bounds, to: contentView) : closeFrame,
            isHome && homeConfiguration.showsScan ? scanButton.convert(scanButton.bounds, to: contentView) : closeFrame,
            closeFrame,
        ]
    }

    private func prepareHomeActionsGlassTransition() {
        // Handed off, the buttons are the host's control, which carries itself through the transition
        guard homeActionGlassViews.isEmpty, glassContainerView != nil, homeActionsFold == 0, !isTrailingButtonHandedOff,
              #available(iOS 26, *) else { return }
        homeActionGlassPresentation = presentation
        // Keep material visible while its geometry merges. Duplicate shapes start
        // overlapped when splitting and are replaced only after the animation.
        UIView.performWithoutAnimation {
            for (index, frame) in homeActionGlassFrames(for: presentation).enumerated() {
                let glass: UIVisualEffectView
                if let reusable = reusableHomeActionGlassViews.popLast() {
                    removeAnimations(in: reusable.layer)
                    glass = reusable
                } else {
                    glass = UIVisualEffectView()
                    glass.cornerConfiguration = .capsule()
                    glass.isUserInteractionEnabled = false
                }
                glass.effect = UIGlassEffect(style: actionsOverlayAppearance.usesClearGlass ? .clear : .regular)
                glass.overrideUserInterfaceStyle = actionsOverlayAppearance.userInterfaceStyle
                glass.frame = frame
                glass.accessibilityIdentifier = "home_toolbar_transition_glass_\(index)"
                contentView.insertSubview(glass, belowSubview: sharedActionsGlass)
                // Resolve adaptive corners before the host starts animating frames.
                glass.layoutIfNeeded()
                homeActionGlassViews.append(glass)
            }
            updateHomeActionsAppearance(for: presentation)
        }
        noteJoinedGlass()
    }

    private func finishHomeActionsGlassTransition() {
        guard !homeActionGlassViews.isEmpty else { return }
        let outgoingGlass = homeActionGlassViews
        homeActionGlassViews = []
        UIView.performWithoutAnimation {
            updateHomeActionsAppearance(for: presentation)
            outgoingGlass.forEach { $0.removeFromSuperview() }
        }
        reusableHomeActionGlassViews.append(contentsOf: outgoingGlass)
    }

    private func layoutHomeActionsGlassTransition() {
        guard !homeActionGlassViews.isEmpty else { return }
        contentView.layoutIfNeeded()
        for (glass, frame) in zip(homeActionGlassViews, homeActionGlassFrames(for: homeActionGlassPresentation)) {
            glass.frame = frame
        }
    }

    private func finishHomeActionsAppearance() {
        let isHome = showsHomeActions(in: presentation)
        accountsButton.isHidden = !isHome || !homeConfiguration.showsAccounts
        scanButton.isHidden = !isHome || !homeConfiguration.showsScan
        if let configuration = pendingHomeConfiguration, presentationTransition == nil {
            pendingHomeConfiguration = nil
            setHomeConfiguration(configuration, animated: window != nil)
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
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        transitionProgressView.translatesAutoresizingMaskIntoConstraints = false
        transitionProgressView.isUserInteractionEnabled = false
        contentView.addSubview(fieldView)
        sharedActionsGlass.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sharedActionsGlass)
        sharedActionsGlass.contentView.addSubview(accountsButton)
        scanButton.translatesAutoresizingMaskIntoConstraints = false
        sharedActionsGlass.contentView.addSubview(scanButton)
        sharedActionsGlass.contentView.addSubview(closeButton)
        contentView.addSubview(transitionProgressView)

        closeButtonLeadingConstraint = closeButton.leadingAnchor.constraint(
            equalTo: fieldView.trailingAnchor,
            constant: 8
        )
        closeButtonTrailingConstraint = closeButton.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor
        )
        closeButtonCompactCenterXConstraint = closeButton.centerXAnchor.constraint(
            equalTo: fieldView.centerXAnchor
        )
        fieldCompactWidthConstraint = fieldView.widthAnchor.constraint(equalToConstant: 48)
        closeButtonTopConstraint = closeButton.topAnchor.constraint(equalTo: contentView.topAnchor)
        accountsLeadingConstraint = accountsButton.leadingAnchor.constraint(equalTo: closeButton.leadingAnchor)
        scanLeadingConstraint = scanButton.leadingAnchor.constraint(equalTo: closeButton.leadingAnchor)
        sharedActionsLeadingConstraint = sharedActionsGlass.leadingAnchor.constraint(equalTo: closeButton.leadingAnchor)
        accountsTopConstraint = accountsButton.topAnchor.constraint(equalTo: closeButton.topAnchor)
        scanTopConstraint = scanButton.topAnchor.constraint(equalTo: closeButton.topAnchor)
        sharedActionsTopConstraint = sharedActionsGlass.topAnchor.constraint(equalTo: closeButton.topAnchor)
        NSLayoutConstraint.activate([
            accountsLeadingConstraint,
            accountsTopConstraint,
            accountsButton.widthAnchor.constraint(equalToConstant: 48),
            accountsButton.heightAnchor.constraint(equalToConstant: 48),
            scanLeadingConstraint,
            scanTopConstraint,
            scanButton.widthAnchor.constraint(equalToConstant: 48),
            scanButton.heightAnchor.constraint(equalToConstant: 48),
            sharedActionsLeadingConstraint,
            sharedActionsGlass.trailingAnchor.constraint(equalTo: closeButton.trailingAnchor),
            sharedActionsTopConstraint,
            sharedActionsGlass.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor),
            fieldView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            fieldView.topAnchor.constraint(equalTo: contentView.topAnchor),
            fieldView.heightAnchor.constraint(equalToConstant: 48),

            closeButtonLeadingConstraint,
            closeButtonTrailingConstraint,
            closeButtonTopConstraint,
            closeButton.heightAnchor.constraint(equalToConstant: 48),
            closeButton.widthAnchor.constraint(equalToConstant: 48),

            transitionProgressView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            transitionProgressView.topAnchor.constraint(equalTo: contentView.topAnchor),
            transitionProgressView.widthAnchor.constraint(equalToConstant: 1),
            transitionProgressView.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    public override func layoutSubviews() {
        if isTrailingHandoffActive {
            let fullWidth = max(48, bounds.width - 48 - closeButtonLeadingConstraint.constant)
            let width = fullWidth + (48 - fullWidth) * trailingHandoffProgress
            if abs(fieldHandoffWidthConstraint.constant - width) > 0.25 { applyTrailingHandoff() }
        }
        super.layoutSubviews()
        layoutHomeActionsGlassTransition()
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
        scanButton.onTap = { [weak self] in self?.onScanTap?() }
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
            contentView.insertSubview(button, belowSubview: sharedActionsGlass)
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

@MainActor
private final class UniversalSearchInteractiveGlassView: UIView {
    let contentView: UIView
    var presentationSourceView: UIView { effectView }

    private let effectView: UIVisualEffectView
    private var materialEffect: UIVisualEffect
    private var usesClearGlass = false
    private var glassTintColor: UIColor?
    private let isInteractive: Bool

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
private final class UniversalSearchScanButton: UIView {
    var onTap: (() -> Void)?
    private let glassView = UniversalSearchInteractiveGlassView()
    private let button = UIButton(type: .system)

    func setOverlayAppearance(_ appearance: ContentOverlayAppearance) {
        overrideUserInterfaceStyle = appearance.userInterfaceStyle
        glassView.setUsesClearGlass(appearance.usesClearGlass)
        button.configuration?.baseForegroundColor = appearance.foregroundColor ?? .label
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = .plain()
        button.configuration?.image = UIImage(
            systemName: "viewfinder",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )
        button.configuration?.contentInsets = .zero
        button.configuration?.baseForegroundColor = .label
        button.accessibilityLabel = lang("Scan QR Code")
        button.accessibilityIdentifier = "home_scan_qr_button"
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

    func setAppearance(showsBackground: Bool, showsContent: Bool) {
        glassView.setEffectVisible(showsBackground, inheritsAnimation: true)
        button.alpha = showsContent ? 1 : 0
    }

    /// Fades and scales the glyph for a host's handoff morph, apart from `setAppearance`'s visibility
    func setHandoffContent(alpha: CGFloat, scale: CGFloat) {
        glassView.contentView.alpha = alpha
        button.transform = scale == 1 ? .identity : CGAffineTransform(scaleX: scale, y: scale)
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

    func setBackgroundVisible(_ visible: Bool) {
        glassView.setEffectVisible(visible, inheritsAnimation: true)
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
