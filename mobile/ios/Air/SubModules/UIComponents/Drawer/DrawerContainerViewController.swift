import UIKit
import WalletContext

public struct DrawerOpeningGesturePriorityRegion {
    public let view: UIView
    public let contentInsets: UIEdgeInsets

    public init(view: UIView, contentInsets: UIEdgeInsets = .zero) {
        self.view = view
        self.contentInsets = contentInsets
    }
}

public struct DrawerContainerConfiguration {
    public var maximumDrawerWidth: CGFloat
    public var minimumExposedMainWidth: CGFloat
    public var mainCornerRadius: CGFloat
    public var drawerBackgroundColor: UIColor
    public var openMainContentOpacity: CGFloat
    public var drawerParallaxFactor: CGFloat
    public var drawerMinimumScale: CGFloat
    public var drawerMinimumOpacity: CGFloat
    public var shadowOpacity: Float
    public var shadowRadius: CGFloat
    public var transitionDuration: TimeInterval
    public var minimumTransitionDuration: TimeInterval
    public var springDampingRatio: CGFloat
    public var overscrollReturnDuration: TimeInterval
    public var openingEdgeWidth: CGFloat

    public init(
        maximumDrawerWidth: CGFloat = 333,
        minimumExposedMainWidth: CGFloat = 52,
        mainCornerRadius: CGFloat = 50,
        drawerBackgroundColor: UIColor = .air.background,
        openMainContentOpacity: CGFloat = 0.5,
        drawerParallaxFactor: CGFloat = 0.08,
        drawerMinimumScale: CGFloat = 1,
        drawerMinimumOpacity: CGFloat = 0.76,
        shadowOpacity: Float = 0.16,
        shadowRadius: CGFloat = 32,
        transitionDuration: TimeInterval = 0.42,
        minimumTransitionDuration: TimeInterval = 0.18,
        springDampingRatio: CGFloat = 0.92,
        overscrollReturnDuration: TimeInterval = 0.28,
        openingEdgeWidth: CGFloat = 44
    ) {
        self.maximumDrawerWidth = maximumDrawerWidth
        self.minimumExposedMainWidth = minimumExposedMainWidth
        self.mainCornerRadius = mainCornerRadius
        self.drawerBackgroundColor = drawerBackgroundColor
        self.openMainContentOpacity = openMainContentOpacity
        self.drawerParallaxFactor = drawerParallaxFactor
        self.drawerMinimumScale = drawerMinimumScale
        self.drawerMinimumOpacity = drawerMinimumOpacity
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.transitionDuration = transitionDuration
        self.minimumTransitionDuration = minimumTransitionDuration
        self.springDampingRatio = springDampingRatio
        self.overscrollReturnDuration = overscrollReturnDuration
        self.openingEdgeWidth = openingEdgeWidth
    }
}

@MainActor
public final class DrawerContainerViewController: UIViewController, VisibleContentProviding {
    public let mainViewController: UIViewController
    public let drawerViewController: UIViewController
    public private(set) var configuration: DrawerContainerConfiguration

    public private(set) var isDrawerOpen = false
    public private(set) var transitionProgress: CGFloat = 0

    public let openingGestureRecognizer = UIPanGestureRecognizer()
    public var shouldBeginOpeningGesture: (() -> Bool)?
    public var shouldUseFullWidthOpeningGesture: (() -> Bool)?
    public var openingGesturePriorityRegions: (() -> [DrawerOpeningGesturePriorityRegion])?
    public var onWillOpen: (() -> Void)?

    public var visibleContentProviderViewController: UIViewController {
        isDrawerOpen ? drawerViewController : mainViewController
    }

    private let drawerHostView = UIView()
    private let drawerPresentationView = UIView()
    private let mainShadowView = UIView()
    private let mainClippingView = UIView()
    private let mainContentView = UIView()
    private let dimmingControl = UIControl()
    private let closingGestureRecognizer = UIPanGestureRecognizer()

    private var drawerWidthConstraint: NSLayoutConstraint!
    private var activeAnimator: UIViewPropertyAnimator?
    private var panStartProgress: CGFloat = 0
    private var overscrollTranslation: CGFloat = 0
    private var lastLayoutSize: CGSize = .zero
    private var prioritizedPanGestureRecognizerIDs: Set<ObjectIdentifier> = []

