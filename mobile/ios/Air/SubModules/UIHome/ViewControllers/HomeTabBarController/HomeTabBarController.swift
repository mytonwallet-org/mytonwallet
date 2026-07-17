//
//  HomeTabBarController.swift
//  MyTonWallet
//
//  Created by Sina on 3/21/24.
//

import UIKit
import UIComponents
import ContextMenuKit
import WalletCore
import WalletContext
import UIKit.UIGestureRecognizerSubclass

private let scaleFactor: CGFloat = 0.85

public class HomeTabBarController: UITabBarController {

    private(set) public var homeVC: HomeVC!

    private var navControllersByTabId: [AppTabId: WNavigationController] = [:]
    private let makeNavController: @MainActor (AppTabId) -> WNavigationController?
    private let tabLabelProvider: @MainActor (AppTabId) -> String?

    private var highlightView: UIImageView? { view.subviews.first(where: { $0 is UIImageView }) as? UIImageView }
    private var settingsTabContextMenuInteraction: ContextMenuInteraction?
    private var isSwitchAccountMenuPresented = false
    private var gestureRecognizersInstalledForTabIds: Set<AppTabId> = []

    public init(
        navControllerFactory: @escaping @MainActor (AppTabId) -> WNavigationController?,
        tabLabelProvider: @escaping @MainActor (AppTabId) -> String?
    ) {
        self.makeNavController = navControllerFactory
        self.tabLabelProvider = tabLabelProvider
        let walletNC = navControllerFactory(.wallet) ?? WNavigationController(rootViewController: HomeVC())
        self.homeVC = walletNC.viewControllers.first as? HomeVC ?? HomeVC()
        self.navControllersByTabId = [.wallet: walletNC]
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeUpdated(_:)), name: .updateTheme, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageDidChange(_:)), name: .languageDidChange, object: nil)

        if !IOS_26_MODE_ENABLED {
            applyTabBarAppearance()
        }

        WalletCoreData.add(eventObserver: self)

        StartupTrace.markOnce("homeTabBar.viewDidLoad", details: "pending applyTabConfiguration")

        updateTheme()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Make window background black. It was groupedBackground until home appearance!
        UIApplication.shared.delegate?.window??.backgroundColor = .black

        if let config = ConfigStore.shared.config {
            handleConfig(config)
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateTheme()
    }

    public func applyTabConfiguration(_ orderedIds: [AppTabId]) {
        let currentId = currentTabId

        buildNavControllers(for: orderedIds)

        let removedIds = Set(navControllersByTabId.keys).subtracting(orderedIds)
        for id in removedIds {
            navControllersByTabId.removeValue(forKey: id)
            gestureRecognizersInstalledForTabIds.remove(id)
        }

        rebuildViewControllers(orderedIds: orderedIds)

        if orderedIds.contains(currentId), let idx = navControllerIndex(of: currentId) {
            selectedIndex = idx
        } else {
            selectedIndex = navControllerIndex(of: .wallet) ?? 0
        }
    }

    private func buildNavControllers(for ids: [AppTabId]) {
        for id in ids where navControllersByTabId[id] == nil {
            guard let nc = makeNavController(id) else { continue }
            if id == .wallet, let newHomeVC = nc.viewControllers.first as? HomeVC {
                self.homeVC = newHomeVC
            }
            navControllersByTabId[id] = nc
        }
    }

    private func rebuildViewControllers(orderedIds: [AppTabId]) {
        let vcs: [UIViewController] = orderedIds.compactMap { navControllersByTabId[$0] }
        self.viewControllers = vcs
        addGestureRecognizers(orderedIds: orderedIds)
    }

    public var currentTabId: AppTabId {
        tabId(at: selectedIndex)
    }

    public func takeNavigationStack(for id: AppTabId, keepingRoot: Bool) -> [UIViewController]? {
        guard let navigationController = navControllersByTabId[id] else { return nil }
        if navigationController.viewControllers.isEmpty,
           currentTabId == id,
           let lazyNC = navigationController as? AppTabLazyNavigationController {
            lazyNC.ensureRootViewControllerInstalled()
        }
        let stack = navigationController.viewControllers
        guard !stack.isEmpty else { return nil }
        if keepingRoot, let rootViewController = stack.first {
            navigationController.setViewControllers([rootViewController], animated: false)
        } else {
            navigationController.setViewControllers([Self.makeNavigationStackPlaceholder()], animated: false)
        }
        return stack
    }

    public func setNavigationStack(_ stack: [UIViewController], for id: AppTabId) {
        guard !stack.isEmpty, let navigationController = navControllersByTabId[id] else { return }
        if id == .wallet, let newHomeVC = stack.first as? HomeVC {
            self.homeVC = newHomeVC
        }
        if let lazyNC = navigationController as? AppTabLazyNavigationController {
            lazyNC.setPreservedViewControllers(stack)
        } else {
            navigationController.setViewControllers(stack, animated: false)
        }
    }

    public func selectTab(_ id: AppTabId, popToRoot: Bool = false) {
        guard let index = navControllerIndex(of: id) else { return }
        selectedIndex = index
        if popToRoot {
            navControllersByTabId[id]?.popToRootViewController(animated: true)
        }
    }

    public func scrollToTop(tabVC: UIViewController) {
        if let navController = tabVC as? UINavigationController {
            _ = navController.tabItemTapped()
        } else if let viewController = tabVC as? WViewController {
            viewController.scrollToTop(animated: true)
        } else {
            topWViewController()?.scrollToTop(animated: true)
        }
    }

    public func switchToHome(popToRoot: Bool) {
        selectTab(.wallet)
        if popToRoot {
            homeVC?.navigationController?.popToRootViewController(animated: true)
        }
        if let rootVC = view.window?.rootViewController, rootVC.presentedViewController != nil {
            rootVC.dismiss(animated: true)
        }
    }

    public func switchToAgent() {
        selectTab(.agent)
    }

    public func switchToExplore() {
        selectTab(.explore)
    }

    public func switchToSettings(path: [UIViewController]) {
        selectTab(.settings)
        guard let settingsNC = settingsNavigationController else { return }
        guard let rootViewController = settingsNC.viewControllers.first else { return }
        settingsNC.setViewControllers([rootViewController] + path, animated: false)
    }

    @discardableResult
    public func pushOnSettingsRoot(_ viewController: UIViewController, animated: Bool = true) -> Bool {
        guard let settingsNC = settingsNavigationController else { return false }
        settingsNC.pushViewController(viewController, animated: animated)
        return true
    }

    public func debugOnly_resetAgentRoot() {
        guard let agentNC = navControllersByTabId[.agent] as? AppTabLazyNavigationController else { return }
        agentNC.resetRootViewController()
    }

    private func tabId(at index: Int) -> AppTabId {
        guard let vcs = viewControllers, vcs.indices.contains(index) else { return .wallet }
        let vc = vcs[index]
        return navControllersByTabId.first(where: { $0.value === vc })?.key ?? .wallet
    }

    private func navControllerIndex(of id: AppTabId) -> Int? {
        guard let nc = navControllersByTabId[id], let vcs = viewControllers else { return nil }
        return vcs.firstIndex(where: { $0 === nc })
    }

    private static func makeNavigationStackPlaceholder() -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .black
        return viewController
    }

    private var settingsNavigationController: WNavigationController? {
        guard let nc = navControllersByTabId[.settings] else { return nil }
        if let lazyNC = nc as? AppTabLazyNavigationController {
            lazyNC.ensureRootViewControllerInstalled()
        }
        return nc
    }

    @objc private func handleThemeUpdated(_ notification: Notification) {
        updateTheme()
    }

    @objc private func handleLanguageDidChange(_ notification: Notification) {
        refreshTabBarItemTitles()
    }

    private func refreshTabBarItemTitles() {
        for (id, nc) in navControllersByTabId {
            if let title = tabLabelProvider(id) {
                nc.tabBarItem.title = title
            }
        }
    }

    private func updateTheme() {
        tabBar.tintColor = UIColor.tintColor
        tabBar.unselectedItemTintColor = .air.secondaryLabel
        applyTabBarAppearance()
        tabBar.setNeedsLayout()
    }

    private func applyTabBarAppearance() {
        guard !IOS_26_MODE_ENABLED else { return }

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        applyTabBarItemAppearance(appearance.stackedLayoutAppearance)
        applyTabBarItemAppearance(appearance.inlineLayoutAppearance)
        applyTabBarItemAppearance(appearance.compactInlineLayoutAppearance)

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    private func applyTabBarItemAppearance(_ itemAppearance: UITabBarItemAppearance) {
        itemAppearance.normal.iconColor = .air.secondaryLabel
        itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.air.secondaryLabel]
        itemAppearance.selected.iconColor = UIColor.tintColor
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.tintColor]
    }

    private func addGestureRecognizers(orderedIds: [AppTabId]) {
        for (index, view) in tabViews().enumerated() {
            guard orderedIds.indices.contains(index) else { continue }
            let tabId = orderedIds[index]
            guard !gestureRecognizersInstalledForTabIds.contains(tabId) else { continue }
            gestureRecognizersInstalledForTabIds.insert(tabId)
            let isSettingsTab = tabId == .settings

            if !IOS_26_MODE_ENABLED {
                if !isSettingsTab {
                    let highlightGesture = UILongPressGestureRecognizer()
                    highlightGesture.addTarget(self, action: #selector(onTouch))
                    highlightGesture.delegate = self
                    highlightGesture.minimumPressDuration = 0
                    highlightGesture.allowableMovement = 100
                    view.addGestureRecognizer(highlightGesture)
                }

                let tapGesture = UITapGestureRecognizer()
                tapGesture.addTarget(self, action: #selector(onSelect))
                tapGesture.delegate = self
                view.addGestureRecognizer(tapGesture)
            }

            if isSettingsTab {
                let interaction = ContextMenuInteraction(
                    triggers: [.longPress],
                    onWillPresent: { [weak self, weak view] in
                        self?.isSwitchAccountMenuPresented = true
                        if let view {
                            self?.cancelTabSelectionInteraction(on: view)
                        }
                        self?.tabBar.isUserInteractionEnabled = false
                    },
                    onDidDismiss: { [weak self] in
                        self?.isSwitchAccountMenuPresented = false
                        self?.tabBar.isUserInteractionEnabled = true
                    },
                    configurationProvider: { _ in
                        return SwitchAccountMenu.makeConfiguration()
                    }
                )
                interaction.attach(to: view)
                settingsTabContextMenuInteraction = interaction
            }

#if DEBUG
            if tabId == .explore {
                let gesture = UILongPressGestureRecognizer()
                gesture.minimumPressDuration = 0.4
                gesture.addTarget(self, action: #selector(onExploreLongTap))
                gesture.delegate = self
                view.addGestureRecognizer(gesture)
            }
#endif
        }
    }

#if DEBUG
    @objc private func onExploreLongTap(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            AppActions.showDebugView()
        }
    }
#endif

    @objc func onTouch(_ gesture: UIGestureRecognizer) {
        guard !UIAccessibility.buttonShapesEnabled else { return }
        if gesture.state == .began {
            if let view = gesture.view {
                guard view.center.x > 280 else { return }
                if self.highlightView == nil {
                    let image = view.asImage()
                    let snapshot = UIImageView(image: image)
                    snapshot.frame = view.bounds
                    for subview in view.subviews {
                        subview.alpha = 0
                    }
                    snapshot.tag = 1
                    view.addSubview(snapshot)
                    UIView.animate(withDuration: 0.15, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) {
                        snapshot.transform = .identity.scaledBy(x: scaleFactor, y: scaleFactor)
                    }
                } else if let snapshot = self.highlightView, snapshot.superview === view {
                    UIView.animate(withDuration: 0.15, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) {
                        snapshot.transform = .identity.scaledBy(x: scaleFactor, y: scaleFactor)
                    }
                }
            }
        } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            guard let view = gesture.view else { return }
            for snapshot in view.subviews where snapshot is UIImageView && snapshot.tag == 1 {
                UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) {
                    snapshot.transform = .identity
                } completion: { ok in
                    if snapshot.transform == .identity {
                        snapshot.removeFromSuperview()
                    }
                    for subview in view.subviews {
                        subview.alpha = 1
                    }
                }
            }
        }
    }

    @objc func onSelect(_ gesture: UIGestureRecognizer) {
        if self.isSwitchAccountMenuPresented {
            return
        }
        let tabViews = self.tabViews()
        if let view = gesture.view, let idx = tabViews.firstIndex(where: { $0 === view }), idx < viewControllers?.count ?? 0, let vc = viewControllers?[idx] {
            if tabBarController(self, shouldSelect: vc) {
                selectedIndex = idx
                for snapshot in view.subviews where snapshot.tag == 1 {
                    if let snapshot = snapshot as? UIImageView, let image = snapshot.image {
                        snapshot.image = image.withRenderingMode(.alwaysTemplate)
                        snapshot.tintColor = UIColor.tintColor
                    }
                }
            }
        }
    }

    private func tabViews() -> [UIView] {
        guard let tabBarItems = tabBar.items else { return [] }
        return tabBarItems.compactMap { item in
            item.value(forKey: "view") as? UIView
        }
    }

    private func cancelTabSelectionInteraction(on view: UIView) {
        self.resetTabHighlight(on: view)
        let wasViewInteractionEnabled = view.isUserInteractionEnabled
        view.isUserInteractionEnabled = false
        view.isUserInteractionEnabled = wasViewInteractionEnabled
        self.cancelControlTracking(in: view)
        for recognizer in view.gestureRecognizers ?? [] where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
    }

    private func cancelControlTracking(in view: UIView) {
        if let control = view as? UIControl {
            let wasEnabled = control.isEnabled
            control.isHighlighted = false
            control.isEnabled = false
            control.isEnabled = wasEnabled
        }
        for subview in view.subviews {
            self.cancelControlTracking(in: subview)
        }
    }

    private func resetTabHighlight(on view: UIView) {
        for snapshot in view.subviews where snapshot.tag == 1 {
            snapshot.removeFromSuperview()
        }
        for subview in view.subviews {
            subview.alpha = 1
        }
    }
}

