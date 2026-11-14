import UIKit
import UIAgent
import UIComponents
import UIUniversalSearch

/// The root toolbar that carries the Agent list's bar
@MainActor
protocol RootAgentBarHost: AnyObject {
    /// The view the toolbar lays out in
    var agentBarHostView: UIView { get }
    var agentBarNavigationController: WNavigationController? { get }
    /// The edge a vertical toolbar stands on; the bar shows only over the bottom toolbar
    var agentBarSideEdge: UIRectEdge? { get }
    var agentBarSearchViewController: UIViewController? { get }
    /// Paging progress toward the Agent tab, for the band under the toolbar
    func agentBarMorphProgressDidChange(_ progress: CGFloat)
    /// The question field gained or lost focus
    func agentBarEditingDidChange(_ isEditing: Bool)
    /// The question field gave up focus to the chat it composed, whose composer it is already
    func agentBarDidHandOffEditingToComposedChat()
}

/// Hosts the Agent list's question field over the toolbar, where it grows out of the trailing button, and carries it
/// into a chat's composer and the search field and back.
@MainActor
final class RootAgentBarController {
    private weak var host: (any RootAgentBarHost)?
    private let searchToolbar: UniversalSearchFieldView
    private let containerView: UIView
    private weak var bar: AgentListBottomBar?
    private var barConstraints: [NSLayoutConstraint] = []
    private var morphProgress: CGFloat = 0
    var isAvailable = true {
        didSet { if isAvailable != oldValue { applyMorph() } }
    }
    /// While a chat's push or pop carries the bar, the transition owns the toolbar field's appearance
    private var isNavigationHandoffActive = false
    /// A question sent from the list's new chat continues in its chat on the same screen; see
    /// `beginComposedChatHandoff`
    private var isComposedChatHandoffPending = false
    /// Waits for the field to land with the keyboard before the composed chat's composer takes its place
    private var composedChatLanding: GlassMotionClock?
    private weak var composedChatTarget: (any AgentComposerHandoffTarget)?
    /// The handoff's spring on the list's field and the search circle, if one is running
    private var handoffMotion: AgentHandoffMotion?
    /// The field holds a question, as last placed: wide over the search circle's place, the circle away past the
    /// leading edge. Transitions that start meanwhile start from this.
    private var isQuestionHeld = false
    private var questionAnimator: UIViewPropertyAnimator?

    init(host: any RootAgentBarHost, searchToolbar: UniversalSearchFieldView, containerView: UIView) {
        self.host = host
        self.searchToolbar = searchToolbar
        self.containerView = containerView
    }

    var isEditing: Bool {
        bar?.isEditing == true
    }

    /// The bar's glass lives in the toolbar's glass container, so the field, the microphone and the search circle flow
    /// together.
    func install(_ bar: AgentListBottomBar) {
        guard self.bar !== bar || bar.superview !== containerView else { return }
        NSLayoutConstraint.deactivate(barConstraints)
        if let previous = self.bar, previous !== bar, previous.superview === containerView {
            previous.setGlassHost(nil)
            previous.onMorphFrame = nil
            previous.removeFromSuperview()
        }
        self.bar = bar
        bar.removeFromSuperview()
        bar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(bar)
        barConstraints = [
            bar.leadingAnchor.constraint(equalTo: searchToolbar.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: searchToolbar.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: searchToolbar.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: AgentListBottomBar.height),
        ]
        NSLayoutConstraint.activate(barConstraints)
        containerView.layoutIfNeeded()
        // Set once: replacing the container's effect redraws all of its glass
        searchToolbar.setGlassMergeSpacing(AgentListBottomBar.glassMergeSpacing)
        bar.setGlassHost(searchToolbar.glassContentView)
        searchToolbar.hostedGlassViews = { [weak bar] in bar?.hostedGlassViews ?? [] }
        bar.onHostEditingChange = { [weak self] isEditing in
            self?.handleEditingChange(isEditing)
        }
        bar.onMorphFrame = { [weak self] progress in
            self?.applyMorphFrame(progress)
        }
        bar.onQuestionChange = { [weak self] in
            self?.updateQuestionLayout()
        }
        isQuestionHeld = bar.hasQuestion
        if !bar.isEditing {
            bar.setExpansion(isQuestionHeld ? 1 : 0)
        }
        applyMorph()
    }

