import UIKit

/// Discrete states supported by a minimizable sheet.
public enum MinimizableSheetState: Equatable {
    /// Sheet is fully hidden.
    case hidden
    /// Sheet is visible in compact/minimized mode.
    case minimized
    /// Sheet is fully expanded.
    case expanded
}

/// Configuration for `MinimizableSheetContainerViewController`.
public struct MinimizableSheetConfiguration {

    /// Controls where the expanded sheet stops at the top edge.
    public enum ExpandedTopInsetMode {
        /// Expanded sheet stops at the top safe area inset.
        case safeArea
    }

    /// Visible minimized height above the bottom safe area.
    public var minimizedVisibleHeight: CGFloat = 50
    /// Height of the separator/gap between main content and minimized sheet.
    public var separatorHeight: CGFloat = 4
    /// Range used to smooth interactive transition around minimized height.
    public var minimizedTransitionRange: CGFloat = 40
    /// Dimming alpha used when the sheet is fully expanded.
    public var expandedDimmingAlpha: CGFloat = 0.14
    /// Top corner radius used while minimized.
    public var minimizedCornerRadius: CGFloat = 20
    /// Top corner radius used while expanded.
    public var expandedCornerRadius: CGFloat = 26
    /// Duration for larger transitions involving `.expanded`.
    public var largeTransitionDuration: TimeInterval = 0.42
    /// Duration for compact transitions between `.minimized` and `.hidden`.
    public var compactTransitionDuration: TimeInterval = 0.24
    /// Top inset behavior for expanded sheet.
    public var expandedTopInsetMode: ExpandedTopInsetMode = .safeArea

    /// Default configuration values.
    public static let `default` = MinimizableSheetConfiguration()

    /// Creates a configuration with default values.
    public init() {}
}

/// Final state transition emitted after a sheet state change completes.
public struct MinimizableSheetStateChange {
    /// Previous sheet state.
    public let fromState: MinimizableSheetState
    /// New sheet state.
    public let toState: MinimizableSheetState

    /// Creates a state change value.
    public init(fromState: MinimizableSheetState, toState: MinimizableSheetState) {
        self.fromState = fromState
        self.toState = toState
    }
}

/// Interactive transition payload emitted during pan gestures.
public struct MinimizableSheetInteractiveTransition {
    /// Source state for the interactive transition.
    public let fromState: MinimizableSheetState
    /// Destination state for the interactive transition.
    public let toState: MinimizableSheetState
    /// Normalized transition progress in `[0, 1]`.
    public let progress: CGFloat
    /// Current visible sheet height in points.
    public let currentSheetHeight: CGFloat

    /// Creates an interactive transition value.
    public init(
        fromState: MinimizableSheetState,
        toState: MinimizableSheetState,
        progress: CGFloat,
        currentSheetHeight: CGFloat
    ) {
        self.fromState = fromState
        self.toState = toState
        self.progress = progress
        self.currentSheetHeight = currentSheetHeight
    }
}

/// Event stream emitted by `MinimizableSheetController` observers.
public enum MinimizableSheetEvent {
    /// Non-interactive state transition start event, emitted before animation begins.
    case stateWillChange(MinimizableSheetStateChange)
    /// Non-interactive state change event.
    case stateDidChange(MinimizableSheetStateChange)
    /// Interactive transition update event.
    case interactiveTransition(MinimizableSheetInteractiveTransition)
}

/// Observation categories for `MinimizableSheetController.addObserver`.
public struct MinimizableSheetObservationOptions: OptionSet {
    /// Option set raw value.
    public let rawValue: Int

    /// Creates observation options from a raw value.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Observe state transition start events emitted before animation/layout changes begin.
    public static let stateWillChanges = MinimizableSheetObservationOptions(rawValue: 1 << 0)
    /// Observe only final state changes.
    public static let stateChanges = MinimizableSheetObservationOptions(rawValue: 1 << 1)
    /// Observe interactive transition progress updates.
    public static let interactiveTransitions = MinimizableSheetObservationOptions(rawValue: 1 << 2)
    /// Observe all available events.
    public static let all: MinimizableSheetObservationOptions = [.stateWillChanges, .stateChanges, .interactiveTransitions]
}