extension HomeTabBarController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

extension HomeTabBarController: UITabBarControllerDelegate {

    public func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if self.isSwitchAccountMenuPresented {
            return false
        }
        if viewController === selectedViewController {
            scrollToTop(tabVC: viewController)
        }
        return true
    }
}

extension HomeTabBarController: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .configChanged:
            if let config = ConfigStore.shared.config {
                handleConfig(config)
            }
        default:
            break
        }
    }

    private func handleConfig(_ config: ApiUpdate.UpdateConfig) {
        if config.isAppUpdateRequired == true {
            AppActions.showToast(message: lang("Update %app_name%", arg1: APP_NAME), duration: nil) {
                UIApplication.shared.open(URL(string: APP_INSTALL_URL)!)
            }
        }
    }
}

fileprivate extension UIView {
    func asImage() -> UIImage {
        let origAlpha = alpha
        let origIsHidden = isHidden
        alpha = 1
        isHidden = false
        let img = UIGraphicsImageRenderer(bounds: bounds).image { rendererContext in
            layer.render(in: rendererContext.cgContext)
            // FIXME: hack to prevent color changing slightly on unhighlight
            layer.render(in: rendererContext.cgContext)
        }
        alpha = origAlpha
        isHidden = origIsHidden
        return img
    }
}