    /// The field's width at rest on the list: wide while it is edited or holds a question
    private var restingExpansion: CGFloat {
        bar?.isEditing == true || isQuestionHeld ? 1 : 0
    }

    /// The search circle stays away past the leading edge: while the field holds a question and isn't edited, when the
    /// circle dissolves in place instead
    private var isSearchCircleAway: Bool {
        isQuestionHeld && bar?.isEditing != true
    }

    /// While the field holds a question, being recorded or recognized or as text, the search circle flies off past the
    /// leading edge and the field widens over its place, as Telegram's attachment button leaves while a voice message
    /// records. Once the question is sent or cleared, they come back. A transition or paging running meanwhile places
    /// them as it goes.
    private func updateQuestionLayout() {
        guard let bar, bar.hasQuestion != isQuestionHeld else { return }
        isQuestionHeld = bar.hasQuestion
        guard !bar.isEditing, !isNavigationHandoffActive, handoffMotion == nil, host?.agentBarSideEdge == nil else {
            return
        }
        // Under a chat the circle waits away and the field is the chat's composer; the pop places them
        guard host?.agentBarNavigationController?.viewControllers.count ?? 1 <= 1 else { return }
        let isAway = isQuestionHeld
        guard morphProgress >= 1, !bar.isHidden, bar.window != nil, !UIAccessibility.isReduceMotionEnabled else {
            bar.setExpansion(restingExpansion)
            UIView.performWithoutAnimation {
                bar.layoutIfNeeded()
                if morphProgress >= 1 { applySearchCircleFlight(isAway ? 1 : 0) }
            }
            return
        }
        questionAnimator?.stopAnimation(false)
        questionAnimator?.finishAnimation(at: .current)
        // The circle keeps its glass on the way out and lets it go once out of sight; coming back it has its glass
        // before it moves
        if !isAway {
            UIView.performWithoutAnimation { applySearchCircleFlight(1, keepsGlass: true) }
        }
        bar.setExpansion(restingExpansion)
        let animator = AgentListBottomBar.makeQuestionAnimator()
        animator.addAnimations { [weak self, weak bar] in
            bar?.layoutIfNeeded()
            self?.applySearchCircleFlight(isAway ? 1 : 0, keepsGlass: true)
        }
        animator.addCompletion { [weak self, weak animator] _ in
            guard let self, questionAnimator === animator else { return }
            questionAnimator = nil
            if isAway, isSearchCircleAway, !isNavigationHandoffActive, morphProgress >= 1 {
                applySearchCircleFlight(1)
            }
        }
        questionAnimator = animator
        animator.startAnimation()
    }

    /// Paging progress toward the Agent tab: 0 shows the regular toolbar, 1 the search circle and the question field
    func setMorphProgress(_ progress: CGFloat) {
        let progress = min(1, max(0, progress))
        guard progress != morphProgress else { return }
        morphProgress = progress
        if progress < 1, bar?.isEditing == true {
            bar?.resignEditing()
        }
        applyMorph()
    }

    private func applyMorph() {
        let progress = morphProgress
        host?.agentBarMorphProgressDidChange(progress)
        guard let bar else {
            searchToolbar.setTrailingHandoffProgress(progress)
            return
        }
        // The bar follows on a spring and reports each frame back through `applyMorphFrame`
        bar.setMorphProgress(progress)
        applyMorphFrame(bar.morphProgress)
    }