/// Handle that keeps an observer alive until invalidated or deallocated.
public final class MinimizableSheetObservation {

    private var onInvalidate: (() -> Void)?

    init(onInvalidate: @escaping () -> Void) {
        self.onInvalidate = onInvalidate
    }

    /// Stops receiving events for this observation.
    public func invalidate() {
        onInvalidate?()
        onInvalidate = nil
    }

    deinit {
        invalidate()
    }
}

/// Public control surface for a minimizable sheet.
public final class MinimizableSheetController {

    fileprivate weak var container: MinimizableSheetContainerViewController?

    /// Current resolved state of the sheet.
    public var state: MinimizableSheetState {
        container?.sheetState ?? .hidden
    }

    /// Sets the sheet state.
    /// - Parameters:
    ///   - state: Target state.
    ///   - animated: Whether to animate the transition.
    public func setState(_ state: MinimizableSheetState, animated: Bool = true) {
        container?.setSheetState(state, animated: animated)
    }

    /// Expands the sheet.
    /// - Parameter animated: Whether to animate the transition.
    public func expand(animated: Bool = true) {
        setState(.expanded, animated: animated)
    }

    /// Minimizes the sheet.
    /// - Parameter animated: Whether to animate the transition.
    public func minimize(animated: Bool = true) {
        setState(.minimized, animated: animated)
    }

    /// Hides/closes the sheet.
    /// - Parameter animated: Whether to animate the transition.
    public func close(animated: Bool = true) {
        setState(.hidden, animated: animated)
    }

    /// Subscribes to sheet events.
    /// - Parameters:
    ///   - options: Event categories to observe.
    ///   - observer: Callback invoked on each matching event.
    /// - Returns: A token that must be retained to keep the observer active.
    public func addObserver(
        options: MinimizableSheetObservationOptions = .stateChanges,
        _ observer: @escaping (MinimizableSheetEvent) -> Void
    ) -> MinimizableSheetObservation {
        guard let container else {
            return MinimizableSheetObservation(onInvalidate: {})
        }
        return container.addObserver(options: options, observer)
    }
}

/// Container view controller that hosts a main view controller and a minimizable sheet.
///
/**
 `MinimizableSheetContainerViewController` is a UIKit container that hosts:

 - a main content view controller
 - a sheet content view controller with states: `.hidden`, `.minimized`, `.expanded`

 The sheet is **not** presented with `present(...)`; it is a child inside the container.

 ## Create A Root View Controller

 ```swift
 import UIKit

 final class RootViewController: UIViewController {
     private let sheetContainer: MinimizableSheetContainerViewController = {
         var config = MinimizableSheetConfiguration.default
         config.minimizedVisibleHeight = 50
         config.largeTransitionDuration = 0.42   // expanded <-> minimized
         config.compactTransitionDuration = 0.24 // minimized <-> hidden

         return MinimizableSheetContainerViewController(
             mainViewController: MainContentViewController(),
             sheetViewController: SheetContentViewController(),
             configuration: config
         )
     }()

     override func viewDidLoad() {
         super.viewDidLoad()
         addChild(sheetContainer)
         view.addSubview(sheetContainer.view)
         sheetContainer.view.translatesAutoresizingMaskIntoConstraints = false
         NSLayoutConstraint.activate([
             sheetContainer.view.topAnchor.constraint(equalTo: view.topAnchor),
             sheetContainer.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
             sheetContainer.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
             sheetContainer.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
         ])
         sheetContainer.didMove(toParent: self)
     }
 }
 ```

 ## Show / Hide (Present) The Sheet

 From any descendant view controller:

 ```swift
 minimizableSheetController?.expand(animated: true)    // show expanded
 minimizableSheetController?.minimize(animated: true)  // collapse
 minimizableSheetController?.close(animated: true)     // hide
 ```

 You can also set an explicit target state:

 ```swift
 minimizableSheetController?.setState(.expanded, animated: true)
 ```

 ## Observe State Changes

 Retain the observation token for as long as you need updates:

 ```swift
 final class SheetContentViewController: UIViewController {
     private var sheetObservation: MinimizableSheetObservation?

     override func viewDidAppear(_ animated: Bool) {
         super.viewDidAppear(animated)

         guard sheetObservation == nil,
               let controller = minimizableSheetController else { return }

         sheetObservation = controller.addObserver(options: .stateChanges) { event in
             guard case let .stateDidChange(change) = event else { return }
             print("Sheet state: \(change.fromState) -> \(change.toState)")
         }
     }
 }
 ```

 To also track interactive pan progress:

 ```swift
 sheetObservation = controller.addObserver(options: .all) { event in
     switch event {
     case .stateWillChange(let change):
         print("Will change: \(change.fromState) -> \(change.toState)")
     case .stateDidChange(let change):
         print("State: \(change.fromState) -> \(change.toState)")
     case .interactiveTransition(let transition):
         print("Progress: \(transition.progress), to: \(transition.toState)")
     }
 }
 ```

 ## Useful Public Types

 - `MinimizableSheetContainerViewController`
 - `MinimizableSheetController`
 - `MinimizableSheetState`
 - `MinimizableSheetConfiguration`
 - `MinimizableSheetObservationOptions`
 - `MinimizableSheetEvent`
 - `MinimizableSheetStateChange`
 - `MinimizableSheetInteractiveTransition`
 */
