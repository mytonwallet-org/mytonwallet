//
//  HomeTabBarController.swift
//  MyTonWallet
//
//  Created by Sina on 3/21/24.
//

import UIKit
import UIBrowser
import UIAgent
import UISettings
import UIComponents
import WalletCore
import WalletContext
import UIKit.UIGestureRecognizerSubclass

private let scaleFactor: CGFloat = 0.85
private final class LazyRootNavigationController: WNavigationController {
    private let rootViewControllerType: UIViewController.Type
    private let makeRootViewController: () -> UIViewController
    private var didInstallRootViewController = false

    init(rootViewControllerType: UIViewController.Type, makeRootViewController: @escaping () -> UIViewController) {
        self.rootViewControllerType = rootViewControllerType
        self.makeRootViewController = makeRootViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ensureRootViewControllerInstalled()
    }

    func ensureRootViewControllerInstalled() {
        guard !didInstallRootViewController else { return }
        didInstallRootViewController = true
        viewControllers = [makeRootViewController()]
    }

    func containsRootViewController<T: UIViewController>(of type: T.Type) -> Bool {
        if let rootViewController = viewControllers.first {
            return rootViewController is T
        }
        return rootViewControllerType == type
    }
}

public class HomeTabBarController: UITabBarController {
    
    public enum Tab: Int {
        case home
        case agent
        case explore
        case settings
    }

    private(set) public var homeVC: HomeVC!
    
    private var tabBarBorder: UIView?
    private var highlightView: UIImageView? { view.subviews.first(where: { $0 is UIImageView }) as? UIImageView }