    /// One frame of the bar's spring: the toolbar's field shrinks into the circle under the bar's field, swelling like
    /// the bar, and the field and the trailing button the bar folds back into settle with the same slight bounce
    private func applyMorphFrame(_ progress: CGFloat) {
        guard let bar else { return }
        let clamped = min(1, max(0, progress))
        // The toolbar's own pieces show whenever the bar doesn't, so no frame goes without the trailing button
        let isBarFolded = clamped <= 0.001
        bar.toolbarActionsWidth = searchToolbar.homeActionsWidth
        searchToolbar.setTrailingHandoffProgress(isBarFolded ? 0 : AgentListBottomBar.getSearchCircleCollapse(at: clamped))
        let isOnRoot = host?.agentBarNavigationController?.viewControllers.count ?? 1 <= 1
        bar.isHidden = isBarFolded || !isOnRoot || !isAvailable
        if !bar.isHidden, bar.alpha < 1, !isNavigationHandoffActive { bar.alpha = 1 }
        guard !isNavigationHandoffActive, bar.isEditing == false else { return }
        let swell = progress > 0.001 && progress < 0.999 || abs(progress - morphProgress) > 0.001
            ? AgentListBottomBar.swell(at: min(1.15, max(-0.1, progress)))
            : 1
        // Under a chat the circle waits away, where the chat's composer stands: a fold still springing from a tab switch
        // made with the push, as asking the Agent from search does, must not bring it back over the composer
        if !isOnRoot, host?.agentBarNavigationController?.topViewController is any AgentComposerHandoffTarget {
            searchToolbar.setTrailingButtonHandoffScale(1)
            return
        }
        if isSearchCircleAway {
            // Away for a question on the Agent tab, the circle comes back to the toolbar as the bar folds into it
            applySearchCircleFlight(clamped, scale: swell)
        } else {
            searchToolbar.setFieldHandoffAppearance(scale: swell, alpha: 1)
        }
        searchToolbar.setTrailingButtonHandoffScale(swell)
    }

    /// The list's new chat is about to become the chat of the question just sent, in place: the field keeps the
    /// composer's width as it gives up the keyboard, and rides down with it as the chat fades in around it, until the
    /// chat's composer takes its place where it lands. Call before the field resigns.
    func beginComposedChatHandoff() {
        guard bar?.isEditing == true, host?.agentBarSideEdge == nil else { return }
        isComposedChatHandoffPending = true
    }

    private func handleEditingChange(_ isEditing: Bool) {
        guard let bar else { return }
        if isEditing {
            isComposedChatHandoffPending = false
        } else if isComposedChatHandoffPending {
            // The search circle stays away and the field stays wide: they are the chat's composer already. The field
            // goes down on the keyboard's own curve, which its notification brings, as the chat's composer follows the
            // keyboard: on a curve of its own the field would land first, and the composer would take over above it.
            isNavigationHandoffActive = true
            host?.agentBarDidHandOffEditingToComposedChat()
            return
        }
        host?.agentBarEditingDidChange(isEditing)
        isQuestionHeld = bar.hasQuestion
        // The field widens over the search circle on the capsules' spring as the keyboard comes up, flowing into the
        // circle's glass, and the circle dematerializes in place as Telegram's glass does, swelling as it fades; it
        // comes back the same way. A field left with a question stays wide, its circle waiting away out of sight.
        animateExpansion(bar, to: restingExpansion)
        if isSearchCircleAway {
            UIView.performWithoutAnimation { applySearchCircleFlight(1) }
            return
        }
        let dissolve = { self.applySearchCircleDissolve(isEditing ? 1 : 0) }
        guard !UIAccessibility.isReduceMotionEnabled, bar.window != nil else {
            UIView.performWithoutAnimation(dissolve)
            return
        }
        UIView.animate(
            withDuration: TimeInterval(GlassMotion.transition.response),
            delay: 0,
            usingSpringWithDamping: GlassMotion.materialize.dampingRatio,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: dissolve
        )
    }

