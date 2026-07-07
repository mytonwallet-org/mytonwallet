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

open class WViewController: UIViewController {
    
    open var bottomButton: WButton? = nil
    open var bottomButtonConstraint: NSLayoutConstraint? = nil
    
    open var navigationBarProgressiveBlurMinY: CGFloat = 0
    open var navigationBarProgressiveBlurDelta: CGFloat = 16

    open var hideNavigationBar: Bool {
        false
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
        view.backgroundColor = .air.background
        self.view = view
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

    nonisolated(unsafe) private var observer: NSObjectProtocol?
    private let notificationViewControllerKey = "viewController"
    private let wViewControllerDidAppearNtf = Notification.Name("WViewControllerDidAppear")
    
    public func registerForOtherViewControllerAppearNotifications() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: wViewControllerDidAppearNtf, object: nil, queue: .main) { [weak self] notification in
            guard let self, let vc = notification.userInfo?[notificationViewControllerKey] as? UIViewController else { return }
            if self !== vc {
                MainActor.assumeIsolated {
                    self.otherViewControllerDidAppear(vc)
                }
            }
        }
    }
    
    open func otherViewControllerDidAppear(_ vc: UIViewController) { }
    
    // MARK: - Navigation bar
    
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
        navigationItem.compactAppearance = appearance
        navigationItem.compactScrollEdgeAppearance = appearance
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
        
    public var canGoBack: Bool {
        if let navigationController, navigationController.viewControllers.count > 1 {
            return true
        }
        return false
    }
    
    open func goBack() {
        navigationController?.popViewController(animated: true)
    }
    
    @discardableResult
    public func addCustomNavigationBarBackground(color: UIColor?, navItemTransparent: Bool = true) -> UIView {
        
        if navItemTransparent {
            configureNavigationItemWithTransparentBackground()
        }
        
        let bottomExtension: CGFloat = 18
        let topOverscan: CGFloat = 20
        let alpha: CGFloat
        let maxEdgeSize: CGFloat
        
        if #available(iOS 26.0, *) {
            maxEdgeSize = 64
            alpha = 0.85
        } else {
            maxEdgeSize = 28
            alpha = 0.95
        }
        
        let customBackground = NavigationBarEdgeEffectBackgroundView(
            content: color ?? .air.sheetBackground,
            alpha: alpha,
            topOverscan: topOverscan,
            maxEdgeSize: maxEdgeSize
        )
        customBackground.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(customBackground)
        NSLayoutConstraint.activate([
            customBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customBackground.topAnchor.constraint(equalTo: view.topAnchor, constant: -topOverscan),
            customBackground.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: bottomExtension),
        ])
        return customBackground
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
        
        @MainActor public var constraints: (_ parent: WViewController, _ child: UIView) -> () {
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

    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateMaxContentWidthIfNeeded()
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
    
    public lazy var toastController = ToastController(containerView: view)

    public func showToast(_ config: ToastConfig) {
        toastController.showToast(config)
    }
    
    // MARK: - Tip
    
    public func showTip<Content: View>(title: String, kind: TipView<Content>.Kind = .info, wide: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        let vc = UIHostingController(rootView: TipView(title: title, kind: kind, wide: wide, content: content))
        vc.modalPresentationStyle = .overFullScreen
        vc.view.backgroundColor = .clear
        present(vc, animated: false)
    }
}

private final class NavigationBarEdgeEffectBackgroundView: UIView {
    private let edgeEffectView = EdgeEffectView()
    private var content: UIColor
    private let contentAlpha: CGFloat
    private let topOverscan: CGFloat
    private let maxEdgeSize: CGFloat

    init(content: UIColor, alpha: CGFloat, topOverscan: CGFloat, maxEdgeSize: CGFloat) {
        self.content = content
        self.contentAlpha = alpha
        self.topOverscan = topOverscan
        self.maxEdgeSize = maxEdgeSize
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        addSubview(edgeEffectView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        edgeEffectView.frame = bounds
        let effectiveHeight = max(1, bounds.height - topOverscan)
        edgeEffectView.update(
            content: content,
            blur: true,
            alpha: contentAlpha,
            edge: .top,
            edgeSize: min(maxEdgeSize, effectiveHeight)
        )
    }
}
