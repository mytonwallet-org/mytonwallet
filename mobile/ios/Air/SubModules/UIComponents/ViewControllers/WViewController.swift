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

    open var shouldPreserveSheetSizeOnPush: Bool {
        false
    }

    open var maxContentWidth: CGFloat? {
        nil
    }

    /// Prefer the view's center for a capped column, while keeping it inside the safe area.
    open var prefersViewCenteredContent: Bool {
        false
    }

    private var appliedSafeAreaInsetsForMaxContentWidth: UIEdgeInsets = .zero

    /// The backgrounds `addCustomNavigationBarBackground` made, which `setCustomNavigationBarBackgroundTint` paints
    private var customNavigationBarBackgrounds: [WeakNavigationBarBackground] = []

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
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "nav_close"
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
    public func addCustomNavigationBarBackground(
        color: UIColor?,
        navItemTransparent: Bool = true,
        maxEdgeSize: CGFloat? = nil,
        inside scrollView: UIScrollView? = nil
    ) -> UIView {
        
        if navItemTransparent {
            configureNavigationItemWithTransparentBackground()
        }
        
        let bottomExtension: CGFloat = 18
        let topOverscan: CGFloat = 20
        let alpha: CGFloat
        let defaultMaxEdgeSize: CGFloat
        
        if #available(iOS 26.0, *) {
            defaultMaxEdgeSize = 64
            alpha = 0.85
        } else {
            defaultMaxEdgeSize = 28
            alpha = 0.95
        }
        
        let customBackground = NavigationBarEdgeEffectBackgroundView(
            content: color ?? .air.sheetBackground,
            alpha: alpha,
            topOverscan: topOverscan,
            maxEdgeSize: maxEdgeSize ?? defaultMaxEdgeSize
        )
        customBackground.translatesAutoresizingMaskIntoConstraints = false
        customNavigationBarBackgrounds.removeAll { $0.view == nil }
        customNavigationBarBackgrounds.append(WeakNavigationBarBackground(view: customBackground))
        let bottomConstraint: NSLayoutConstraint
        if let scrollView {
            scrollView.addSubview(customBackground)
            bottomConstraint = customBackground.bottomAnchor.constraint(equalTo: scrollView.safeAreaLayoutGuide.topAnchor, constant: bottomExtension)
            NSLayoutConstraint.activate([
                customBackground.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
                customBackground.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
                customBackground.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor, constant: -topOverscan),
                bottomConstraint,
            ])
        } else {
            view.addSubview(customBackground)
            bottomConstraint = customBackground.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: bottomExtension)
            NSLayoutConstraint.activate([
                customBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                customBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                customBackground.topAnchor.constraint(equalTo: view.topAnchor, constant: -topOverscan),
                bottomConstraint,
            ])
        }
        customBackground.bottomConstraint = bottomConstraint
        customBackground.bottomExtension = bottomExtension
        return customBackground
    }
    
    /// A live copy of the header backdrop for transitions drawn above the screen's content.
    public static func makeCustomNavigationBarBackgroundCopy(of background: UIView) -> UIView? {
        (background as? NavigationBarEdgeEffectBackgroundView)?.makeCopy()
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
    
    public func addBottomButton(bottomConstraint: Bool = true, horizontalInset: CGFloat = 16) -> WButton {
        let button = WButton(style: .primary)
        self.bottomButton = button
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        if bottomConstraint {
            let bottomConstraint = button.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16)
            self.bottomButtonConstraint = bottomConstraint
            NSLayoutConstraint.activate([
                bottomConstraint,
                button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: horizontalInset),
                button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -horizontalInset)
            ])
        } else {
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: horizontalInset),
                button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -horizontalInset)
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
            applyMaxContentWidthHorizontalInsets(left: 0, right: 0)
            return
        }

        let previousInsets = appliedSafeAreaInsetsForMaxContentWidth
        let baseSafeAreaLeft = max(0, view.safeAreaInsets.left - previousInsets.left)
        let baseSafeAreaRight = max(0, view.safeAreaInsets.right - previousInsets.right)
        let availableWidth = view.bounds.width - baseSafeAreaLeft - baseSafeAreaRight
        guard availableWidth > 0 else { return }

        if prefersViewCenteredContent {
            let contentWidth = min(availableWidth, maxContentWidth)
            let preferredLeft = (view.bounds.width - contentWidth) * 0.5
            let contentLeft = min(max(preferredLeft, baseSafeAreaLeft), view.bounds.width - baseSafeAreaRight - contentWidth)
            applyMaxContentWidthHorizontalInsets(
                left: contentLeft - baseSafeAreaLeft,
                right: view.bounds.width - baseSafeAreaRight - contentLeft - contentWidth
            )
        } else {
            let desiredInset = max(0, floor((availableWidth - maxContentWidth) * 0.5))
            applyMaxContentWidthHorizontalInsets(left: desiredInset, right: desiredInset)
        }
    }

    private func applyMaxContentWidthHorizontalInsets(left: CGFloat, right: CGFloat) {
        let left = max(0, left)
        let right = max(0, right)
        let previousInsets = appliedSafeAreaInsetsForMaxContentWidth
        guard abs(left - previousInsets.left) > 0.5 || abs(right - previousInsets.right) > 0.5 else { return }

        var newInsets = additionalSafeAreaInsets
        newInsets.left = max(0, newInsets.left - previousInsets.left + left)
        newInsets.right = max(0, newInsets.right - previousInsets.right + right)
        appliedSafeAreaInsetsForMaxContentWidth = UIEdgeInsets(top: 0, left: left, bottom: 0, right: right)
        additionalSafeAreaInsets = newInsets
    }

    // MARK: - Toast
    
    public lazy var toastController = ToastController(containerView: view)

    public func showToast(_ config: ToastConfig) {
        toastController.showToast(config)
    }
    
    // MARK: - Tip
    
    public func showTip<Content: View>(title: String, kind: TipView.Kind = .info, wide: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        guard presentedViewController == nil, !isBeingDismissed else { return }
        view.endEditing(true)
        let vc = WAlertController(title: title, kind: kind, configuration: .init(wide: wide), actions: [WAlertAction(title: lang("OK"))], content: content)
        present(vc, animated: true)
    }
}