    /// The question field becomes a chat's composer as the chat is pushed, and returns as it is popped. The
    /// toolbar stays in place meanwhile; its search circle flies off past the leading edge as the field widens, and
    /// flies back in on the way back.
    func updateForNavigation(
        showing viewController: UIViewController,
        isShowingRoot: Bool,
        in navigationController: WNavigationController
    ) {
        stopComposedChatLanding()
        // A tab menu can still be dismissing when its selection updates the root toolbar.
        // Only a push or pop carries the Agent field into another screen.
        let coordinator = navigationController.transitionCoordinator.flatMap {
            $0.presentationStyle == .none ? $0 : nil
        }
        guard isAvailable else {
            handoffMotion?.stop()
            handoffMotion = nil
            isNavigationHandoffActive = false
            bar?.isHidden = true
            searchToolbar.shouldKeepPlaceWhenEmpty = false
            return
        }
        // The composed chat comes without a transition; its composer is the field already, still riding the keyboard
        if isComposedChatHandoffPending, isShowingRoot, coordinator == nil {
            return
        }
        let isComposedChat = isComposedChatHandoffPending
        isComposedChatHandoffPending = false
        guard let bar, morphProgress > 0, host?.agentBarSideEdge == nil else {
            if searchToolbar.shouldKeepPlaceWhenEmpty {
                searchToolbar.shouldKeepPlaceWhenEmpty = false
                searchToolbar.setFieldHandoffAppearance(scale: 1, alpha: 1)
            }
            return
        }
        // The root shown again without a transition, as when the pages settle once the field takes focus and paging
        // stops, with the bar already resting there: nothing moves, and the field keeps widening or narrowing on its
        // own spring, the search circle dissolving or coming back beside it
        if isShowingRoot, coordinator == nil, !isComposedChat, !isNavigationHandoffActive,
           handoffMotion == nil, !bar.isHidden, bar.alpha > 0.99 {
            return
        }
        let fromViewController = coordinator?.viewController(forKey: .from)
        // Only a screen directly above the list takes over its bar; deeper pushes, such as a News discussion, leave
        // the bar hidden and the toolbar away
        let involvesList = isShowingRoot || (coordinator.map { _ in
            fromViewController === navigationController.viewControllers.first
        } ?? (navigationController.viewControllers.count == 2))
        guard involvesList else {
            isNavigationHandoffActive = false
            bar.isHidden = true
            bar.alpha = 0
            searchToolbar.shouldKeepPlaceWhenEmpty = false
            searchToolbar.setFieldHandoffAppearance(scale: 1, alpha: 1)
            return
        }
        let otherViewController = isShowingRoot ? fromViewController : viewController
        let handoffTarget = otherViewController as? any AgentComposerHandoffTarget
        // Back from a chat whose composer rides the keyboard, as through a swipe back while typing, the composer stays
        // with the chat above the keyboard, which leaves with it, and the list's field comes in at the bottom as they
        // go, as Telegram's input panel does
        let keepsComposer = isShowingRoot && handoffTarget?.isComposerOnKeyboard == true
        let finalAlpha: CGFloat = isShowingRoot ? 1 : 0
        let finalExpansion: CGFloat = isShowingRoot ? restingExpansion : 1
        // A field that holds a question goes and comes back wide, its circle away
        let finalFlight: CGFloat = isShowingRoot && !isSearchCircleAway ? 0 : 1
        searchToolbar.shouldKeepPlaceWhenEmpty = handoffTarget != nil

        func finish(isRootShown: Bool) {
            stopComposedChatLanding()
            handoffMotion?.stop()
            handoffMotion = nil
            isNavigationHandoffActive = false
            bar.isHidden = !isRootShown || !isAvailable
            bar.alpha = isRootShown ? 1 : 0
            bar.setExpansion(isRootShown ? restingExpansion : 1)
            if isRootShown, isSearchCircleAway {
                applySearchCircleFlight(1)
                searchToolbar.shouldKeepPlaceWhenEmpty = false
            } else if isRootShown || handoffTarget == nil {
                searchToolbar.setFieldHandoffAppearance(scale: 1, alpha: 1)
                searchToolbar.shouldKeepPlaceWhenEmpty = false
            } else {
                // Under the chat the circle waits off screen, where the pop brings it back from
                applySearchCircleFlight(1)
            }
            handoffTarget?.setComposerHandoffHidden(false)
            // A question sent or cleared during the transition moves the circle and the field once it ends
            if isRootShown { updateQuestionLayout() }
        }

        handoffMotion?.stop()
        handoffMotion = nil
        bar.setSearchHandoff(0)
        searchToolbar.isTrailingButtonHandedOff = false
        guard let coordinator, coordinator.isAnimated else {
            if isComposedChat, let handoffTarget {
                landComposedChat(bar, on: handoffTarget) { finish(isRootShown: false) }
            } else {
                finish(isRootShown: isShowingRoot)
            }
            return
        }
        if let search = host?.agentBarSearchViewController, otherViewController === search {
            startSearchHandoff(bar, isShowingRoot: isShowingRoot, coordinator: coordinator)
            return
        }
        isNavigationHandoffActive = handoffTarget != nil
        bar.isHidden = false
        if isShowingRoot {
            bar.setExpansion(handoffTarget == nil ? restingExpansion : 1)
            bar.alpha = handoffTarget == nil || keepsComposer ? 0 : 1
            if handoffTarget != nil || isSearchCircleAway {
                applySearchCircleFlight(1)
            }
        }
        if !keepsComposer {
            handoffTarget?.setComposerHandoffHidden(true)
        }
        host?.agentBarHostView.layoutIfNeeded()

        guard handoffTarget != nil else {
            let accepted = coordinator.animate(alongsideTransition: { _ in
                bar.alpha = finalAlpha
            }, completion: { context in
                finish(isRootShown: context.isCancelled ? !isShowingRoot : isShowingRoot)
            })
            if !accepted { finish(isRootShown: isShowingRoot) }
            return
        }

        // As Telegram's bars do, the field and the circle don't follow the transition: they move on the glass spring
        // once a push or a tapped pop starts, and a swipe back holds them until the finger lifts. A field that holds a
        // question is wide and its circle away already.
        let start: CGFloat = isShowingRoot || isComposedChat || isSearchCircleAway ? 1 : 0
        let motion = AgentHandoffMotion(
            expansion: (from: start, to: finalExpansion),
            dissolve: (from: start, to: finalFlight)
        ) { [weak self, weak bar] expansion, dissolve in
            guard let self, let bar else { return }
            bar.setExpansion(expansion)
            bar.layoutIfNeeded()
            applySearchCircleFlight(dissolve)
        }
        handoffMotion = motion
        var isRootShownAfterTransition: Bool?
        motion.onSettle = {
            guard let isRootShown = isRootShownAfterTransition else { return }
            finish(isRootShown: isRootShown)
        }
        if coordinator.isInteractive {
            coordinator.notifyWhenInteractionChanges { context in
                if !context.isCancelled { motion.start() }
            }
        }
        let accepted = coordinator.animate(alongsideTransition: { context in
            if !context.isInteractive { motion.start() }
            if keepsComposer { bar.alpha = finalAlpha }
        }, completion: { context in
            let isRootShown = context.isCancelled ? !isShowingRoot : isShowingRoot
            isRootShownAfterTransition = isRootShown
            if context.isCancelled || !motion.isRunning {
                finish(isRootShown: isRootShown)
            }
        })
        if !accepted {
            finish(isRootShown: isShowingRoot)
        }
    }