    public init() {
        self.homeVC = HomeVC()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeUpdated(_:)), name: .updateTheme, object: nil)

        if IOS_26_MODE_ENABLED {
        } else {
            tabBar.layer.borderWidth = 0
            tabBar.clipsToBounds = true
            applyTabBarAppearance()
            let tabBarBorder = UIView()
            self.tabBarBorder = tabBarBorder
            tabBarBorder.translatesAutoresizingMaskIntoConstraints = false
            tabBarBorder.backgroundColor = .air.separator
            tabBar.addSubview(tabBarBorder)
            NSLayoutConstraint.activate([
                tabBarBorder.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
                tabBarBorder.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
                tabBarBorder.topAnchor.constraint(equalTo: tabBar.topAnchor),
                tabBarBorder.heightAnchor.constraint(equalToConstant: 0.33)
            ])
        }
        
        WalletCoreData.add(eventObserver: self)
        
        let homeNav = WNavigationController(rootViewController: homeVC)
        let settingsViewController = LazyRootNavigationController(rootViewControllerType: SettingsVC.self) {
            SettingsVC()
        }
        let browserViewController = LazyRootNavigationController(rootViewControllerType: ExploreTabVC.self) {
            ExploreTabVC()
        }
        let agentViewController = LazyRootNavigationController(rootViewControllerType: AgentVC.self) {
            AgentVC()
        }
        
        homeNav.tabBarItem.image = UIImage(named: "tab_home", in: AirBundle, compatibleWith: nil)
        homeNav.title = lang("Wallet")

        agentViewController.tabBarItem.image = UIImage(named: "tab_agent", in: AirBundle, compatibleWith: nil)
        agentViewController.title = lang("Agent")
        
        browserViewController.tabBarItem.image = UIImage(named: "tab_explore", in: AirBundle, compatibleWith: nil)
        browserViewController.title = lang("Explore")
        
        settingsViewController.tabBarItem.image = UIImage(named: "tab_settings", in: AirBundle, compatibleWith: nil)
        settingsViewController.title = lang("Settings")

        let tabViewControllers: [UIViewController] = [homeNav, agentViewController, browserViewController, settingsViewController]
        self.viewControllers = tabViewControllers

        StartupTrace.markOnce("homeTabBar.viewDidLoad", details: "tabs=\(tabViewControllers.count)")

        addGestureRecognizer()

        if #available(iOS 18.0, *), UIDevice.current.userInterfaceIdiom == .pad {
            traitOverrides.horizontalSizeClass = .compact
        }
        
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

    @objc private func handleThemeUpdated(_ notification: Notification) {
        updateTheme()
    }
    
    private func updateTheme() {
        tabBarBorder?.backgroundColor = .air.separator
        tabBar.tintColor = UIColor.tintColor
        tabBar.unselectedItemTintColor = .air.secondaryLabel
        applyTabBarAppearance()
        tabBar.setNeedsLayout()
    }
    
    public override var selectedViewController: UIViewController? {
        didSet {
            tabChanged(to: selectedIndex)
        }
    }
    
    public override var selectedIndex: Int {
        didSet {
            tabChanged(to: selectedIndex)
        }
    }
    
    func tabChanged(to selectedIndex: Int) {
        tabBarBorder?.isHidden = currentTab == .explore
    }

    public var currentTab: Tab {
        tab(at: selectedIndex)
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
        selectedIndex = tabIndex(for: .home)
        if popToRoot {
            homeVC?.navigationController?.popToRootViewController(animated: true)
        }
        if let rootVC = view.window?.rootViewController, rootVC.presentedViewController != nil {
            rootVC.dismiss(animated: true)
        }
    }

    public func switchToAgent() {
        selectedIndex = tabIndex(for: .agent)
    }
    
    public func switchToExplore() {
        selectedIndex = tabIndex(for: .explore)
    }

    public func switchToSettings(path: [UIViewController]) {
        selectedIndex = tabIndex(for: .settings)
        guard let settingsNavigationController else { return }
        guard let rootViewController = settingsNavigationController.viewControllers.first else { return }
        settingsNavigationController.setViewControllers([rootViewController] + path, animated: false)
    }

    @discardableResult
    public func pushOnSettingsRoot(_ viewController: UIViewController, animated: Bool = true) -> Bool {
        guard let settingsNavigationController else { return false }
        settingsNavigationController.pushViewController(viewController, animated: animated)
        return true
    }

    private func tabIndex(for tab: Tab) -> Int {
        tab.rawValue
    }

    private func tab(at index: Int) -> Tab {
        Tab(rawValue: index) ?? .home
    }

    private func applyTabBarAppearance() {
        guard !IOS_26_MODE_ENABLED else { return }

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
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
    
    func addGestureRecognizer() {
        for (index, view) in tabViews().enumerated() {
            if IOS_26_MODE_ENABLED {
            } else {
                let highlightGesture = UILongPressGestureRecognizer()
                highlightGesture.addTarget(self, action: #selector(onTouch))
                highlightGesture.delegate = self
                highlightGesture.minimumPressDuration = 0
                highlightGesture.allowableMovement = 100
                view.addGestureRecognizer(highlightGesture)
                
                let tapGesture = UITapGestureRecognizer()
                tapGesture.addTarget(self, action: #selector(onSelect))
                tapGesture.delegate = self
                view.addGestureRecognizer(tapGesture)
            }
            
            if let viewControllers, index < viewControllers.count, isSettingsNavigationController(viewControllers[index]) {
                let gesture = UILongPressGestureRecognizer()
                gesture.minimumPressDuration = 0.25
                gesture.addTarget(self, action: #selector(onLongTap))
                gesture.delegate = self
                view.addGestureRecognizer(gesture)
            }
        }
    }
    
    @objc func onLongTap(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            showSwitchWallet(gesture: gesture)
        }
    }
    
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
        if topViewController() is SwitchAccountVC {
            // don't switch to settings in that case
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
    
    // MARK: Account switcher

    private func showSwitchWallet(gesture: UIGestureRecognizer) {
        Haptics.play(.drag)
        let switchAccountVC = SwitchAccountVC(iconColor: currentTab == .settings ? UIColor.tintColor : .air.secondaryLabel)
        switchAccountVC.modalPresentationStyle = .overFullScreen
        switchAccountVC.startingGestureRecognizer = gesture
        (topViewController() ?? self).present(switchAccountVC, animated: false)
    }

    private var settingsNavigationController: UINavigationController? {
        guard let viewControllers else { return nil }
        for viewController in viewControllers {
            guard isSettingsNavigationController(viewController) else { continue }
            if let lazyNavigationController = viewController as? LazyRootNavigationController {
                lazyNavigationController.ensureRootViewControllerInstalled()
            }
            return viewController as? UINavigationController
        }
        return nil
    }

    private func isSettingsNavigationController(_ viewController: UIViewController) -> Bool {
        if let lazyNavigationController = viewController as? LazyRootNavigationController {
            return lazyNavigationController.containsRootViewController(of: SettingsVC.self)
        }
        guard let navigationController = viewController as? UINavigationController else {
            return false
        }
        return navigationController.viewControllers.first is SettingsVC
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
        if self.presentedViewController is SwitchAccountVC {
            return false
        }
        if viewController === selectedViewController  {
            scrollToTop(tabVC: viewController)
        }
        tabBarBorder?.isHidden = currentTab == .explore
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
            AppActions.showToast(message: lang("Update %app_name%", arg1: "MyTonWallet"), duration: nil, tapAction: {
                UIApplication.shared.open(URL(string: "https://get.mytonwallet.io/ios")!)
            })
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
