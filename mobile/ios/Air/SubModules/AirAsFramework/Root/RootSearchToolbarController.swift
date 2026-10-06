import ContextMenuKit
import SwiftUI
import UIKit
import UIAssets
import UIComponents
import UIHome
import UIUniversalSearch
import UniversalSearchFeature
import WalletContext
import WalletCore

private let rootBottomChromeHeight: CGFloat = 64
private let rootBottomGradientHeight: CGFloat = 84
private let rootActionMenuWidth: CGFloat = 386
private let rootActionMenuMaximumCompactWidth: CGFloat = 424
private let rootActionMenuItemHeight: CGFloat = 124
private let rootActionMenuItemOrder: [SplitHomeActionItem] = [
    .buy,
    .deposit,
    .swap,
    .sell,
    .send,
    .earn,
    .scan,
]
private let rootSearchAnimationDuration: TimeInterval = 0.28

@MainActor
protocol RootSearchToolbarHost: AnyObject {
    var searchNavigationController: WNavigationController? { get }
    var searchRootContentControllers: [UIViewController] { get }
    var searchEditingNavigator: NftsEditingNavigator? { get }
    var showsRootSearchToolbar: Bool { get }
    func searchToolbarWillDetach()
    func setSearchVisible(_ isVisible: Bool, coordinator: (any UIViewControllerTransitionCoordinator)?)
}

extension RootSearchToolbarHost {
    func searchToolbarWillDetach() {}
    func setSearchVisible(_ isVisible: Bool, coordinator: (any UIViewControllerTransitionCoordinator)?) {}
}

/// Owns the same field, result controller and return deadline across root layout changes.
@MainActor
final class RootSearchToolbarController: NSObject {
    private weak var host: (any RootSearchToolbarHost)?
    private weak var sharedMainNavigationController: WNavigationController?
    private var hostConstraints: [NSLayoutConstraint] = []
    private var searchToolbarWidthConstraint: NSLayoutConstraint?
    private var isMigrating = false
    private var traitCollection: UITraitCollection { searchToolbarHostView.traitCollection }

    override init() {
        super.init()
        installSearchToolbar()
        configureBottomBar()
        searchToolbarContainerView.onLayout = { [weak self] in
            guard let self else { return }
            self.updateSearchToolbarGeometry(for: self.searchToolbar.presentation)
        }
    }

    func attach(to host: any RootSearchToolbarHost) {
        guard let navigation = host.searchNavigationController else { return }
        if sharedMainNavigationController !== navigation {
            if !isMigrating { discardSearch() }
            detach()
            self.host = host
            sharedMainNavigationController = navigation
            installBottomBar()
            configureNavigationControllers()
        } else {
            self.host = host
        }
        host.searchRootContentControllers.forEach(applyChromeInsets)
        navigation.viewControllers.forEach(applyChromeInsets)
        updatePresentation()
    }

    func prepareForLayoutChange() {
        isMigrating = true
        if isSearchVisible, searchToolbar.isEditing {
            universalSearchViewController?.restoresKeyboard = true
        }
        searchToolbar.endEditing()
        detach()
    }

    func finishLayoutChange() {
        isMigrating = false
        updatePresentation()
        guard let top = sharedMainNavigationController?.topViewController else { return }
        searchNavigationDidShow(top)
    }

    private func detach() {
        host?.setSearchVisible(false, coordinator: nil)
        host?.searchToolbarWillDetach()
        searchToolbar.setPresentation(searchToolbar.presentation, animated: false)
        sharedMainNavigationController?.onWillShowViewController = nil
        sharedMainNavigationController?.onDidShowViewController = nil
        searchToolbarKeyboardAnimationID = nil
        searchToolbarKeyboardConstraint?.isActive = false
        searchToolbarKeyboardConstraint = nil
        NSLayoutConstraint.deactivate(hostConstraints)
        hostConstraints = []
        bottomGradientView.removeFromSuperview()
        searchToolbarViewportView.removeFromSuperview()
        NotificationCenter.default.removeObserver(self)
        activeSharedBottomToolbarProvider?.onSharedBottomToolbarActionsChange = nil
        activeSharedBottomToolbarProvider?.setSharedBottomToolbarHosted(false)
        activeSharedBottomToolbarProvider = nil
        for inset in contentInsets.values {
            inset.controller?.additionalSafeAreaInsets.bottom -= inset.bottom
        }
        contentInsets = [:]
        sharedMainNavigationController = nil
        host = nil
    }

    @discardableResult
    func pushFromSearch(_ controller: UIViewController) -> Bool {
        guard isSearchVisible, let navigation = sharedMainNavigationController else { return false }
        navigation.pushViewController(controller, animated: true)
        return true
    }

    private let bottomGradientView = RootBottomGradientView()
    private let searchToolbarViewportView = WTouchPassView()
    private let searchToolbarContainerView = RootSearchToolbarContainerView()
    let searchToolbar = UniversalSearchFieldView(configuration: .init(
        placeholder: lang("Search or Ask"),
        showsMicrophone: false
    ))
    private var searchToolbarLeadingConstraint: NSLayoutConstraint?
    private var searchToolbarTrailingConstraint: NSLayoutConstraint?
    private var bottomBarBottomConstraint: NSLayoutConstraint?
    private var searchToolbarKeyboardConstraint: NSLayoutConstraint?
    private var searchToolbarKeyboardAnimationID: UUID?
    private var actionsMenuInteraction: ContextMenuInteraction?
    private(set) var universalSearchViewController: RootSearchViewController?
    private var searchSheetObservation: MinimizableSheetObservation?