    /// Keeps the chat's composer hidden while the list's field, in its place, rides the keyboard down, and calls
    /// `finish` to hand over once the field lands
    private func landComposedChat(
        _ bar: AgentListBottomBar,
        on target: any AgentComposerHandoffTarget,
        finish: @escaping () -> Void
    ) {
        isNavigationHandoffActive = true
        bar.isHidden = false
        bar.alpha = 1
        bar.setExpansion(1)
        target.setComposerHandoffHidden(true)
        composedChatTarget = target
        let start = CACurrentMediaTime()
        let landing = GlassMotionClock { [weak self, weak bar, weak target] time in
            guard let self else { return }
            guard let bar, let target, time < start + Self.composedChatLandingTimeout,
                  !Self.isFieldLanding(bar, on: target, after: time - start) else {
                stopComposedChatLanding()
                finish()
                return
            }
        }
        composedChatLanding = landing
        landing.start()
    }

    private static let composedChatLandingTimeout: CFTimeInterval = 1
    /// After this long a field that stopped short of the composer hands over where it stands
    private static let composedChatSettleTimeout: CFTimeInterval = 0.6

    /// Whether the field, as shown with every animation on its way, is still above the chat's composer: the toolbar,
    /// its field and the keyboard's lift each move it
    private static func isFieldLanding(
        _ bar: AgentListBottomBar,
        on target: any AgentComposerHandoffTarget,
        after elapsed: CFTimeInterval
    ) -> Bool {
        guard let window = bar.window else { return false }
        let fieldFrame = bar.fieldFrame
        let modelFrame = bar.convert(fieldFrame, to: window)
        let shownFrame = bar.convertAsShown(fieldFrame, to: window)
        if let composerFrame = target.getComposerHandoffFrame(in: window),
           abs(shownFrame.maxY - composerFrame.maxY) < 0.75 {
            return false
        }
        let isSettled = abs(shownFrame.maxY - modelFrame.maxY) < 0.5
        return !isSettled || elapsed < composedChatSettleTimeout
    }

