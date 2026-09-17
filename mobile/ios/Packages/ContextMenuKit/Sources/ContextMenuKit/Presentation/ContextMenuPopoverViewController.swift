import UIKit

@available(iOS 26.0, *)
@MainActor
class ContextMenuPopoverViewController: UIViewController, ContextMenuNavigationViewDelegate, ContextMenuPresentationSession, UIPopoverPresentationControllerDelegate {
    private static let externalSelectionActivationDistance: CGFloat = 4.0
    // UIKit's dismissal completion trails the visual exit. Release the ContextMenuKit session sooner.
    private static let dismissalReadinessDelay: TimeInterval = 0.3

    private let configuration: ContextMenuConfiguration
    private let popoverSourceItem: UIBarButtonItem
    private weak var sourceView: UIView?
    private let sourceUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection
    private let maximumContentHorizontalInsets: UIEdgeInsets
    private var isDismissingMenu = false
    private var didNotifyDismissal = false
    private var dismissalReadinessWorkItem: DispatchWorkItem?
    private var pendingDismissalAction: (() -> Void)?
    private var initialExternalSelectionPoint: CGPoint?
    private var didMoveFromInitialExternalSelectionPoint = false
    private var isReplacingContent = false

    private lazy var customRowContext = ContextMenuCustomRowContext(dismissHandler: { [weak self] in
        self?.dismissMenu()
    })
    private lazy var navigationView = ContextMenuNavigationView(
        rootPage: self.configuration.rootPage,
        style: self.configuration.style,
        sourceUserInterfaceStyle: self.overrideUserInterfaceStyle,
        sourceUserInterfaceLayoutDirection: self.sourceUserInterfaceLayoutDirection,
        customRowContext: self.customRowContext,
        surface: .systemPresentation
    )

    var onDidDismiss: (() -> Void)?

    init(
        configuration: ContextMenuConfiguration,
        sourceView: UIView,
        sourceUserInterfaceStyle: UIUserInterfaceStyle,
        sourceUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection,
        modalPresentationStyle: UIModalPresentationStyle = .popover,
        maximumContentHorizontalInsets: UIEdgeInsets = UIEdgeInsets(
            top: 0,
            left: 16,
            bottom: 0,
            right: 16
        )
    ) {
        self.configuration = configuration
        self.popoverSourceItem = UIBarButtonItem(customView: sourceView)
        self.sourceView = sourceView
        self.sourceUserInterfaceLayoutDirection = sourceUserInterfaceLayoutDirection
        self.maximumContentHorizontalInsets = maximumContentHorizontalInsets

        super.init(nibName: nil, bundle: nil)

        self.overrideUserInterfaceStyle = sourceUserInterfaceStyle
        self.modalPresentationStyle = modalPresentationStyle
        self.navigationView.delegate = self

        self.presentationController?.delegate = self

        if modalPresentationStyle == .popover, let popoverPresentationController {
            popoverPresentationController.delegate = self
            popoverPresentationController.sourceItem = self.popoverSourceItem
        }

        self.updatePreferredContentSize()
        self.registerForSourceTraitChanges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .clear
        self.view.isOpaque = false
        self.navigationView.requestLayout = { [weak self] in
            self?.updatePreferredContentSize()
        }
        self.view.addSubview(self.navigationView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !self.isReplacingContent else { return }

        let contentFrame = self.navigationContentFrame
        self.navigationView.transform = .identity
        self.navigationView.bounds = CGRect(origin: .zero, size: contentFrame.size)
        self.navigationView.center = CGPoint(x: contentFrame.midX, y: contentFrame.midY)
        self.navigationView.transform = self.navigationContentTransform
        self.navigationView.applyPanelLayout(panelSize: contentFrame.size)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if self.isBeingDismissed || self.presentingViewController == nil {
            self.finishDismissalIfNeeded()
        }
    }

    func beginExternalSelection(at pointInWindow: CGPoint) {
        if self.initialExternalSelectionPoint == nil {
            self.initialExternalSelectionPoint = pointInWindow
        }
    }

    func updateExternalSelection(at pointInWindow: CGPoint) {
        if self.initialExternalSelectionPoint == nil {
            self.initialExternalSelectionPoint = pointInWindow
        }
        guard self.isViewLoaded,
              self.view.window != nil,
              let initialExternalSelectionPoint = self.initialExternalSelectionPoint else {
            return
        }

        if !self.didMoveFromInitialExternalSelectionPoint {
            let distance = abs(pointInWindow.y - initialExternalSelectionPoint.y)
            if distance > Self.externalSelectionActivationDistance {
                self.didMoveFromInitialExternalSelectionPoint = true
                self.navigationView.beginExternalSelection(at: pointInWindow)
            }
        } else {
            self.navigationView.updateExternalSelection(at: pointInWindow)
        }
    }

    func endExternalSelection(performAction: Bool) {
        defer {
            self.initialExternalSelectionPoint = nil
            self.didMoveFromInitialExternalSelectionPoint = false
        }
        guard self.didMoveFromInitialExternalSelectionPoint else {
            return
        }
        self.navigationView.endExternalSelection(performAction: performAction)
    }

    func navigationView(_ navigationView: ContextMenuNavigationView, didActivate action: ContextMenuActivation) {
        guard !self.isDismissingMenu, !self.isReplacingContent else { return }
        if action.dismissesMenu {
            self.dismissMenu(action: action.handler)
        } else {
            action.handler?()
        }
    }

    func adaptivePresentationStyle(
        for controller: UIPresentationController
    ) -> UIModalPresentationStyle {
        .none
    }

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        self.finishDismissalIfNeeded()
    }