open class MinimizableSheetContainerViewController: UIViewController {

    private struct LayoutValues {
        let sheetHeight: CGFloat
        let mainBottomOffset: CGFloat
        let dimAlpha: CGFloat
        let mainCornerRadius: CGFloat
        let sheetCornerRadius: CGFloat
    }

    private struct ObserverEntry {
        let options: MinimizableSheetObservationOptions
        let handler: (MinimizableSheetEvent) -> Void
    }

    /// Embedded main content view controller.
    public let mainViewController: UIViewController
    /// Embedded sheet content view controller.
    public let sheetViewController: UIViewController
    /// Controller object used to query and control sheet state.
    public let sheetController = MinimizableSheetController()

    private let configuration: MinimizableSheetConfiguration

    private let mainContainerView = UIView()
    private let dimmingView = UIView()
    private let sheetContainerView = UIView()
    private let sheetContentHostView = UIView()

    private var mainBottomConstraint: NSLayoutConstraint!
    private var sheetHeightConstraint: NSLayoutConstraint!
    private var sheetContentHeightConstraint: NSLayoutConstraint!

    fileprivate private(set) var sheetState: MinimizableSheetState = .hidden
    private var panStartHeight: CGFloat = 0
    private var panStartState: MinimizableSheetState = .hidden
    private weak var panTrackedScrollView: UIScrollView?
    private var panHasNestedScrollHandoff: Bool = false
    private var panNestedHandoffTranslationY: CGFloat = 0
    private var panNestedHandoffStartHeight: CGFloat = 0
    private var lastLayoutBoundsSize: CGSize = .zero

    private var observers: [UUID: ObserverEntry] = [:]

    private lazy var sheetPanGestureRecognizer: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSheetPan(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = self
        return pan
    }()

    /// Creates a container with a main content controller and a sheet controller.
    /// - Parameters:
    ///   - mainViewController: Main content controller (full-screen background layer).
    ///   - sheetViewController: Sheet content controller (foreground sheet layer).
    ///   - configuration: Sheet behavior and animation configuration.
    public init(
        mainViewController: UIViewController,
        sheetViewController: UIViewController,
        configuration: MinimizableSheetConfiguration = .default
    ) {
        self.mainViewController = mainViewController
        self.sheetViewController = sheetViewController
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
        sheetController.container = self
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupLayout()
        setupChildren()
        setupInteractions()
        setSheetState(.hidden, animated: false)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let currentSize = view.bounds.size
        guard currentSize != lastLayoutBoundsSize else { return }
        lastLayoutBoundsSize = currentSize
        setSheetState(sheetState, animated: false)
    }