    private func stopComposedChatLanding() {
        guard let landing = composedChatLanding else { return }
        landing.stop()
        composedChatLanding = nil
        composedChatTarget?.setComposerHandoffHidden(false)
        composedChatTarget = nil
    }

    /// Search opening over the Agent list, and closing back to it: the question field flies off past the trailing
    /// edge as the search circle widens into the search field, and the microphone turns into the search's close
    /// cross, which the toolbar's own close button then takes over; closing plays it backwards. Like the push into a
    /// chat, it moves on the glass spring once the transition starts, or once a swipe back is let go.
    private func startSearchHandoff(
        _ bar: AgentListBottomBar,
        isShowingRoot: Bool,
        coordinator: any UIViewControllerTransitionCoordinator
    ) {
        isNavigationHandoffActive = true
        bar.isHidden = false
        bar.alpha = 1
        bar.setExpansion(restingExpansion)
        searchToolbar.isTrailingButtonHandedOff = true
        let start: CGFloat = isShowingRoot ? 1 : 0
        bar.setSearchHandoff(start)
        // A circle away for a question comes back in as it widens into the search field, and goes again on the way back
        let isCircleAway = isSearchCircleAway
        let motion = AgentHandoffMotion(
            expansion: (from: start, to: 1 - start),
            dissolve: (from: 0, to: 0)
        ) { [weak self, weak bar] progress, _ in
            bar?.setSearchHandoff(progress)
            if isCircleAway { self?.applySearchCircleFlight(1 - progress) }
        }
        handoffMotion = motion
        var isRootShownAfterTransition: Bool?
        let finish = { [weak self, weak bar] (isRootShown: Bool) in
            guard let self else { return }
            handoffMotion?.stop()
            handoffMotion = nil
            isNavigationHandoffActive = false
            bar?.setSearchHandoff(0)
            bar?.isHidden = !isRootShown || !isAvailable
            bar?.alpha = isRootShown ? 1 : 0
            searchToolbar.isTrailingButtonHandedOff = false
            if isCircleAway {
                applySearchCircleFlight(isRootShown ? 1 : 0)
            }
            if isRootShown { updateQuestionLayout() }
        }
        motion.onSettle = {
            guard let isRootShown = isRootShownAfterTransition else { return }
            finish(isRootShown)
        }
        if coordinator.isInteractive {
            coordinator.notifyWhenInteractionChanges { context in
                if !context.isCancelled { motion.start() }
            }
        }
        let accepted = coordinator.animate(alongsideTransition: { context in
            if !context.isInteractive { motion.start() }
        }, completion: { context in
            let isRootShown = context.isCancelled ? !isShowingRoot : isShowingRoot
            isRootShownAfterTransition = isRootShown
            if context.isCancelled || !motion.isRunning {
                finish(isRootShown)
            }
        })
        if !accepted {
            finish(isShowingRoot)
        }
    }