    var isSearchVisible: Bool {
        guard let universalSearchViewController else { return false }
        return sharedMainNavigationController?.topViewController === universalSearchViewController
    }
    private weak var activeSharedBottomToolbarProvider: (any SharedBottomToolbarContentProviding)?
    private(set) var isClosingSearch = false
    private struct ContentInset {
        weak var controller: UIViewController?
        var bottom: CGFloat
    }
    private var contentInsets: [ObjectIdentifier: ContentInset] = [:]
    private var searchToolbarHostView: UIView {
        sharedMainNavigationController?.view ?? searchToolbarViewportView.superview ?? searchToolbarContainerView
    }

    private var homeToolbarBottomInset: CGFloat {
        homeToolbarBottomInset(in: searchToolbarHostView)
    }

    private func homeToolbarBottomInset(in hostView: UIView) -> CGFloat {
        hostView.safeAreaInsets.bottom > 0 ? 2 : -16
    }

    func discardSearch() {
        guard !isMigrating, let search = universalSearchViewController else { return }
        search.stop()
        universalSearchViewController = nil
        host?.setSearchVisible(false, coordinator: nil)
        clearSharedSearchField()
        searchSheetObservation?.invalidate()
        searchSheetObservation = nil
        if let navigationController = sharedMainNavigationController {
            navigationController.setViewControllers(
                navigationController.viewControllers.filter { $0 !== search },
                animated: false
            )
        }
        isClosingSearch = false
    }

    private func configureNavigationControllers() {
        sharedMainNavigationController?.onWillShowViewController = { [weak self] viewController in
            guard let self, let sharedMainNavigationController else { return }
            searchNavigationWillShow(viewController, in: sharedMainNavigationController)
            applyChromeInsets(to: viewController)
            updateRootChromeVisibility(
                for: sharedMainNavigationController,
                showing: viewController
            )
        }
        sharedMainNavigationController?.onDidShowViewController = { [weak self] viewController in
            guard let self else { return }
            searchNavigationDidShow(viewController)
            if !isMigrating {
                host?.setSearchVisible(isSearchVisible, coordinator: nil)
            }
        }
    }

    private func updateRootChromeVisibility(
        for navigationController: WNavigationController,
        showing viewController: UIViewController
    ) {
        guard !isMigrating, navigationController === sharedMainNavigationController else {
            return
        }
        host?.setSearchVisible(
            viewController is RootSearchViewController,
            coordinator: navigationController.transitionCoordinator
        )
        let isShowingRoot = navigationController.viewControllers.first === viewController
        if isShowingRoot, installHomeNftSelectionToolbarIfNeeded(in: navigationController) {
            return
        }
        let provider = viewController as? any SharedBottomToolbarContentProviding
        let targetPresentation: UniversalSearchFieldPresentation = viewController is RootSearchViewController
            ? .search
            : sharedBottomToolbarPresentation(isShowingRoot: isShowingRoot, provider: provider)
        searchToolbar.isHidden = false
        updateSharedBottomToolbar(
            provider: provider,
            targetPresentation: targetPresentation,
            in: navigationController,
            coordinator: navigationController.transitionCoordinator
        )
    }

    func updatePresentation() {
        guard let navigationController = sharedMainNavigationController,
              let viewController = navigationController.topViewController else {
            return
        }
        // Presented sheets do not change the navigation stack's toolbar.
        updateRootChromeVisibility(for: navigationController, showing: viewController)
    }

