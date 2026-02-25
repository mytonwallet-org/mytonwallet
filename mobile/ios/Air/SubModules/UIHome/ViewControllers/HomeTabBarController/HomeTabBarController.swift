//
//  HomeTabBarController.swift
//  MyTonWallet
//
//  Created by Sina on 3/21/24.
//

import UIKit
import UIBrowser
import UISettings
import UIComponents
import WalletCore
import WalletContext
import UIKit.UIGestureRecognizerSubclass

private let scaleFactor: CGFloat = 0.85


public class HomeTabBarController: UITabBarController, WThemedView {
    
    public enum Tab: Int {
        case home
        case explore
        case settings
    }

    private(set) public var homeVC: HomeVC!
    
    private var forwardedGestureRecognizer: ForwardedGestureRecognizer!
    private var blurView: WBlurView!
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
        
        view.layer.cornerRadius = 10.667
        view.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.layer.masksToBounds = true
        
        if IOS_26_MODE_ENABLED {
        } else {
            tabBar.layer.borderWidth = 0
            tabBar.clipsToBounds = true
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            let tabBarBorder = UIView()
            self.tabBarBorder = tabBarBorder
            tabBarBorder.translatesAutoresizingMaskIntoConstraints = false
            tabBarBorder.backgroundColor = WTheme.separator
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
        let settingsViewController = WNavigationController(rootViewController: SettingsVC())
        let browserViewController = WNavigationController(rootViewController: ExploreTabVC())
        
        homeNav.tabBarItem.image = UIImage(named: "tab_home", in: AirBundle, compatibleWith: nil)
        homeNav.title = lang("Wallet")
        
        browserViewController.tabBarItem.image = UIImage(named: "tab_browser", in: AirBundle, compatibleWith: nil)
        browserViewController.title = lang("Explore")
        
        settingsViewController.tabBarItem.image = UIImage(named: "tab_settings", in: AirBundle, compatibleWith: nil)
        settingsViewController.title = lang("Settings")

        // Set view controllers for the tab bar controller
        self.viewControllers = [
            homeNav,
            browserViewController,
            settingsViewController,
        ]
        
        addBlurEffectBackground()

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
    
    public func updateTheme() {
        tabBarBorder?.backgroundColor = WTheme.separator
        tabBar.tintColor = WTheme.tint
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
        tabBarBorder?.isHidden = selectedIndex == Tab.explore.rawValue
    }

    public var currentTab: Tab {
        Tab(rawValue: selectedIndex) ?? .home
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
        selectedIndex = Tab.home.rawValue
        if popToRoot {
            homeVC?.navigationController?.popToRootViewController(animated: true)
        }
        if let rootVC = view.window?.rootViewController, rootVC.presentedViewController != nil {
            rootVC.dismiss(animated: true)
        }
    }
    
    public func switchToExplore() {
        selectedIndex = Tab.explore.rawValue
    }

    private func addBlurEffectBackground() {
        blurView = WBlurView()
        tabBar.insertSubview(blurView, at: 0)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: tabBar.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor)
        ])
        blurView.isHidden = true
        blurView.alpha = 0
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
            
            if let viewControllers, index <= viewControllers.count, let nc = viewControllers[index] as? WNavigationController, nc.viewControllers.first is SettingsVC {
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
                        snapshot.tintColor = WTheme.tint
                    }
                }
                tabBarController(self, didSelect: vc)
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
    
//    private var switcherPresented: Bool = false {
//        didSet {
//            UIView.animate(withDuration: 0.5) {
//                self.setNeedsUpdateOfHomeIndicatorAutoHidden()
//            }
//        }
//    }
//    
//    public override var prefersStatusBarHidden: Bool {
//        switcherPresented
//    }
//    
//    public override var childForStatusBarHidden: UIViewController? {
//        if presentedViewController is SwitchAccountVC && switcherPresented {
//            return nil
//        }
//        return super.childForStatusBarHidden
//    }
    
    private func showSwitchWallet(gesture: UIGestureRecognizer?) {
        
        Haptics.play(.drag)
        let switchAccountVC = SwitchAccountVC(iconColor: currentTab == .settings ? WTheme.tint : WTheme.secondaryLabel)
        switchAccountVC.modalPresentationStyle = .overFullScreen
        switchAccountVC.startingGestureRecognizer = gesture ?? forwardedGestureRecognizer
//        switchAccountVC.dismissCallback = {
//            self.switcherPresented = false
//            
//        }
        (topViewController() ?? self).present(switchAccountVC, animated: false)
//        switcherPresented = true
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
        tabBarBorder?.isHidden = selectedIndex == Tab.explore.rawValue
        return true
    }
    
    public func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        blurView.isHidden = true
        blurView.alpha = 0
    }
}


final class ForwardedGestureRecognizer: UILongPressGestureRecognizer {
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .began
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .changed
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .ended
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .ended
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