    /// Widens the field for the keyboard or narrows it back on Telegram's spring. Core Animation carries it, so the
    /// main thread's pauses as the keyboard comes up don't jump it, and the keyboard's own layout passes add their
    /// movement to it.
    private func animateExpansion(_ bar: AgentListBottomBar, to target: CGFloat) {
        bar.setExpansion(target)
        let layout = { bar.layoutIfNeeded() }
        guard !UIAccessibility.isReduceMotionEnabled, bar.window != nil else {
            UIView.performWithoutAnimation(layout)
            return
        }
        if #available(iOS 17.0, *) {
            UIView.animate(
                springDuration: TimeInterval(GlassMotion.transition.response),
                bounce: 1 - GlassMotion.transition.dampingRatio,
                initialSpringVelocity: 0,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: layout
            )
        } else {
            UIView.animate(
                withDuration: 0.55,
                delay: 0,
                usingSpringWithDamping: GlassMotion.transition.dampingRatio,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: layout
            )
        }
    }

    /// 0: the search circle as it is; 1: dissolved in place, swollen as glass dematerializes
    private func applySearchCircleDissolve(_ dissolve: CGFloat) {
        let dissolve = min(1, max(0, dissolve))
        let scale = GlassMotion.getMaterializeScale(size: CGSize(width: AgentListBottomBar.height, height: AgentListBottomBar.height)).width
        searchToolbar.setFieldHandoffAppearance(scale: 1 + dissolve * (scale - 1), alpha: 1 - dissolve)
    }

    /// 0: the search circle as it is; 1: flown off past the screen's leading edge, as Telegram's bar items leave for
    /// a pushed screen. A spring's overshoot carries it a little past its place on the way back. Out of sight it lets
    /// its glass go unless `keepsGlass`; coming back it is there at once.
    private func applySearchCircleFlight(_ flight: CGFloat, scale: CGFloat = 1, keepsGlass: Bool = false) {
        let flight = min(1.1, max(-0.1, flight))
        let circle = searchToolbar.convert(searchToolbar.bounds, to: containerView)
        let isRightToLeft = searchToolbar.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let distance = isRightToLeft
            ? containerView.bounds.width - circle.maxX + AgentListBottomBar.height + 24
            : circle.minX + AgentListBottomBar.height + 24
        let alpha: CGFloat = flight >= 0.98 && !keepsGlass ? 0 : 1
        searchToolbar.setFieldHandoffAppearance(
            scale: scale,
            alpha: alpha,
            offset: (isRightToLeft ? 1 : -1) * distance * flight
        )
    }
}

/// Springs the Agent list's field between its own width and a chat composer's, and the search circle between shown
/// and dissolved, on the glass transition spring, in time rather than with a navigation transition's progress
@MainActor
private final class AgentHandoffMotion {
    private let expansion: (from: CGFloat, to: CGFloat)
    private let dissolve: (from: CGFloat, to: CGFloat)
    private let apply: @MainActor (_ expansion: CGFloat, _ dissolve: CGFloat) -> Void
    var onSettle: (() -> Void)?
    private var expansionCurve: GlassSpringCurve?
    private var dissolveCurve: GlassSpringCurve?
    private lazy var clock = GlassMotionClock { [weak self] time in self?.step(at: time) }
    private(set) var isRunning = false

    init(
        expansion: (from: CGFloat, to: CGFloat),
        dissolve: (from: CGFloat, to: CGFloat),
        apply: @escaping @MainActor (_ expansion: CGFloat, _ dissolve: CGFloat) -> Void
    ) {
        self.expansion = expansion
        self.dissolve = dissolve
        self.apply = apply
    }

    func start() {
        guard expansionCurve == nil else { return }
        let now = CACurrentMediaTime()
        let spring = UIAccessibility.isReduceMotionEnabled ? GlassMotion.materialize : GlassMotion.transition
        expansionCurve = GlassSpringCurve(startTime: now, from: expansion.from, target: expansion.to, spring: spring)
        dissolveCurve = GlassSpringCurve(startTime: now, from: dissolve.from, target: dissolve.to, spring: spring)
        isRunning = true
        UIView.performWithoutAnimation { step(at: now) }
        clock.start()
    }

    func stop() {
        clock.stop()
        isRunning = false
    }

    private func step(at time: CFTimeInterval) {
        guard let expansionCurve, let dissolveCurve else { return }
        apply(expansionCurve.getValue(at: time), dissolveCurve.getValue(at: time))
        guard time >= max(expansionCurve.restTime, dissolveCurve.restTime) else { return }
        stop()
        onSettle?()
    }
}