    private func updateSharedBottomToolbar(
        provider: (any SharedBottomToolbarContentProviding)?,
        targetPresentation: UniversalSearchFieldPresentation,
        in navigationController: WNavigationController,
        coordinator: (any UIViewControllerTransitionCoordinator)?
    ) {
        if let provider {
            bindSharedBottomToolbarProvider(provider, coordinator: coordinator)
        }
        let targetActions = provider?.sharedBottomToolbarActions ?? searchToolbar.compactActions

        guard searchToolbar.presentation != targetPresentation || searchToolbar.compactActions != targetActions else {
            updateSearchToolbarGeometry(for: targetPresentation)
            finishBottomChromeVisibility(at: targetPresentation)
            if targetPresentation != .compactToolbar {
                finishSharedBottomToolbarPresentation(
                    provider: provider,
                    presentation: targetPresentation
                )
            }
            return
        }

        if targetPresentation != .homeToolbar {
            actionsMenuInteraction?.detach()
        }
        prepareBottomChromeVisibilityForTransition()
        navigationController.view.layoutIfNeeded()

        guard let coordinator else {
            updateSearchToolbarGeometry(for: targetPresentation)
            searchToolbar.setCompactActions(targetActions)
            searchToolbar.setPresentation(targetPresentation, animated: false)
            navigationController.view.layoutIfNeeded()
            finishBottomChromeVisibility(at: targetPresentation)
            finishSharedBottomToolbarPresentation(
                provider: provider,
                presentation: targetPresentation
            )
            return
        }

        let sourcePresentation = searchToolbar.presentation
        let isPop = coordinator.viewController(forKey: .from).map {
            !navigationController.viewControllers.contains($0)
        } ?? false
        guard let transitionID = searchToolbar.preparePresentationTransition(
            to: targetPresentation,
            compactActions: targetActions,
            navigationOperation: isPop ? .pop : .push
        ) else { return }
        let keyboardAnimationID = targetPresentation == .search
            && !coordinator.isInteractive
            && universalSearchViewController?.restoresKeyboard == true
            && !searchToolbar.isEditing
            ? prepareSearchToolbarKeyboardAnimation()
            : nil
        let accepted = coordinator.animateAlongsideTransition(in: searchToolbarHostView) { [weak self, weak navigationController] _ in
            guard let self, let navigationController,
                  navigationController === sharedMainNavigationController else { return }
            guard searchToolbar.applyPreparedPresentationTransition(transitionID) else { return }
            updateSearchToolbarGeometry(for: targetPresentation)
            if targetPresentation == .search, !coordinator.isInteractive,
               universalSearchViewController?.restoresKeyboard == true {
                _ = searchToolbar.focus()
            }
            bottomGradientView.alpha = targetPresentation == .empty ? 0 : 1
            navigationController.view.layoutIfNeeded()
        } completion: { [weak self, weak navigationController] context in
            if let keyboardAnimationID {
                self?.finishSearchToolbarKeyboardAnimation(keyboardAnimationID)
            }
            guard let self, let navigationController,
                  navigationController === sharedMainNavigationController,
                  searchToolbar.finishPreparedPresentationTransition(transitionID, isCancelled: context.isCancelled) else { return }
            let finalPresentation = context.isCancelled ? sourcePresentation : targetPresentation
            updateSearchToolbarGeometry(for: finalPresentation)
            finishBottomChromeVisibility(at: finalPresentation)
            guard let topViewController = navigationController.topViewController else {
                return
            }
            synchronizeSharedBottomToolbar(
                for: topViewController,
                in: navigationController
            )
        }

        if !accepted, let keyboardAnimationID {
            finishSearchToolbarKeyboardAnimation(keyboardAnimationID)
        }
        if !accepted, searchToolbar.finishPreparedPresentationTransition(transitionID, isCancelled: false) {
            updateSearchToolbarGeometry(for: targetPresentation)
            navigationController.view.layoutIfNeeded()
            finishBottomChromeVisibility(at: targetPresentation)
            finishSharedBottomToolbarPresentation(
                provider: provider,
                presentation: targetPresentation
            )
        }
    }

    private func synchronizeSharedBottomToolbar(
        for viewController: UIViewController,
        in navigationController: WNavigationController
    ) {
        let isShowingRoot = navigationController.viewControllers.first === viewController
        if isShowingRoot, installHomeNftSelectionToolbarIfNeeded(in: navigationController) {
            return
        }
        let provider = viewController as? any SharedBottomToolbarContentProviding
        let targetPresentation: UniversalSearchFieldPresentation = viewController is RootSearchViewController
            ? .search
            : sharedBottomToolbarPresentation(isShowingRoot: isShowingRoot, provider: provider)
        searchToolbar.isHidden = false
        if let provider {
            bindSharedBottomToolbarProvider(provider)
            searchToolbar.setCompactActions(provider.sharedBottomToolbarActions)
        }
        updateSearchToolbarGeometry(for: targetPresentation)
        searchToolbar.setPresentation(targetPresentation, animated: false)
        navigationController.view.layoutIfNeeded()
        finishBottomChromeVisibility(at: targetPresentation)
        finishSharedBottomToolbarPresentation(
            provider: provider,
            presentation: targetPresentation
        )
    }

    private func updateSearchToolbarGeometry(for presentation: UniversalSearchFieldPresentation) {
        let isSearch = presentation == .search
        searchToolbarLeadingConstraint?.constant = isSearch ? 8 : 28
        searchToolbarTrailingConstraint?.constant = isSearch ? -8 : -28
        searchToolbarWidthConstraint?.constant = isSearch ? -16 : -56
        bottomBarBottomConstraint?.constant = isSearch ? -10 : homeToolbarBottomInset
    }

    private func sharedBottomToolbarPresentation(
        isShowingRoot: Bool,
        provider: (any SharedBottomToolbarContentProviding)?
    ) -> UniversalSearchFieldPresentation {
        if isShowingRoot, host?.showsRootSearchToolbar == true {
            .homeToolbar
        } else if provider?.isSharedBottomToolbarEnabled == true {
            .compactToolbar
        } else {
            .empty
        }
    }

    @discardableResult
    private func installHomeNftSelectionToolbarIfNeeded(
        in navigationController: WNavigationController
    ) -> Bool {
        guard let navigator = host?.searchEditingNavigator,
              navigator.state.editingState == .selection else {
            return false
        }
        bottomGradientView.isHidden = false
        searchToolbar.isHidden = true
        navigator.installToolbar(into: navigationController.view)
        return true
    }

