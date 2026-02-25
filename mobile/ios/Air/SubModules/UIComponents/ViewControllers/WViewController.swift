//
//  WViewController.swift
//  UIComponents
//
//  Created by Sina on 3/16/24.
//

import SwiftUI
import UIKit
import WalletCore
import WalletContext

private let log = Log("WViewController")


open class WViewController: UIViewController, WThemedView {

    open var navigationBar: WNavigationBar? = nil
    open var customNavigationBarBackground: UIView? = nil
    
    open var bottomButton: WButton? = nil
    open var bottomButtonConstraint: NSLayoutConstraint? = nil
    
    public var bottomBarBlurView: WBlurView?
    private var bottomBarBlurConstraint: NSLayoutConstraint?
    
    open var navigationBarAnchor: NSLayoutYAxisAnchor {
        if let navigationBar {
            navigationBar.bottomAnchor
        } else {
            view.safeAreaLayoutGuide.topAnchor
        }
    }
    
    open var navigationBarHeight: CGFloat {
        if let navigationBar {
            navigationBar.navHeight
        } else {
            0
        }
    }
    
    open var navigationBarProgressiveBlurMinY: CGFloat = 0
    open var navigationBarProgressiveBlurDelta: CGFloat = 16

    open var hideNavigationBar: Bool {
        navigationBar != nil
    }

    open var hideBottomBar: Bool {
        true
    }

    open var maxContentWidth: CGFloat? {
        nil
    }

    private var appliedHorizontalSafeAreaInsetForMaxContentWidth: CGFloat = 0

    // set a view with background as UIViewController view, to do the rest, programmatically, inside the subclasses.
    open override func loadView() {
        let view = UIView()
        view.backgroundColor = WTheme.background
        self.view = view
    }
    