    func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
        guard self.beginDismissal(action: nil) else {
            return
        }
        guard let transitionCoordinator = presentationController.presentingViewController.transitionCoordinator,
              transitionCoordinator.isInteractive else {
            self.scheduleDismissalReadiness()
            return
        }
        transitionCoordinator.notifyWhenInteractionChanges { [weak self] context in
            if context.isCancelled {
                self?.cancelDismissalIfNeeded()
            } else {
                self?.scheduleDismissalReadiness()
            }
        }
    }

    private func updatePreferredContentSize() {
        guard !self.isReplacingContent else { return }
        let preferredSize = self.navigationView.preferredPanelSize(
            constrainedTo: self.maximumContentSize()
        )
        guard preferredSize != self.preferredContentSize else {
            return
        }
        self.preferredContentSize = preferredSize
        self.navigationController?.preferredContentSize = preferredSize
        self.sheetPresentationController?.invalidateDetents()
        self.viewIfLoaded?.setNeedsLayout()
    }

    var navigationContentFrame: CGRect {
        self.view.bounds
    }

    var navigationContentTransform: CGAffineTransform {
        .identity
    }

    func finishMenuForContentReplacement() {
        self.isReplacingContent = true
        self.navigationView.clearSelections()
        self.view.isUserInteractionEnabled = false
        self.view.accessibilityElementsHidden = true
        self.finishDismissalIfNeeded()
    }

    private func maximumContentSize() -> CGSize {
        let windowBounds = self.sourceView?.window?.bounds ?? UIScreen.main.bounds
        let safeAreaInsets = self.sourceView?.window?.safeAreaInsets ?? .zero
        let availableWidth = max(
            1.0,
            windowBounds.width
                - safeAreaInsets.left
                - safeAreaInsets.right
                - self.maximumContentHorizontalInsets.left
                - self.maximumContentHorizontalInsets.right
        )
        let availableHeight = max(
            1.0,
            windowBounds.height - safeAreaInsets.top - safeAreaInsets.bottom
        )
        return CGSize(
            width: min(self.configuration.style.maxWidth, availableWidth),
            height: max(120.0, availableHeight * self.configuration.style.maximumHeightRatio)
        )
    }

    private func dismissMenu(action: (() -> Void)? = nil) {
        guard self.beginDismissal(action: action) else {
            return
        }

        self.dismiss(animated: true) { [weak self] in
            self?.finishDismissalIfNeeded()
        }
        self.scheduleDismissalReadiness()
    }

    private func beginDismissal(action: (() -> Void)?) -> Bool {
        guard !self.isDismissingMenu else {
            return false
        }
        self.isDismissingMenu = true
        self.pendingDismissalAction = action
        self.initialExternalSelectionPoint = nil
        self.didMoveFromInitialExternalSelectionPoint = false
        self.navigationView.clearSelections()
        self.view.isUserInteractionEnabled = false
        return true
    }

    private func scheduleDismissalReadiness() {
        guard !self.didNotifyDismissal, self.dismissalReadinessWorkItem == nil else {
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishDismissalIfNeeded()
        }
        self.dismissalReadinessWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.dismissalReadinessDelay,
            execute: workItem
        )
    }

    private func cancelDismissalIfNeeded() {
        guard !self.didNotifyDismissal else {
            return
        }
        self.dismissalReadinessWorkItem?.cancel()
        self.dismissalReadinessWorkItem = nil
        self.pendingDismissalAction = nil
        self.isDismissingMenu = false
        self.view.isUserInteractionEnabled = true
    }

    private func finishDismissalIfNeeded() {
        guard !self.didNotifyDismissal else {
            return
        }
        self.dismissalReadinessWorkItem?.cancel()
        self.dismissalReadinessWorkItem = nil
        self.didNotifyDismissal = true
        let onDidDismiss = self.onDidDismiss
        self.onDidDismiss = nil
        onDidDismiss?()
        self.performPendingDismissalActionIfNeeded()
    }

    private func performPendingDismissalActionIfNeeded() {
        let action = self.pendingDismissalAction
        self.pendingDismissalAction = nil
        action?()
    }

    private func registerForSourceTraitChanges() {
        guard let sourceView else {
            return
        }
        sourceView.registerForTraitChanges(
            [UITraitUserInterfaceStyle.self],
            target: self,
            action: #selector(self.handleSourceTraitChange(_:previousTraitCollection:))
        )
    }

    @objc private func handleSourceTraitChange(_ sourceView: UIView, previousTraitCollection: UITraitCollection) {
        guard previousTraitCollection.userInterfaceStyle != sourceView.traitCollection.userInterfaceStyle else {
            return
        }
        let userInterfaceStyle = ContextMenuVisuals.resolvedUserInterfaceStyle(for: sourceView.traitCollection)
        self.overrideUserInterfaceStyle = userInterfaceStyle
        self.navigationView.updateUserInterfaceStyle(userInterfaceStyle)
    }
}