    private func setupLayout() {
        mainContainerView.translatesAutoresizingMaskIntoConstraints = false
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        sheetContainerView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(mainContainerView)
        view.addSubview(dimmingView)
        view.addSubview(sheetContainerView)

        dimmingView.backgroundColor = UIColor.black
        dimmingView.alpha = 0

        mainContainerView.layer.cornerCurve = .continuous
        mainContainerView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        mainContainerView.layer.cornerRadius = 0
        mainContainerView.clipsToBounds = true

        sheetContainerView.backgroundColor = .secondarySystemBackground
        sheetContainerView.layer.cornerRadius = configuration.minimizedCornerRadius
        sheetContainerView.layer.cornerCurve = .continuous
        sheetContainerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetContainerView.clipsToBounds = true

        mainBottomConstraint = mainContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        sheetHeightConstraint = sheetContainerView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            mainContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            mainContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainBottomConstraint,

            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sheetContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheetContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheetContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sheetHeightConstraint,
        ])
    }

    private func setupChildren() {
        embed(mainViewController, in: mainContainerView)

        sheetContentHostView.translatesAutoresizingMaskIntoConstraints = false
        sheetContainerView.addSubview(sheetContentHostView)

        sheetContentHeightConstraint = sheetContentHostView.heightAnchor.constraint(equalToConstant: expandedSheetHeight)

        NSLayoutConstraint.activate([
            sheetContentHostView.topAnchor.constraint(equalTo: sheetContainerView.topAnchor),
            sheetContentHostView.leadingAnchor.constraint(equalTo: sheetContainerView.leadingAnchor),
            sheetContentHostView.trailingAnchor.constraint(equalTo: sheetContainerView.trailingAnchor),
            sheetContentHeightConstraint
        ])

        embed(sheetViewController, in: sheetContentHostView)
    }

    private func setupInteractions() {
        let dimTap = UITapGestureRecognizer(target: self, action: #selector(handleDimTap))
        dimmingView.addGestureRecognizer(dimTap)

        sheetContainerView.addGestureRecognizer(sheetPanGestureRecognizer)
    }

    private func embed(_ child: UIViewController, in container: UIView) {
        addChild(child)
        container.addSubview(child.view)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: container.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        child.didMove(toParent: self)
    }

    private var minimizedSheetHeight: CGFloat {
        configuration.minimizedVisibleHeight + view.safeAreaInsets.bottom
    }

    private var expandedSheetHeight: CGFloat {
        switch configuration.expandedTopInsetMode {
        case .safeArea:
            return max(0, view.bounds.height - view.safeAreaInsets.top)
        }
    }

    /// Offset applied to `mainContainerView.bottomAnchor` to create the visible gap above the sheet.
    private func mainBottomOffset(sheetHeight: CGFloat, gapProgress: CGFloat) -> CGFloat {
        -(sheetHeight + configuration.separatorHeight * gapProgress)
    }

    private var minimizedMainBottomOffset: CGFloat {
        mainBottomOffset(sheetHeight: minimizedSheetHeight, gapProgress: 1)
    }

    private func layoutValues(for state: MinimizableSheetState) -> LayoutValues {
        switch state {
        case .hidden:
            return LayoutValues(
                sheetHeight: 0,
                mainBottomOffset: 0,
                dimAlpha: 0,
                mainCornerRadius: 0,
                sheetCornerRadius: configuration.minimizedCornerRadius
            )
        case .minimized:
            return LayoutValues(
                sheetHeight: minimizedSheetHeight,
                mainBottomOffset: minimizedMainBottomOffset,
                dimAlpha: 0,
                mainCornerRadius: configuration.minimizedCornerRadius,
                sheetCornerRadius: configuration.minimizedCornerRadius
            )
        case .expanded:
            return LayoutValues(
                sheetHeight: expandedSheetHeight,
                mainBottomOffset: 0,
                dimAlpha: configuration.expandedDimmingAlpha,
                mainCornerRadius: 0,
                sheetCornerRadius: configuration.expandedCornerRadius
            )
        }
    }

    private func transitionDuration(from oldState: MinimizableSheetState, to newState: MinimizableSheetState) -> TimeInterval {
        let usesLargeTransition = (oldState == .expanded || newState == .expanded)
        return usesLargeTransition ? configuration.largeTransitionDuration : configuration.compactTransitionDuration
    }

    fileprivate func setSheetState(_ newState: MinimizableSheetState, animated: Bool) {
        let values = layoutValues(for: newState)
        let oldState = sheetState
        let duration = transitionDuration(from: oldState, to: newState)
        let stateChange = MinimizableSheetStateChange(fromState: oldState, toState: newState)
        let useHiddenToExpandedSlideAnimation = animated && oldState == .hidden && newState == .expanded

        let applyLayout = {
            self.sheetContentHeightConstraint.constant = self.expandedSheetHeight
            self.sheetHeightConstraint.constant = values.sheetHeight
            self.mainBottomConstraint.constant = values.mainBottomOffset
            self.dimmingView.alpha = values.dimAlpha
            self.mainContainerView.layer.cornerRadius = values.mainCornerRadius
            self.sheetContainerView.layer.cornerRadius = values.sheetCornerRadius
            self.view.layoutIfNeeded()
        }

        let finish = {
            self.sheetState = newState
            self.dimmingView.isUserInteractionEnabled = (newState == .expanded)
            if oldState != newState {
                self.notify(.stateDidChange(stateChange))
            }
        }

        if oldState != newState {
            notify(.stateWillChange(stateChange))
        }

        // Hidden -> expanded must slide in at full height to avoid visible content resizing from zero.
        if useHiddenToExpandedSlideAnimation {
            applyLayout()
            sheetContainerView.transform = CGAffineTransform(translationX: 0, y: values.sheetHeight)
            dimmingView.alpha = 0
            UIView.animate(
                withDuration: duration,
                delay: 0,
                usingSpringWithDamping: 0.94,
                initialSpringVelocity: 0.25,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
            ) {
                self.sheetContainerView.transform = .identity
                self.dimmingView.alpha = values.dimAlpha
            } completion: { _ in
                finish()
            }
        } else if animated {
            UIView.animate(
                withDuration: duration,
                delay: 0,
                usingSpringWithDamping: 0.94,
                initialSpringVelocity: 0.25,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
                animations: applyLayout
            ) { _ in
                finish()
            }
        } else {
            applyLayout()
            finish()
        }
    }

    private func applyInteractiveSheetHeight(_ sheetHeight: CGFloat) {
        let maxHeight = expandedSheetHeight
        let height = max(0, min(maxHeight, sheetHeight))
        sheetContentHeightConstraint.constant = maxHeight
        sheetHeightConstraint.constant = height

        let minimizedHeight = minimizedSheetHeight
        let bridgeTop = min(maxHeight, minimizedHeight + configuration.minimizedTransitionRange)

        if height <= minimizedHeight {
            let progress = minimizedHeight == 0 ? 0 : (height / minimizedHeight)
            mainBottomConstraint.constant = mainBottomOffset(sheetHeight: height, gapProgress: progress)
            dimmingView.alpha = 0
            mainContainerView.layer.cornerRadius = configuration.minimizedCornerRadius * progress
            sheetContainerView.layer.cornerRadius = configuration.minimizedCornerRadius
        } else if height < bridgeTop {
            let range = max(1, bridgeTop - minimizedHeight)
            let progress = (height - minimizedHeight) / range
            mainBottomConstraint.constant = minimizedMainBottomOffset * (1 - progress)
            dimmingView.alpha = configuration.expandedDimmingAlpha * 0.25 * progress
            mainContainerView.layer.cornerRadius = configuration.minimizedCornerRadius * (1 - progress)
            let radiusDelta = configuration.expandedCornerRadius - configuration.minimizedCornerRadius
            sheetContainerView.layer.cornerRadius = configuration.minimizedCornerRadius + radiusDelta * progress
        } else {
            let range = max(1, maxHeight - bridgeTop)
            let progress = (height - bridgeTop) / range
            mainBottomConstraint.constant = 0
            dimmingView.alpha = configuration.expandedDimmingAlpha * (0.25 + progress * 0.75)
            mainContainerView.layer.cornerRadius = 0
            sheetContainerView.layer.cornerRadius = configuration.expandedCornerRadius
        }

        emitInteractiveTransition(currentHeight: height)
        view.layoutIfNeeded()
    }

    private func emitInteractiveTransition(currentHeight: CGFloat) {
        let maxHeight = expandedSheetHeight
        let minimizedHeight = minimizedSheetHeight

        switch panStartState {
        case .expanded:
            let range = max(1, maxHeight - minimizedHeight)
            let progress = (maxHeight - currentHeight) / range
            notify(
                .interactiveTransition(
                    MinimizableSheetInteractiveTransition(
                        fromState: .expanded,
                        toState: .minimized,
                        progress: max(0, min(1, progress)),
                        currentSheetHeight: currentHeight
                    )
                )
            )
        case .minimized:
            if currentHeight >= minimizedHeight {
                let range = max(1, maxHeight - minimizedHeight)
                let progress = (currentHeight - minimizedHeight) / range
                notify(
                    .interactiveTransition(
                        MinimizableSheetInteractiveTransition(
                            fromState: .minimized,
                            toState: .expanded,
                            progress: max(0, min(1, progress)),
                            currentSheetHeight: currentHeight
                        )
                    )
                )
            } else {
                let range = max(1, minimizedHeight)
                let progress = (minimizedHeight - currentHeight) / range
                notify(
                    .interactiveTransition(
                        MinimizableSheetInteractiveTransition(
                            fromState: .minimized,
                            toState: .hidden,
                            progress: max(0, min(1, progress)),
                            currentSheetHeight: currentHeight
                        )
                    )
                )
            }
        case .hidden:
            break
        }
    }

    private func finalizePan(velocityY: CGFloat) {
        let currentHeight = sheetHeightConstraint.constant
        let targetState: MinimizableSheetState

        switch panStartState {
        case .expanded:
            if velocityY > 460 || currentHeight < expandedSheetHeight - 110 {
                targetState = .minimized
            } else {
                targetState = .expanded
            }
        case .minimized:
            if velocityY < -460 {
                targetState = .expanded
            } else if velocityY > 460 {
                targetState = .hidden
            } else if currentHeight > minimizedSheetHeight + 90 {
                targetState = .expanded
            } else if currentHeight < minimizedSheetHeight * 0.55 {
                targetState = .hidden
            } else {
                targetState = .minimized
            }
        case .hidden:
            targetState = .hidden
        }

        setSheetState(targetState, animated: true)
    }

    private func resetPanScrollTracking() {
        panTrackedScrollView = nil
        panHasNestedScrollHandoff = false
        panNestedHandoffTranslationY = 0
        panNestedHandoffStartHeight = 0
    }

    private func scrollViewForPanLocation(_ gesture: UIPanGestureRecognizer) -> UIScrollView? {
        let point = gesture.location(in: sheetContentHostView)
        guard let hitView = sheetContentHostView.hitTest(point, with: nil) else { return nil }
        return hitView.nearestAncestorScrollView()
    }

    private func isScrollViewAtTop(_ scrollView: UIScrollView) -> Bool {
        let topOffset = -scrollView.adjustedContentInset.top
        return scrollView.contentOffset.y <= topOffset + 0.5
    }

    private func lockScrollViewToTop(_ scrollView: UIScrollView) {
        let topOffset = -scrollView.adjustedContentInset.top
        if scrollView.contentOffset.y != topOffset {
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: topOffset)
        }
    }

    @objc
    private func handleDimTap() {
        if sheetState == .expanded {
            setSheetState(.minimized, animated: true)
        }
    }

    @objc
    private func handleSheetPan(_ gesture: UIPanGestureRecognizer) {
        guard sheetState != .hidden else { return }

        let translationY = gesture.translation(in: view).y
        let velocityY = gesture.velocity(in: view).y

        switch gesture.state {
        case .began:
            panStartHeight = sheetHeightConstraint.constant
            panStartState = sheetState
            resetPanScrollTracking()
            if panStartState == .expanded {
                panTrackedScrollView = scrollViewForPanLocation(gesture)
            }
        case .changed:
            if panStartState == .expanded, let trackedScrollView = panTrackedScrollView {
                if !panHasNestedScrollHandoff {
                    if translationY > 0, isScrollViewAtTop(trackedScrollView) {
                        panHasNestedScrollHandoff = true
                        panNestedHandoffTranslationY = translationY
                        panNestedHandoffStartHeight = sheetHeightConstraint.constant
                        lockScrollViewToTop(trackedScrollView)
                    } else {
                        break
                    }
                }

                lockScrollViewToTop(trackedScrollView)
                let effectiveTranslation = max(0, translationY - panNestedHandoffTranslationY)
                let nextHeight = panNestedHandoffStartHeight - effectiveTranslation
                applyInteractiveSheetHeight(max(minimizedSheetHeight, nextHeight))
            } else {
                let nextHeight = panStartHeight - translationY
                let minAllowedHeight: CGFloat = (panStartState == .expanded) ? minimizedSheetHeight : 0
                applyInteractiveSheetHeight(max(minAllowedHeight, nextHeight))
            }
        case .ended, .cancelled, .failed:
            if panStartState == .expanded, panTrackedScrollView != nil, !panHasNestedScrollHandoff {
                resetPanScrollTracking()
                break
            }
            finalizePan(velocityY: velocityY)
            resetPanScrollTracking()
        default:
            break
        }
    }

    fileprivate func addObserver(
        options: MinimizableSheetObservationOptions,
        _ handler: @escaping (MinimizableSheetEvent) -> Void
    ) -> MinimizableSheetObservation {
        let id = UUID()
        observers[id] = ObserverEntry(options: options, handler: handler)
        return MinimizableSheetObservation { [weak self] in
            self?.observers.removeValue(forKey: id)
        }
    }

    private func notify(_ event: MinimizableSheetEvent) {
        for entry in observers.values {
            switch event {
            case .stateWillChange:
                guard entry.options.contains(.stateWillChanges) else { continue }
            case .stateDidChange:
                guard entry.options.contains(.stateChanges) else { continue }
            case .interactiveTransition:
                guard entry.options.contains(.interactiveTransitions) else { continue }
            }
            entry.handler(event)
        }
    }
}