    private func bindSharedBottomToolbarProvider(
        _ provider: any SharedBottomToolbarContentProviding,
        coordinator: (any UIViewControllerTransitionCoordinator)? = nil
    ) {
        if let previousProvider = activeSharedBottomToolbarProvider,
           (previousProvider as AnyObject) !== (provider as AnyObject) {
            previousProvider.onSharedBottomToolbarActionsChange = nil
            // The outgoing screen must not show its local controls while the
            // shared controls are still following an interactive transition.
            let deferred = coordinator?.animate(alongsideTransition: nil) { [weak self, weak previousProvider] context in
                guard !context.isCancelled,
                      let previousProvider,
                      (self?.activeSharedBottomToolbarProvider as AnyObject?) !== (previousProvider as AnyObject) else {
                    return
                }
                previousProvider.setSharedBottomToolbarHosted(false)
            } ?? false
            if !deferred {
                previousProvider.setSharedBottomToolbarHosted(false)
            }
        }
        activeSharedBottomToolbarProvider = provider
        provider.setSharedBottomToolbarHosted(true)
        provider.onSharedBottomToolbarActionsChange = { [weak self, weak provider] in
            guard let self, let provider,
                  (activeSharedBottomToolbarProvider as AnyObject?) === (provider as AnyObject),
                  let navigationController = sharedMainNavigationController,
                  let viewController = navigationController.topViewController,
                  viewController === (provider as AnyObject) else {
                return
            }
            applyChromeInsets(to: viewController)
            updateRootChromeVisibility(for: navigationController, showing: viewController)
        }
    }

    private func finishSharedBottomToolbarPresentation(
        provider: (any SharedBottomToolbarContentProviding)?,
        presentation: UniversalSearchFieldPresentation
    ) {
        if provider == nil {
            activeSharedBottomToolbarProvider?.onSharedBottomToolbarActionsChange = nil
            activeSharedBottomToolbarProvider?.setSharedBottomToolbarHosted(false)
            activeSharedBottomToolbarProvider = nil
            searchToolbar.setCompactActions([])
            if presentation == .homeToolbar {
                actionsMenuInteraction?.attach(to: searchToolbar.trailingButtonView)
            } else {
                actionsMenuInteraction?.detach()
            }
        } else {
            actionsMenuInteraction?.detach()
        }
    }

    private func prepareBottomChromeVisibilityForTransition() {
        searchToolbar.isHidden = false
        bottomGradientView.isHidden = false
        bottomGradientView.alpha = searchToolbar.presentation == .empty ? 0 : 1
    }

    private func finishBottomChromeVisibility(
        at presentation: UniversalSearchFieldPresentation
    ) {
        let isVisible = presentation != .empty
        searchToolbar.isHidden = false
        bottomGradientView.alpha = isVisible ? 1 : 0
        bottomGradientView.isHidden = !isVisible
    }

    func applyChromeInsets(to controller: UIViewController) {
        let identifier = ObjectIdentifier(controller)
        let previous = contentInsets[identifier].flatMap { $0.controller === controller ? $0.bottom : nil } ?? 0
        let isRoot = host?.searchRootContentControllers.contains { $0 === controller } == true
        let usesToolbar = (controller as? any SharedBottomToolbarContentProviding)?.isSharedBottomToolbarEnabled == true
        let bottom: CGFloat = isRoot || usesToolbar ? rootBottomChromeHeight : 0
        controller.additionalSafeAreaInsets.bottom += bottom - previous
        contentInsets[identifier] = ContentInset(controller: controller, bottom: bottom)
    }

    func removeChrome(from controller: UIViewController) {
        if let inset = contentInsets.removeValue(forKey: ObjectIdentifier(controller)) {
            controller.additionalSafeAreaInsets.bottom -= inset.bottom
        }
    }

    private func configureBottomBar() {
        searchToolbar.bottomHitAreaExtension = 12
        searchToolbar.actionsAccessibilityLabel = lang("Actions")
        searchToolbar.closeAccessibilityLabel = lang("Close")
        searchToolbar.setPresentation(.homeToolbar, animated: false)
        searchToolbar.onActivate = { [weak self] in
            self?.openSearch()
        }
        searchToolbar.onCloseTap = { [weak self] in
            self?.closeSearch()
        }
        searchToolbar.onEditingChange = { [weak self] isEditing in
            self?.updateToolbarKeyboardFocus(isEditing: isEditing)
        }
        searchToolbar.onTextChange = { [weak self] text in
            guard let self, isSearchVisible, let search = universalSearchViewController else { return }
            search.fieldConfiguration.text = text
            search.session.updateQuery(text)
        }
        searchToolbar.onReturn = { [weak self] _ in
            guard let self else { return }
            if universalSearchViewController?.screen.selectPreselectedItem() != true {
                searchToolbar.endEditing()
            }
        }
        searchToolbar.onToolbarActionTap = { [weak self] id in
            self?.activeSharedBottomToolbarProvider?.performSharedBottomToolbarAction(id: id)
        }

        let interaction = ContextMenuInteraction(
            triggers: [.tap, .longPress],
            presentationMode: .zoomSheetOrPopover,
            longPressDuration: 0.25,
            sourcePortal: ContextMenuSourcePortal(
                mask: .roundedAttachmentRect(cornerRadius: 24, cornerCurve: .continuous)
            ),
            activationViewProvider: { [weak searchToolbar] _ in
                searchToolbar?.trailingButtonPresentationSourceView
            }
        ) { [weak self] _ in
            self?.makeActionsMenuConfiguration()
        }
        interaction.attach(to: searchToolbar.trailingButtonView)
        actionsMenuInteraction = interaction
    }