extension WViewController {
    /// Changes the color of a background made by `addCustomNavigationBarBackground`
    public func updateCustomNavigationBarBackground(_ background: UIView, color: UIColor) {
        (background as? NavigationBarEdgeEffectBackgroundView)?.updateColor(color)
    }

    /// Reaches a background made by `addCustomNavigationBarBackground` `extra` points further down, such as under a
    /// section header pinned below the bar
    public func setCustomNavigationBarBackgroundExtension(_ background: UIView, _ extra: CGFloat) {
        guard let background = background as? NavigationBarEdgeEffectBackgroundView,
              let constraint = background.bottomConstraint else { return }
        let constant = background.bottomExtension + extra
        if constraint.constant != constant { constraint.constant = constant }
    }

    /// Paints the backgrounds made by `addCustomNavigationBarBackground` in `color`, such as while paging carries a
    /// neighbouring tab's background over, so the band under the bar changes with the rest of the screen. Nil gives
    /// them their own colors back.
    public func setCustomNavigationBarBackgroundTint(_ color: UIColor?) {
        for entry in customNavigationBarBackgrounds {
            entry.view?.setTint(color)
        }
    }
}

private struct WeakNavigationBarBackground {
    weak var view: NavigationBarEdgeEffectBackgroundView?
}

private final class NavigationBarEdgeEffectBackgroundView: UIView {
    private let edgeEffectView = EdgeEffectView()
    private var content: UIColor
    private let contentAlpha: CGFloat
    private let topOverscan: CGFloat
    private let maxEdgeSize: CGFloat

    init(content: UIColor, alpha: CGFloat, topOverscan: CGFloat, maxEdgeSize: CGFloat) {
        self.content = content
        ownColor = content
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

    /// Pins the background's bottom below the safe area's top, `bottomExtension` points down at rest
    var bottomConstraint: NSLayoutConstraint?
    var bottomExtension: CGFloat = 0

    /// The color the screen gave the background, which a tint covers for a while
    private var ownColor: UIColor
    private var tint: UIColor?

    func updateColor(_ color: UIColor) {
        ownColor = color
        guard tint == nil else { return }
        content = color
        edgeEffectView.updateColor(color)
    }

    func makeCopy() -> UIView {
        NavigationBarEdgeEffectBackgroundView(
            content: content, alpha: contentAlpha, topOverscan: topOverscan, maxEdgeSize: maxEdgeSize
        )
    }

    func setTint(_ color: UIColor?) {
        guard color != tint else { return }
        tint = color
        let shown = color ?? ownColor
        content = shown
        edgeEffectView.updateColor(shown)
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