extension MinimizableSheetContainerViewController: UIGestureRecognizerDelegate {

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let isSheetPan = (gestureRecognizer === sheetPanGestureRecognizer)
            || (otherGestureRecognizer === sheetPanGestureRecognizer)
        guard isSheetPan else { return false }

        let candidate: UIGestureRecognizer = (gestureRecognizer === sheetPanGestureRecognizer)
            ? otherGestureRecognizer
            : gestureRecognizer
        guard let scrollView = candidate.view as? UIScrollView else { return false }
        guard scrollView.panGestureRecognizer === candidate else { return false }
        return scrollView.isDescendant(of: sheetViewController.view)
    }
}

extension UIViewController {

    /// Returns the nearest ancestor `MinimizableSheetContainerViewController`, if any.
    public var minimizableSheetContainerViewController: MinimizableSheetContainerViewController? {
        var current: UIViewController? = self
        while let candidate = current {
            if let container = candidate as? MinimizableSheetContainerViewController {
                return container
            }
            current = candidate.parent
        }
        return nil
    }

    /// Returns the sheet controller associated with the nearest minimizable sheet container.
    public var minimizableSheetController: MinimizableSheetController? {
        minimizableSheetContainerViewController?.sheetController
    }

    /// `true` when this controller belongs to the sheet content subtree of a minimizable sheet container.
    ///
    /// This distinguishes sheet content from main content. Returns `false` when not inside a
    /// `MinimizableSheetContainerViewController`, or when inside its main content subtree.
    public var isInsideMinimizableSheetContent: Bool {
        guard let container = minimizableSheetContainerViewController else { return false }

        var current: UIViewController? = self
        while let candidate = current {
            if candidate === container.sheetViewController {
                return true
            }
            if candidate === container.mainViewController || candidate === container {
                return false
            }
            current = candidate.parent
        }
        return false
    }
}

private extension UIView {

    func nearestAncestorScrollView() -> UIScrollView? {
        var current: UIView? = self
        while let view = current {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}

extension UIView {

    /// Returns the nearest sheet controller reachable through the responder chain.
    public var minimizableSheetController: MinimizableSheetController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController.minimizableSheetController
            }
            responder = current.next
        }
        return nil
    }

    /// `true` when this view belongs to the sheet content subtree of a minimizable sheet container.
    public var isInsideMinimizableSheetContent: Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController.isInsideMinimizableSheetContent
            }
            responder = current.next
        }
        return false
    }
}