    private func prepareSearchToolbarKeyboardAnimation() -> UUID {
        let hostView = searchToolbarHostView
        let animationID = UUID()
        searchToolbarKeyboardAnimationID = animationID
        // The live guide can move before UIKit posts the keyboard notification.
        // Pin the starting position before becoming first responder.
        searchToolbarKeyboardConstraint?.constant = (searchToolbarContainerView.layer.presentation()?.frame.maxY
            ?? searchToolbarContainerView.frame.maxY) - hostView.safeAreaLayoutGuide.layoutFrame.maxY
        searchToolbarKeyboardConstraint?.isActive = true
        return animationID
    }

    private func finishSearchToolbarKeyboardAnimation(_ animationID: UUID) {
        guard searchToolbarKeyboardAnimationID == animationID else { return }
        searchToolbarKeyboardAnimationID = nil
        // Keep unfocused Search at the bottom even if another field owns the keyboard.
        UIView.performWithoutAnimation {
            searchToolbarKeyboardConstraint?.constant = 0
            searchToolbarKeyboardConstraint?.isActive = !searchToolbar.isEditing
            searchToolbarHostView.layoutIfNeeded()
        }
    }

    private func updateToolbarKeyboardFocus(isEditing: Bool) {
        let hostView = searchToolbarHostView
        let overlap = isEditing
            ? max(0, hostView.safeAreaLayoutGuide.layoutFrame.maxY - hostView.keyboardLayoutGuide.layoutFrame.minY)
            : 0
        // Responder transfers need not change the keyboard frame or send a notification.
        animateToolbarKeyboard(overlap: overlap, duration: 0.25, options: .curveEaseInOut)
    }