    public init(
        mainViewController: UIViewController,
        drawerViewController: UIViewController,
        configuration: DrawerContainerConfiguration = .init(),
        openingGesturePriorityRegions: (() -> [DrawerOpeningGesturePriorityRegion])? = nil
    ) {
        self.mainViewController = mainViewController
        self.drawerViewController = drawerViewController
        self.configuration = configuration
        self.openingGesturePriorityRegions = openingGesturePriorityRegions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = configuration.drawerBackgroundColor
        view.clipsToBounds = true

        setupHierarchy()
        setupGestures()
        applyVisualProgress(0)
        finishTransition(open: false, announce: false)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshOpeningGesturePriority()
        guard view.bounds.size != lastLayoutSize else { return }

        stopActiveAnimatorAtCurrentProgress()
        lastLayoutSize = view.bounds.size
        drawerWidthConstraint.constant = resolvedDrawerWidth
        applyVisualProgress(transitionProgress)
    }

    public override var childForStatusBarStyle: UIViewController? {
        visibleContentProviderViewController
    }

    public override var childForStatusBarHidden: UIViewController? {
        visibleContentProviderViewController
    }

    public func setDrawerOpen(
        _ open: Bool,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        loadViewIfNeeded()
        stopActiveAnimatorAtCurrentProgress()
        if open {
            onWillOpen?()
        }

        if !animated {
            overscrollTranslation = 0
            applyVisualProgress(open ? 1 : 0)
            finishTransition(open: open)
            completion?()
            return
        }

        animate(toOpen: open, initialVelocityX: 0, completion: completion)
    }

    public func toggleDrawer(animated: Bool = true) {
        setDrawerOpen(!isDrawerOpen, animated: animated)
    }

    public func applyConfiguration(_ configuration: DrawerContainerConfiguration) {
        loadViewIfNeeded()
        stopActiveAnimatorAtCurrentProgress()
        self.configuration = configuration
        view.backgroundColor = configuration.drawerBackgroundColor
        mainShadowView.layer.shadowRadius = configuration.shadowRadius
        drawerWidthConstraint.constant = resolvedDrawerWidth
        view.layoutIfNeeded()
        updateMainCornerConfiguration()
        setMainSurfaceEffectsEnabled(isDrawerOpen || transitionProgress > 0.001)
        applyVisualProgress(transitionProgress)
    }