    open func updateTheme() {
    }
    open func scrollToTop(animated: Bool) {
    }
    
    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Global navigation stuff
    
    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // This is a very temporary solution until the global navigation is implemented
        // For now this can be used to testing whether something has been changed in UI hierarchy
        // No distingush between "global" and "embedded" controllers are implemented so far
        // to enable call registerForOtherViewControllerAppearNotifications()
        let userInfo: [String: Any] = [notificationViewControllerKey: self ]
        NotificationCenter.default.post(name: wViewControllerDidAppearNtf, object: self, userInfo: userInfo)
    }
    
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateMaxContentWidthIfNeeded()
    }

    private var observer: NSObjectProtocol?
    private let notificationViewControllerKey = "viewController"
    private let wViewControllerDidAppearNtf = Notification.Name("WViewControllerDidAppear")
    
    public func registerForOtherViewControllerAppearNotifications() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: wViewControllerDidAppearNtf, object: nil, queue: .main) { [weak self] notification in
            guard let self, let vc = notification.userInfo?[notificationViewControllerKey] as? UIViewController else { return }
            if self !== vc {
                otherViewControllerDidAppear(vc)
            }
        }
    }
    
    open func otherViewControllerDidAppear(_ vc: UIViewController) { }
    
    // MARK: - Navigation bar
    
    public func addNavigationBar(navHeight: CGFloat? = nil, topOffset: CGFloat = 0, centerYOffset: CGFloat = 0, title: String? = nil, subtitle: String? = nil, leadingItem: WNavigationBarButton? = nil, trailingItem: WNavigationBarButton? = nil, tintColor: UIColor? = nil, titleColor: UIColor? = nil, closeIcon: Bool = false, addBackButton: (() -> Void)? = nil, prefersHardEdge: Bool = false) {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *), !prefersHardEdge {
            if let title {
                self.title = title
            }
            if let subtitle {
                self.navigationItem.subtitle = subtitle
            }
            if closeIcon {
                navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in topViewController()?.dismiss(animated: true) })
            }
            if let leadingItem {
                // TODO: only cancel button is supported
                navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { _ in leadingItem.onPress?() })
            }
        } else {
            let navHeight = navHeight ?? (isPresentationModal ? 60 : 44)
            let navigationBar = WNavigationBar(navHeight: navHeight, topOffset: topOffset, centerYOffset: centerYOffset, title: title, subtitle: subtitle, leadingItem: leadingItem, trailingItem: trailingItem, tintColor: tintColor, titleColor: titleColor, closeIcon: closeIcon, addBackButton: addBackButton)
            self.navigationBar = navigationBar
            navigationBar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(navigationBar)
            NSLayoutConstraint.activate([
                navigationBar.topAnchor.constraint(equalTo: view.topAnchor),
                navigationBar.leftAnchor.constraint(equalTo: view.leftAnchor),
                navigationBar.rightAnchor.constraint(equalTo: view.rightAnchor)
            ])
        }
    }
    
    public var isPresentationModal: Bool {
        if let navigationController, navigationController.presentingViewController?.presentedViewController === navigationController {
            return true
        }
        return false
    }

    public func addCloseNavigationItemIfNeeded() {
        guard isPresentationModal else { return }
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { _ in
            topViewController()?.dismiss(animated: true)
        })
    }
    
    public func configureNavigationItemWithTransparentBackground() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.backgroundEffect = nil
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
    }
    
    public func bringNavigationBarToFront() {
        if let navigationBar {
            view.bringSubviewToFront(navigationBar)
        }
    }
    
    public func updateSeparator(_ y: CGFloat) {
        navigationBar?.showSeparator = y > navigationBarProgressiveBlurMinY
    }
    
    public func calculateNavigationBarProgressiveBlurProgress(_ y: CGFloat) -> CGFloat {
        let minY = navigationBarProgressiveBlurMinY
        let delta = navigationBarProgressiveBlurDelta
        guard delta > 0 else {
            return y > navigationBarProgressiveBlurMinY ? 1 : 0
        }
        let _p = (y - minY) / delta
        let p = min(1, max(0, _p))
        return p
    }
    
    public func updateNavigationBarProgressiveBlur(_ y: CGFloat) {
        let progress = calculateNavigationBarProgressiveBlurProgress(y)
        navigationBar?.blurView.alpha = progress
        navigationBar?.separatorView.alpha = progress
    }
    
    public func weakifyUpdateProgressiveBlur() -> (_ y: CGFloat) -> () {
        return { [weak self] y in
            self?.updateNavigationBarProgressiveBlur(y)
        }
    }
        
    public var canGoBack: Bool {
        if let navigationController, navigationController.viewControllers.count > 1 {
            return true
        }
        return false
    }
    
    open func goBack() {
        navigationController?.popViewController(animated: true)
    }
    
    public func weakifyGoBack() -> () -> () {
        return { [weak self] in self?.goBack() }
    }
    
    public func weakifyGoBackIfAvailable() -> (() -> ())? {
        if canGoBack {
            return { [weak self] in self?.goBack() }
        }
        return nil
    }
    
    public func addCustomNavigationBarBackground(constant: CGFloat = 6) {
        let customBackground = HostingView {
            NavigationBarBackground()
        }
        customBackground.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(customBackground)
        NSLayoutConstraint.activate([
            customBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customBackground.topAnchor.constraint(equalTo: view.topAnchor),
            customBackground.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: constant),
        ])
        self.customNavigationBarBackground = customBackground
    }
    
    // MARK: - Hosting controller
    
    public func addHostingController<V: View>(_ rootView: V, constraints: ((UIView) -> ())? = nil) -> UIHostingController<V> {
        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        if let constraints {
            constraints(hostingController.view)
        }
        hostingController.didMove(toParent: self)
        hostingController.view.backgroundColor = .clear
        return hostingController
    }
    
    public enum ConstraintsConfig {
        case fill
        case fillWithNavigationBar
        
        public var constraints: (_ parent: WViewController, _ child: UIView) -> () {
            switch self {
            case .fill:
                return { parent, child in
                    NSLayoutConstraint.activate([
                        child.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
                        child.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
                        child.topAnchor.constraint(equalTo: parent.view.topAnchor),
                        child.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor),
                    ])
                }
            case .fillWithNavigationBar:
                return { parent, child in
                    NSLayoutConstraint.activate([
                        child.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
                        child.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
                        child.topAnchor.constraint(equalTo: parent.navigationBarAnchor),
                        child.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor),
                    ])
                }
            }
        }
    }
    
    public func addHostingController<V: View>(_ rootView: V, constraints: ConstraintsConfig) -> UIHostingController<V> {
        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        constraints.constraints(self, hostingController.view)
        hostingController.didMove(toParent: self)
        hostingController.view.backgroundColor = .clear
        return hostingController
    }
    
    // MARK: - Bottom button
    
    public func addBottomButton(bottomConstraint: Bool = true) -> WButton {
        let button = WButton(style: .primary)
        self.bottomButton = button
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        if bottomConstraint {
            let bottomConstraint = button.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16)
            self.bottomButtonConstraint = bottomConstraint
            NSLayoutConstraint.activate([
                bottomConstraint,
                button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
            ])
        } else {
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
            ])
        }
        return button
    }

    // MARK: - Bottom bar blur
    
    public func addBottomBarBlur() {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
        } else {
            let tabBarBlurView = WBlurView()
            self.bottomBarBlurView = tabBarBlurView
            tabBarBlurView.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(tabBarBlurView)
            let constraint = tabBarBlurView.heightAnchor.constraint(equalToConstant: view.safeAreaInsets.bottom)
            self.bottomBarBlurConstraint = constraint
            NSLayoutConstraint.activate([
                tabBarBlurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tabBarBlurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                constraint,
                tabBarBlurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
    }
    
    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateMaxContentWidthIfNeeded()
        updateBottomBarBlurConstraint()
    }
    
    open func updateBottomBarBlurConstraint() {
        let newHeight = view.safeAreaInsets.bottom
        if let bottomBarBlurConstraint, view.safeAreaInsets.bottom > 30 {
            if bottomBarBlurConstraint.constant > 0, newHeight > bottomBarBlurConstraint.constant {
                UIView.animate(withDuration: 0.3) { [self] in
                    bottomBarBlurConstraint.constant = view.safeAreaInsets.bottom
                    view.layoutIfNeeded()
                }
            } else {
                bottomBarBlurConstraint.constant = view.safeAreaInsets.bottom
            }
        }
    }
    
    open func updateMaxContentWidthIfNeeded() {
        guard let maxContentWidth, maxContentWidth > 0 else {
            applyMaxContentWidthHorizontalInset(0)
            return
        }

        let previousInset = appliedHorizontalSafeAreaInsetForMaxContentWidth
        let baseSafeAreaLeft = max(0, view.safeAreaInsets.left - previousInset)
        let baseSafeAreaRight = max(0, view.safeAreaInsets.right - previousInset)
        let availableWidth = view.bounds.width - baseSafeAreaLeft - baseSafeAreaRight
        guard availableWidth > 0 else { return }

        let desiredInset = max(0, floor((availableWidth - maxContentWidth) * 0.5))
        applyMaxContentWidthHorizontalInset(desiredInset)
    }

    private func applyMaxContentWidthHorizontalInset(_ inset: CGFloat) {
        let inset = max(0, inset)
        guard abs(inset - appliedHorizontalSafeAreaInsetForMaxContentWidth) > 0.5 else { return }

        var newInsets = additionalSafeAreaInsets
        let previousInset = appliedHorizontalSafeAreaInsetForMaxContentWidth
        newInsets.left = max(0, newInsets.left - previousInset + inset)
        newInsets.right = max(0, newInsets.right - previousInset + inset)
        appliedHorizontalSafeAreaInsetForMaxContentWidth = inset
        additionalSafeAreaInsets = newInsets
    }

    // MARK: - Toast
    var toastView: UIView? = nil
    private var toastHider: DispatchWorkItem?
    private var toastAction: (() -> ())?
    public func showToast(animationName: String? = nil, message: String, duration: Double, tapAction: (() -> ())? = nil) {
        hideToastView()
        toastView = UIView()
        let blurView = WBlurView.attach(to: toastView!, background: .black.withAlphaComponent(0.75))
        blurView.layer.cornerRadius = 16
        blurView.layer.masksToBounds = true
        toastView?.alpha = 0
        toastView?.translatesAutoresizingMaskIntoConstraints = false
        toastView?.layer.cornerRadius = 16
        toastView?.layer.shadowColor = UIColor.black.cgColor
        toastView?.layer.shadowOpacity = 0.2
        toastView?.layer.shadowOffset = CGSize(width: 0, height: 1)
        toastView?.layer.shadowRadius = 16
        toastView?.backgroundColor = .clear
        toastView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onToastTap)))
        
        self.toastAction = tapAction
        
        let animatedSticker: WAnimatedSticker?
        if let animationName {
            animatedSticker = WAnimatedSticker()
            animatedSticker!.animationName = animationName
            animatedSticker!.translatesAutoresizingMaskIntoConstraints = false
            animatedSticker!.setup(width: 35,
                                  height: 35,
                                  playbackMode: .once)
            toastView!.addSubview(animatedSticker!)
            NSLayoutConstraint.activate([
                animatedSticker!.centerYAnchor.constraint(equalTo: toastView!.centerYAnchor),
                animatedSticker!.leftAnchor.constraint(equalTo: toastView!.leftAnchor, constant: 7),
                animatedSticker!.widthAnchor.constraint(equalToConstant: CGFloat(35)),
                animatedSticker!.heightAnchor.constraint(equalToConstant: CGFloat(35))
            ])
        } else {
            animatedSticker = nil
        }
        
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 13)
        lbl.textColor = .white
        lbl.text = message
        lbl.numberOfLines = 0
        toastView!.addSubview(lbl)
        view.addSubview(toastView!)
        let bottomConstraint = toastView!.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: toastView!.topAnchor),
            lbl.leftAnchor.constraint(equalTo: animatedSticker?.rightAnchor ?? toastView!.leftAnchor, constant: animatedSticker?.rightAnchor == nil ? 12 : 8),
            lbl.rightAnchor.constraint(equalTo: toastView!.rightAnchor, constant: -12),
            lbl.bottomAnchor.constraint(equalTo: toastView!.bottomAnchor),
            lbl.heightAnchor.constraint(greaterThanOrEqualToConstant: 49),
            bottomConstraint,
            toastView!.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 12),
            toastView!.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -12),
        ])
        toastView?.alpha = 0
        view.layoutIfNeeded()
        UIView.animate(withDuration: 0.3) {
            self.toastView?.alpha = 1
            self.view.layoutIfNeeded()
        }
        toastHider?.cancel()
        let toastHider = DispatchWorkItem { [weak self] in
            guard let self else {return}
            hideToastView()
        }
        self.toastHider = toastHider
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: toastHider)
    }
    
    private func hideToastView() {
        guard let toastView else {
            return
        }
        UIView.animate(withDuration: 0.3) {
            toastView.alpha = 0
        } completion: { _ in
            toastView.removeFromSuperview()
        }
        self.toastView = nil
    }
    
    @objc private func onToastTap() {
        toastAction?()
        toastHider?.perform()
    }
    
    // MARK: - Tip
    
    public func showTip<Content: View>(title: String, kind: TipView<Content>.Kind = .info, wide: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        let vc = UIHostingController(rootView: TipView(title: title, kind: kind, wide: wide, content: content))
        vc.modalPresentationStyle = .overFullScreen
        vc.view.backgroundColor = .clear
        present(vc, animated: false)
    }
}