    @objc private func updateToolbarKeyboard(_ notification: Notification) {
        let hostView = searchToolbarHostView
        let overlap: CGFloat
        if !searchToolbar.isEditing || notification.name == UIResponder.keyboardWillHideNotification {
            overlap = 0
        } else {
            guard let window = hostView.window,
                  let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let frameInWindow = window.convert(keyboardFrame, from: window.screen.coordinateSpace)
            let frame = hostView.convert(frameInWindow, from: window)
            let isDocked = frameInWindow.maxY >= window.bounds.maxY
                && frameInWindow.width >= window.bounds.width - 1
                && frame.intersects(hostView.bounds)
            overlap = isDocked
                ? max(0, hostView.bounds.maxY - frame.minY - hostView.safeAreaInsets.bottom)
                : 0
        }
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey]
            as? TimeInterval ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey]
            as? UInt ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        animateToolbarKeyboard(overlap: overlap, duration: duration, options: UIView.AnimationOptions(rawValue: curve << 16))
    }

    private func animateToolbarKeyboard(overlap: CGFloat, duration: TimeInterval, options: UIView.AnimationOptions) {
        let hostView = searchToolbarHostView
        guard let constraint = searchToolbarKeyboardConstraint else { return }
        guard !constraint.isActive || constraint.constant != -overlap else { return }
        let animationID = UUID()
        searchToolbarKeyboardAnimationID = animationID
        if !constraint.isActive {
            // Keep the live guide from consuming the keyboard's animation delta.
            constraint.constant = (searchToolbarContainerView.layer.presentation()?.frame.maxY
                ?? searchToolbarContainerView.frame.maxY) - hostView.safeAreaLayoutGuide.layoutFrame.maxY
            constraint.isActive = true
        }
        hostView.layoutIfNeeded()
        constraint.constant = -overlap
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [options, .beginFromCurrentState, .allowUserInteraction, .overrideInheritedDuration, .overrideInheritedCurve]
        ) {
            hostView.layoutIfNeeded()
        } completion: { [weak self] _ in
            self?.finishSearchToolbarKeyboardAnimation(animationID)
        }
    }

    private func installSearchToolbar() {
        let container = searchToolbarContainerView
        searchToolbar.transitionViewportView = searchToolbarViewportView
        searchToolbarViewportView.clipsToBounds = true
        searchToolbarViewportView.addSubview(container)
        searchToolbar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(searchToolbar)
        let leading = searchToolbar.leadingAnchor.constraint(greaterThanOrEqualTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 28)
        let trailing = searchToolbar.trailingAnchor.constraint(lessThanOrEqualTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -28)
        let width = searchToolbar.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -56)
        width.priority = .defaultHigh
        let bottom = searchToolbar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: homeToolbarBottomInset)
        NSLayoutConstraint.activate([
            leading, trailing, width, bottom,
            searchToolbar.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            searchToolbar.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
            searchToolbar.heightAnchor.constraint(equalToConstant: 48),
        ])
        searchToolbarLeadingConstraint = leading
        searchToolbarTrailingConstraint = trailing
        searchToolbarWidthConstraint = width
        bottomBarBottomConstraint = bottom
    }

    private func makeActionsMenuConfiguration() -> ContextMenuConfiguration {
        guard let account = AccountStore.account else {
            return ContextMenuConfiguration(
                rootPage: ContextMenuPage(items: []),
                backdrop: .none
            )
        }
        let accountContext = AccountContext(accountId: account.id)
        let maximumWidth = traitCollection.horizontalSizeClass == .compact
            ? rootActionMenuMaximumCompactWidth
            : rootActionMenuWidth
        let availableItems = Set(SplitHomeActionItem.availableItems(for: account))
        let items: [ContextMenuItem] = rootActionMenuItemOrder.compactMap { item in
            guard availableItems.contains(item) else {
                return nil
            }
            return actionMenuItem(item, accountContext: accountContext)
        }

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(
                items: items,
                layout: .grid(ContextMenuGridLayout(
                    columns: 3,
                    contentInsets: UIEdgeInsets(top: 48, left: 20, bottom: 20, right: 20),
                    highlightInsets: UIEdgeInsets(top: -7, left: 4, bottom: 15, right: 4),
                    highlightCornerRadius: 24
                ))
            ),
            backdrop: .none,
            style: ContextMenuStyle(
                minWidth: rootActionMenuWidth,
                maxWidth: maximumWidth,
                verticalPlacementBehavior: .screenBottom,
                panelCornerRadius: 54,
                screenInsets: UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
            ),
            sheetNavigationControllerProvider: { menu in
                menu.navigationItem.hidesBackButton = true
                if #available(iOS 26.0, *) {
                    return ActionMenuNavigationController(rootViewController: menu)
                }
                return UINavigationController(rootViewController: menu)
            }
        )
    }

    private func actionMenuItem(
        _ item: SplitHomeActionItem,
        accountContext: AccountContext
    ) -> ContextMenuItem {
        let handsOffSheet: Bool
        if #available(iOS 26.0, *), traitCollection.horizontalSizeClass == .compact {
            handsOffSheet = true
        } else {
            handsOffSheet = false
        }
        return .custom(
            .swiftUI(
                sizing: .fixed(height: rootActionMenuItemHeight),
                interaction: .selectable(dismissesMenu: !handsOffSheet) {
                    if #available(iOS 26.0, *), handsOffSheet,
                       let host = topViewController() as? ActionMenuNavigationController {
                        host.perform(item, accountContext: accountContext)
                    } else {
                        item.perform(accountContext: accountContext)
                    }
                }
            ) { _ in
                ActionMenuItem(item: item)
            }
        )
    }

    func openSearch() {
        guard !isMigrating, !isSearchVisible,
              sharedMainNavigationController?.presentedViewController == nil,
              let navigationController = sharedMainNavigationController,
              navigationController.transitionCoordinator == nil else { return }
        discardSearch()
        var configuration = searchToolbar.configuration
        configuration.text = ""
        configuration.autocomplete = nil
        let search = RootSearchViewController(configuration: configuration)
        search.screen.onClose = { [weak self] in self?.closeSearch() }
        search.session.onSelectRoute = { [weak self] route in
            self?.handleUniversalSearchRoute(route)
        }
        search.session.onAutocompleteChange = { [weak self, weak search] autocomplete in
            guard let self, let search else { return }
            search.fieldConfiguration.autocomplete = autocomplete
            if isSearchVisible, searchToolbar.presentation == .search {
                searchToolbar.configuration = search.fieldConfiguration
            }
        }
        search.onAppear = { [weak self, weak search] in
            guard let self, let search, universalSearchViewController === search else { return }
            searchDidReturn(search)
        }
        universalSearchViewController = search
        actionsMenuInteraction?.detach()
        search.session.start()
        navigationController.withCrossfade(
            duration: rootSearchAnimationDuration,
            keepingAboveTransition: [bottomGradientView, searchToolbarViewportView]
        ) {
            navigationController.pushViewController(search, animated: true)
        }
    }

    func closeSearch() {
        guard let search = universalSearchViewController,
              let navigationController = sharedMainNavigationController else { return }
        guard !isClosingSearch else { return }
        if let coordinator = navigationController.transitionCoordinator {
            isClosingSearch = true
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isClosingSearch = false
                    self?.closeSearch()
                }
            }
            return
        }
        guard navigationController.topViewController === search else {
            discardSearch()
            return
        }
        isClosingSearch = true
        search.stop()
        searchToolbar.endEditing()
        navigationController.withCrossfade(
            duration: rootSearchAnimationDuration,
            keepingAboveTransition: [bottomGradientView, searchToolbarViewportView]
        ) {
            _ = navigationController.popViewController(animated: true)
        }
    }

    private func searchNavigationWillShow(_ viewController: UIViewController, in navigationController: WNavigationController) {
        guard !isMigrating, let search = universalSearchViewController else { return }
        if viewController === search {
            searchToolbar.configuration = search.fieldConfiguration
        } else if navigationController.transitionCoordinator?.viewController(forKey: .from) === search {
            if searchToolbar.isEditing { search.restoresKeyboard = true }
            searchToolbar.endEditing()
        }
    }

    private func searchNavigationDidShow(_ viewController: UIViewController) {
        guard !isMigrating, let search = universalSearchViewController,
              let navigationController = sharedMainNavigationController else { return }
        if viewController !== search { clearSharedSearchField() }
        if !navigationController.viewControllers.contains(where: { $0 === search }) {
            search.stop()
            universalSearchViewController = nil
            searchSheetObservation?.invalidate()
            searchSheetObservation = nil
            isClosingSearch = false
        } else if viewController === search {
            if isSearchCoveredByPresentation {
                expireSearchIfNeeded(search)
            } else {
                searchDidReturn(search)
            }
        } else if search.returnDeadline == nil {
            retainSearchForReturn(search)
        } else {
            expireSearchIfNeeded(search)
        }
    }

    private func clearSharedSearchField() {
        var configuration = searchToolbar.configuration
        configuration.text = ""
        configuration.autocomplete = nil
        searchToolbar.configuration = configuration
    }

    private func searchDidReturn(_ search: RootSearchViewController) {
        guard !isMigrating, isSearchVisible, !isClosingSearch, !isSearchCoveredByPresentation else { return }
        search.expirationTask?.cancel()
        search.expirationTask = nil
        search.returnDeadline = nil
        searchToolbar.configuration = search.fieldConfiguration
        if search.restoresKeyboard { _ = searchToolbar.focus() }
    }

    private func retainSearchForReturn(_ search: RootSearchViewController) {
        guard universalSearchViewController === search, search.returnDeadline == nil else { return }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        search.returnDeadline = deadline
        search.expirationTask = Task { [weak self, weak search] in
            do { try await ContinuousClock().sleep(until: deadline) } catch { return }
            guard let self, let search else { return }
            expireSearchIfNeeded(search)
        }
    }

    private var isSearchCoveredByPresentation: Bool {
        let root = sharedMainNavigationController?.view.window?.rootViewController
        return root?.presentedViewController != nil
            || root?.descendantViewController(of: MinimizableSheetContainerViewController.self)?.sheetController.state == .expanded
    }

    func expireSearchIfNeeded(_ search: RootSearchViewController) {
        guard !isMigrating, universalSearchViewController === search,
              let deadline = search.returnDeadline, ContinuousClock.now >= deadline,
              let navigationController = sharedMainNavigationController else { return }
        let coveredByPresentation = isSearchCoveredByPresentation
        guard !isSearchVisible || coveredByPresentation else { return }
        // UIKit can defer a newly installed navigation stack's appearance until
        // its covering modal goes away. That must not suspend Search's deadline.
        if !coveredByPresentation, let coordinator = navigationController.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { [weak self, weak search] _ in
                Task { @MainActor [weak self, weak search] in
                    guard let self, let search else { return }
                    expireSearchIfNeeded(search)
                }
            }
            return
        }
        discardSearch()
    }

    private func trackSearchPresentation(_ search: RootSearchViewController) {
        if isSearchCoveredByPresentation { retainSearchForReturn(search) }
        if let controller = sharedMainNavigationController?.view.window?.rootViewController?
            .descendantViewController(of: MinimizableSheetContainerViewController.self)?.sheetController {
            searchSheetObservation?.invalidate()
            searchSheetObservation = controller.addObserver(options: .stateChanges) { [weak self, weak search] event in
                guard let self, let search, universalSearchViewController === search,
                      case let .stateDidChange(change) = event else { return }
                if change.toState == .expanded {
                    retainSearchForReturn(search)
                } else if isSearchVisible {
                    searchDidReturn(search)
                }
            }
        }
    }

    private func handleUniversalSearchRoute(_ route: UniversalSearchFeatureRoute) {
        guard isSearchVisible, !isClosingSearch,
              sharedMainNavigationController?.transitionCoordinator == nil,
              let search = universalSearchViewController else { return }
        search.expirationTask?.cancel()
        search.returnDeadline = nil
        search.restoresKeyboard = searchToolbar.isEditing
        searchToolbar.endEditing()
        switch route {
        case .walletAction(let action):
            let context = AccountContext(source: .current)
            switch action {
            case .fund: AppActions.showReceive(accountContext: context, chain: nil)
            case .send: AppActions.showSend(accountContext: context, prefilledValues: .init())
            case .earn: AppActions.showEarn(accountContext: context, tokenSlug: nil)
            case .buyWithCard: AppActions.showBuyWithCard(accountContext: context, chain: nil, push: nil)
            case .sell: AppActions.showSell(accountContext: context, tokenSlug: nil)
            case .scan: AppActions.scanAndHandleQR(accountContext: context)
            case .swap:
                Task {
                    await AppActions.showSwap(accountContext: context, defaultSellingToken: nil,
                                              defaultBuyingToken: nil, defaultSellingAmount: nil, push: nil)
                    if self.universalSearchViewController === search {
                        self.trackSearchPresentation(search)
                    }
                }
            }

        case .settings(let section):
            AppActions.showSettings(section: section)

        case .token(let accountID, let token):
            AppActions.showToken(
                accountSource: .accountId(accountID),
                token: token,
                isInModal: false
            )

        case .collectible(let accountID, let nft):
            AppActions.showNft(
                accountContext: AccountContext(accountId: accountID),
                nft: nft,
                isExpanded: true
            )

        case .collection(let accountID, let collection):
            let filter = NftCollectionFilter.collection(collection)
            AppActions.showAssets(
                accountSource: .accountId(accountID),
                selectedTab: .nftCollectionFilter(filter),
                collectionsFilter: filter
            )

        case .application(let url, let title, let opensExternally):
            if opensExternally {
                UIApplication.shared.open(url)
            } else {
                AppActions.openInBrowser(
                    url,
                    title: title,
                    injectDappConnect: true
                )
            }

        case .wallet(let account):
            Task {
                do {
                    _ = try await AccountStore.activateAccount(accountId: account.id)
                    self.discardSearch()
                    AppActions.showHome(popToRoot: true)
                } catch {
                    AppActions.showError(error: error)
                }
            }

        case .externalWallet(let network, let addressOrDomainByChain):
            AppActions.showTemporaryViewAccount(
                network: network,
                addressOrDomainByChain: addressOrDomainByChain
            )

        case .agent(let query):
            AppActions.showAgent(query: query)

        case .website(let url, let title):
            AppActions.openInBrowser(
                url,
                title: title,
                injectDappConnect: true,
                historyTag: "explore"
            )

        case .google(let query):
            guard let url = UniversalSearchWebIntent.googleSearchURL(for: query) else { return }
            AppActions.openInBrowser(
                url,
                title: nil,
                injectDappConnect: false,
                historyTag: "explore"
            )
        }
        trackSearchPresentation(search)
    }

    private func installBottomBar() {
        bottomGradientView.translatesAutoresizingMaskIntoConstraints = false
        bottomGradientView.toolbarView = searchToolbar
        let toolbarHostView = searchToolbarHostView
        toolbarHostView.addSubview(bottomGradientView)
        searchToolbarViewportView.translatesAutoresizingMaskIntoConstraints = false
        toolbarHostView.addSubview(searchToolbarViewportView)
        // Keep keyboard movement separate from the field's navigation morph.
        searchToolbarContainerView.translatesAutoresizingMaskIntoConstraints = false
        searchToolbarContainerView.shouldAcceptTouchesOutside = true
        let keyboardConstraint = searchToolbarContainerView.bottomAnchor.constraint(
            equalTo: toolbarHostView.safeAreaLayoutGuide.bottomAnchor
        )
        searchToolbarKeyboardConstraint = keyboardConstraint
        let keyboardGuideConstraint = searchToolbarContainerView.bottomAnchor.constraint(
            equalTo: toolbarHostView.keyboardLayoutGuide.topAnchor
        )
        // Only a focused Search follows the guide; other fields must not lift this toolbar.
        keyboardGuideConstraint.priority = UILayoutPriority(999)
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(updateToolbarKeyboard(_:)),
                name: name,
                object: nil
            )
        }
        hostConstraints = [
            // A split secondary can span the window behind the sidebar. Its safe
            // area identifies the actual content panel in both split behaviors.
            searchToolbarViewportView.leadingAnchor.constraint(equalTo: toolbarHostView.safeAreaLayoutGuide.leadingAnchor),
            searchToolbarViewportView.trailingAnchor.constraint(equalTo: toolbarHostView.safeAreaLayoutGuide.trailingAnchor),
            searchToolbarViewportView.topAnchor.constraint(equalTo: toolbarHostView.topAnchor),
            searchToolbarViewportView.bottomAnchor.constraint(equalTo: toolbarHostView.bottomAnchor),
            searchToolbarContainerView.leadingAnchor.constraint(equalTo: searchToolbarViewportView.leadingAnchor),
            searchToolbarContainerView.trailingAnchor.constraint(equalTo: searchToolbarViewportView.trailingAnchor),
            keyboardConstraint,
            keyboardGuideConstraint,
            searchToolbarContainerView.heightAnchor.constraint(equalToConstant: 48),
            bottomGradientView.leadingAnchor.constraint(equalTo: toolbarHostView.safeAreaLayoutGuide.leadingAnchor),
            bottomGradientView.trailingAnchor.constraint(equalTo: toolbarHostView.safeAreaLayoutGuide.trailingAnchor),
            bottomGradientView.bottomAnchor.constraint(equalTo: toolbarHostView.bottomAnchor),
            bottomGradientView.heightAnchor.constraint(equalToConstant: rootBottomGradientHeight),
        ]
        NSLayoutConstraint.activate(hostConstraints)
    }
}

@MainActor
private final class RootBottomGradientView: UIView {
    weak var toolbarView: UIView?
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(gradientLayer)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let toolbarView,
              let hostView = superview,
              toolbarView.isDescendant(of: hostView),
              !toolbarView.isHidden,
              toolbarView.alpha > 0.01,
              toolbarView.isUserInteractionEnabled else { return false }
        // Absorb touches beside and below the toolbar, keeping content above it interactive.
        return super.point(inside: point, with: event)
            && convert(point, to: toolbarView).y >= toolbarView.bounds.minY
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    private func updateColors() {
        let color = UIColor.air.groupedBackground
        gradientLayer.colors = [
            color.withAlphaComponent(0).cgColor,
            color.withAlphaComponent(0.6).cgColor,
        ]
        gradientLayer.locations = [0, 1]
    }
}

@MainActor
private final class RootSearchToolbarContainerView: WTouchPassView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