    private func setupHierarchy() {
        drawerHostView.translatesAutoresizingMaskIntoConstraints = false
        drawerHostView.clipsToBounds = true
        view.addSubview(drawerHostView)

        drawerPresentationView.translatesAutoresizingMaskIntoConstraints = false
        drawerPresentationView.backgroundColor = .clear
        drawerPresentationView.layer.allowsEdgeAntialiasing = true
        drawerHostView.addSubview(drawerPresentationView)

        mainShadowView.translatesAutoresizingMaskIntoConstraints = false
        mainShadowView.backgroundColor = .air.background
        mainShadowView.layer.cornerCurve = .continuous
        mainShadowView.layer.shadowColor = UIColor.black.cgColor
        mainShadowView.layer.shadowOffset = .zero
        mainShadowView.layer.shadowRadius = configuration.shadowRadius
        view.addSubview(mainShadowView)

        mainClippingView.translatesAutoresizingMaskIntoConstraints = false
        mainClippingView.backgroundColor = .clear
        mainClippingView.clipsToBounds = false
        mainClippingView.layer.cornerCurve = .continuous
        mainShadowView.addSubview(mainClippingView)

        mainContentView.translatesAutoresizingMaskIntoConstraints = false
        mainContentView.backgroundColor = .clear
        mainClippingView.addSubview(mainContentView)

        dimmingControl.translatesAutoresizingMaskIntoConstraints = false
        dimmingControl.backgroundColor = .clear
        dimmingControl.isAccessibilityElement = false
        dimmingControl.accessibilityLabel = lang("Close")
        dimmingControl.accessibilityTraits = .button
        dimmingControl.addTarget(self, action: #selector(closeFromTap), for: .touchUpInside)
        mainClippingView.addSubview(dimmingControl)

        drawerWidthConstraint = drawerHostView.widthAnchor.constraint(equalToConstant: resolvedDrawerWidth)
        NSLayoutConstraint.activate([
            drawerHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            drawerHostView.topAnchor.constraint(equalTo: view.topAnchor),
            drawerHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            drawerWidthConstraint,

            drawerPresentationView.leadingAnchor.constraint(equalTo: drawerHostView.leadingAnchor),
            drawerPresentationView.trailingAnchor.constraint(equalTo: drawerHostView.trailingAnchor),
            drawerPresentationView.topAnchor.constraint(equalTo: drawerHostView.topAnchor),
            drawerPresentationView.bottomAnchor.constraint(equalTo: drawerHostView.bottomAnchor),

            mainShadowView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainShadowView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainShadowView.topAnchor.constraint(equalTo: view.topAnchor),
            mainShadowView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            mainClippingView.leadingAnchor.constraint(equalTo: mainShadowView.leadingAnchor),
            mainClippingView.trailingAnchor.constraint(equalTo: mainShadowView.trailingAnchor),
            mainClippingView.topAnchor.constraint(equalTo: mainShadowView.topAnchor),
            mainClippingView.bottomAnchor.constraint(equalTo: mainShadowView.bottomAnchor),

            mainContentView.leadingAnchor.constraint(equalTo: mainClippingView.leadingAnchor),
            mainContentView.trailingAnchor.constraint(equalTo: mainClippingView.trailingAnchor),
            mainContentView.topAnchor.constraint(equalTo: mainClippingView.topAnchor),
            mainContentView.bottomAnchor.constraint(equalTo: mainClippingView.bottomAnchor),

            dimmingControl.leadingAnchor.constraint(equalTo: mainClippingView.leadingAnchor),
            dimmingControl.trailingAnchor.constraint(equalTo: mainClippingView.trailingAnchor),
            dimmingControl.topAnchor.constraint(equalTo: mainClippingView.topAnchor),
            dimmingControl.bottomAnchor.constraint(equalTo: mainClippingView.bottomAnchor),
        ])

        embed(drawerViewController, in: drawerPresentationView)
        embed(mainViewController, in: mainContentView)
        updateMainCornerConfiguration()
        refreshOpeningGesturePriority()
    }

    private func setupGestures() {
        openingGestureRecognizer.addTarget(self, action: #selector(handleOpeningPan(_:)))
        openingGestureRecognizer.delegate = self
        openingGestureRecognizer.cancelsTouchesInView = true
        view.addGestureRecognizer(openingGestureRecognizer)

        closingGestureRecognizer.addTarget(self, action: #selector(handleClosingPan(_:)))
        closingGestureRecognizer.delegate = self
        dimmingControl.addGestureRecognizer(closingGestureRecognizer)
    }

    private func embed(_ child: UIViewController, in container: UIView) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: container.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        child.didMove(toParent: self)
    }

    private func refreshOpeningGesturePriority() {
        guard let rootView = mainViewController.viewIfLoaded else { return }
        var views = [rootView]
        while let candidate = views.popLast() {
            for case let panGestureRecognizer as UIPanGestureRecognizer in candidate.gestureRecognizers ?? [] {
                let identifier = ObjectIdentifier(panGestureRecognizer)
                guard prioritizedPanGestureRecognizerIDs.insert(identifier).inserted else { continue }
                panGestureRecognizer.require(toFail: openingGestureRecognizer)
            }
            views.append(contentsOf: candidate.subviews)
        }
    }

    private var resolvedDrawerWidth: CGFloat {
        min(
            configuration.maximumDrawerWidth,
            max(0, view.bounds.width - configuration.minimumExposedMainWidth)
        )
    }

    private var isRightToLeft: Bool {
        view.effectiveUserInterfaceLayoutDirection == .rightToLeft
    }

    private var directionSign: CGFloat {
        isRightToLeft ? -1 : 1
    }

    private func applyVisualProgress(_ progress: CGFloat) {
        let progress = max(0, min(1, progress))
        transitionProgress = progress

        let drawerWidth = resolvedDrawerWidth
        mainShadowView.transform = CGAffineTransform(
            translationX: directionSign * (drawerWidth * progress + overscrollTranslation),
            y: 0
        )
        let drawerScale = configuration.drawerMinimumScale
            + (1 - configuration.drawerMinimumScale) * progress
        let parallaxTranslationX = -directionSign
            * drawerWidth
            * configuration.drawerParallaxFactor
            * (1 - progress)
        // Keep controller geometry stable; scaling an ancestor makes navigation bars relayout mid-transition.
        drawerPresentationView.layer.sublayerTransform = drawerSublayerTransform(
            scale: drawerScale,
            translationX: parallaxTranslationX
        )
        drawerPresentationView.alpha = configuration.drawerMinimumOpacity
            + (1 - configuration.drawerMinimumOpacity) * progress
        mainContentView.alpha = 1 - (1 - configuration.openMainContentOpacity) * progress
        dimmingControl.isUserInteractionEnabled = progress > 0.01
    }

    private func drawerSublayerTransform(scale: CGFloat, translationX: CGFloat) -> CATransform3D {
        let affineTransform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: translationX,
            ty: 0
        )
        return CATransform3DMakeAffineTransform(affineTransform)
    }

    private func updateMainCornerConfiguration() {
        mainShadowView.layer.cornerRadius = configuration.mainCornerRadius
        mainClippingView.layer.cornerRadius = configuration.mainCornerRadius
        mainShadowView.layer.shadowPath = nil
        if #available(iOS 26.0, *) {
            let corners = UICornerConfiguration.corners(
                radius: .containerConcentric(minimum: configuration.mainCornerRadius)
            )
            mainShadowView.cornerConfiguration = corners
            mainClippingView.cornerConfiguration = corners
        }
    }

    private func setMainSurfaceEffectsEnabled(_ enabled: Bool) {
        mainClippingView.clipsToBounds = enabled
        mainShadowView.layer.shadowOpacity = enabled ? configuration.shadowOpacity : 0
    }

    private func animate(
        toOpen open: Bool,
        initialVelocityX: CGFloat,
        completion: (() -> Void)? = nil
    ) {
        let targetProgress: CGFloat = open ? 1 : 0
        let distance = abs(targetProgress - transitionProgress)
        let hasOverscroll = overscrollTranslation > 0.001
        guard distance > 0.001 || hasOverscroll else {
            applyVisualProgress(targetProgress)
            finishTransition(open: open)
            completion?()
            return
        }

        drawerHostView.isHidden = false
        setMainSurfaceEffectsEnabled(true)
        mainContentView.isUserInteractionEnabled = false
        isDrawerOpen = open
        updateAccessibility(open: open)
        setNeedsStatusBarAppearanceUpdate()

        let normalizedVelocity = max(
            -5,
            min(5, directionSign * initialVelocityX / max(1, resolvedDrawerWidth))
        )
        let timing = UISpringTimingParameters(
            dampingRatio: configuration.springDampingRatio,
            initialVelocity: CGVector(dx: normalizedVelocity, dy: 0)
        )
        let animator = UIViewPropertyAnimator(
            duration: hasOverscroll
                ? configuration.overscrollReturnDuration
                : max(
                    configuration.minimumTransitionDuration,
                    configuration.transitionDuration * TimeInterval(distance)
                ),
            timingParameters: timing
        )
        animator.addAnimations { [weak self] in
            self?.overscrollTranslation = 0
            self?.applyVisualProgress(targetProgress)
        }
        animator.addCompletion { [weak self] position in
            guard position == .end else { return }
            self?.activeAnimator = nil
            self?.applyVisualProgress(targetProgress)
            self?.finishTransition(open: open)
            completion?()
        }
        activeAnimator = animator
        animator.startAnimation()
    }

    private func finishTransition(open: Bool, announce: Bool = true) {
        isDrawerOpen = open
        drawerHostView.isHidden = !open
        mainContentView.isUserInteractionEnabled = !open
        setMainSurfaceEffectsEnabled(open)
        updateAccessibility(open: open)
        setNeedsStatusBarAppearanceUpdate()

        guard announce else { return }
        UIAccessibility.post(
            notification: .screenChanged,
            argument: open ? drawerViewController.view : mainViewController.view
        )
    }

    private func updateAccessibility(open: Bool) {
        drawerViewController.view.accessibilityElementsHidden = !open
        drawerViewController.view.accessibilityViewIsModal = open
        mainViewController.view.accessibilityElementsHidden = open
        dimmingControl.isAccessibilityElement = open
        dimmingControl.accessibilityElementsHidden = !open
    }

    public override func accessibilityPerformEscape() -> Bool {
        guard isDrawerOpen else { return super.accessibilityPerformEscape() }
        setDrawerOpen(false, animated: true)
        return true
    }

    private func stopActiveAnimatorAtCurrentProgress() {
        guard let activeAnimator else { return }
        let currentProgress = presentedProgress
        activeAnimator.stopAnimation(true)
        self.activeAnimator = nil
        applyVisualProgress(currentProgress)
        mainContentView.isUserInteractionEnabled = !isDrawerOpen
    }

    private var presentedProgress: CGFloat {
        guard resolvedDrawerWidth > 0,
              let transform = mainShadowView.layer.presentation()?.transform else {
            return transitionProgress
        }
        return max(0, min(1, abs(transform.m41) / resolvedDrawerWidth))
    }

    private func beginInteractiveTransition() {
        stopActiveAnimatorAtCurrentProgress()
        drawerHostView.isHidden = false
        panStartProgress = transitionProgress
        suspendMainContentInteraction()
        setMainSurfaceEffectsEnabled(true)
    }

    private func suspendMainContentInteraction() {
        mainContentView.isUserInteractionEnabled = false
        var views = [mainContentView]
        while let candidate = views.popLast() {
            for gestureRecognizer in candidate.gestureRecognizers ?? [] where gestureRecognizer.isEnabled {
                gestureRecognizer.isEnabled = false
                gestureRecognizer.isEnabled = true
            }
            views.append(contentsOf: candidate.subviews)
        }
    }

    private func updateInteractiveTransition(translationX: CGFloat) {
        let normalizedTranslation = directionSign * translationX / max(1, resolvedDrawerWidth)
        let proposedProgress = panStartProgress + normalizedTranslation
        if proposedProgress > 1 {
            let excess = (proposedProgress - 1) * resolvedDrawerWidth
            overscrollTranslation = rubberBandOffset(for: excess)
            applyVisualProgress(1)
        } else {
            overscrollTranslation = 0
            applyVisualProgress(proposedProgress)
        }
    }

    private func rubberBandOffset(for distance: CGFloat) -> CGFloat {
        let dimension = max(1, resolvedDrawerWidth)
        return (1 - 1 / (distance * 0.55 / dimension + 1)) * dimension
    }

    private func finishInteractiveTransition(velocityX: CGFloat, cancelled: Bool) {
        let normalizedVelocity = directionSign * velocityX
        let targetOpen: Bool
        if cancelled {
            targetOpen = panStartProgress >= 0.5
        } else if normalizedVelocity > 450 {
            targetOpen = true
        } else if normalizedVelocity < -450 {
            targetOpen = false
        } else {
            targetOpen = transitionProgress >= 0.45
        }
        animate(toOpen: targetOpen, initialVelocityX: velocityX)
    }

    @objc private func closeFromTap() {
        setDrawerOpen(false, animated: true)
    }

    @objc private func handleOpeningPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            onWillOpen?()
            beginInteractiveTransition()
        case .changed:
            updateInteractiveTransition(translationX: gesture.translation(in: view).x)
        case .ended:
            finishInteractiveTransition(velocityX: gesture.velocity(in: view).x, cancelled: false)
        case .cancelled, .failed:
            finishInteractiveTransition(velocityX: 0, cancelled: true)
        default:
            break
        }
    }

    @objc private func handleClosingPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginInteractiveTransition()
        case .changed:
            updateInteractiveTransition(translationX: gesture.translation(in: view).x)
        case .ended:
            finishInteractiveTransition(velocityX: gesture.velocity(in: view).x, cancelled: false)
        case .cancelled, .failed:
            finishInteractiveTransition(velocityX: 0, cancelled: true)
        default:
            break
        }
    }
}

extension DrawerContainerViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === openingGestureRecognizer || otherGestureRecognizer === openingGestureRecognizer
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let velocity: CGPoint
        if let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer {
            velocity = panGestureRecognizer.velocity(in: view)
        } else {
            return true
        }

        guard abs(velocity.x) > abs(velocity.y) else { return false }
        let normalizedVelocityX = directionSign * velocity.x

        if gestureRecognizer === openingGestureRecognizer {
            guard shouldBeginOpeningGesture?() ?? true else { return false }
            let startsInPriorityView = openingGesturePriorityRegions?().contains { region in
                let priorityView = region.view
                let priorityBounds = priorityView.bounds.inset(by: region.contentInsets)
                return priorityView.window != nil
                    && !priorityView.isHidden
                    && priorityView.alpha > 0.01
                    && !priorityBounds.isEmpty
                    && priorityBounds.contains(gestureRecognizer.location(in: priorityView))
            } == true
            guard !startsInPriorityView else { return false }
            if shouldUseFullWidthOpeningGesture?() != true {
                let locationX = gestureRecognizer.location(in: view).x
                let initialLocationX = locationX - openingGestureRecognizer.translation(in: view).x
                let isInsideOpeningEdge = isRightToLeft
                    ? initialLocationX >= view.bounds.maxX - configuration.openingEdgeWidth
                    : initialLocationX <= configuration.openingEdgeWidth
                guard isInsideOpeningEdge else { return false }
            }
            return transitionProgress < 0.001 && normalizedVelocityX > 0
        }
        if gestureRecognizer === closingGestureRecognizer {
            return transitionProgress > 0.999
        }
        return true
    }
}

public extension UIViewController {
    var drawerContainerViewController: DrawerContainerViewController? {
        var candidate: UIViewController? = self
        while let viewController = candidate {
            if let drawerContainer = viewController as? DrawerContainerViewController {
                return drawerContainer
            }
            candidate = viewController.parent
        }
        return nil
    }
}
