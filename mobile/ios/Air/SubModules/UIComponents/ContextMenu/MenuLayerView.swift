
import UIKit
import SwiftUI


@MainActor public func getMenuLayerView() -> MenuLayerView? {
    guard let window = UIApplication.shared.sceneKeyWindow else { return nil }
    for child in window.subviews {
        if let menuView = child as? MenuLayerView {
            window.bringSubviewToFront(menuView)
            return menuView
        }
    }
    let menuView = MenuLayerView()
    window.addSubview(menuView)
    NSLayoutConstraint.activate([
        menuView.topAnchor.constraint(equalTo: window.topAnchor),
        menuView.leadingAnchor.constraint(equalTo: window.leadingAnchor),
        menuView.trailingAnchor.constraint(equalTo: window.trailingAnchor),
        menuView.bottomAnchor.constraint(equalTo: window.bottomAnchor),
    ])
    menuView.frame = window.bounds
    return menuView
}


public final class MenuLayerView: UIView {
    
    private var hostingView: UIView?
    private var menuContext: MenuContext?

    private let blurredBackground = BlurredMenuBackground()
    private var portalView: UIView?
    
    init() {
        super.init(frame: .zero)
        setup()
        NotificationCenter.default.addObserver(self, selector: #selector(dismissMenu), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(blurredBackground)
        blurredBackground.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blurredBackground.topAnchor.constraint(equalTo: topAnchor),
            blurredBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurredBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurredBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        blurredBackground.isUserInteractionEnabled = false
        blurredBackground.alpha = 0

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapGesture))
        addGestureRecognizer(tapGesture)
    }
    
    func showMenu(menuContext: MenuContext) {
        menuContext.menuTriggered = true
        Haptics.play(.transition)
        
        if let sourceView = menuContext.sourceView, let window = sourceView.window, let portalView = makePortalView(of: sourceView) {
            addSubview(portalView)
            portalView.frame = sourceView.convert(sourceView.bounds, to: self)
            self.portalView = portalView

            let maskFrame = menuContext.sourceViewLayout.portalMaskFrame ?? menuContext.sourceViewLayout.frame
            if !maskFrame.isEmpty {
                let sourceFrameInPortal = window.convert(maskFrame, to: portalView)
                let mask = UIView()
                mask.frame = sourceFrameInPortal
                mask.backgroundColor = .white
                portalView.mask = mask
            }
        }
        
        if menuContext.sourceView != nil {
            UIView.animate(withDuration: 0.2) {
                self.blurredBackground.alpha = 1
            }
        }
        
        if let hostingView {
            hostingView.removeFromSuperview()
        }
        let hostingView = HostingView {
            MenuFullscreenContainer(menuContext: menuContext)
        }
        self.hostingView = hostingView
        hostingView.backgroundColor = .clear
        
        self.isHidden = false
        self.isUserInteractionEnabled = true
        
        addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        self.menuContext = menuContext
        menuContext.onAppear?()
    }
    
    @objc public func dismissMenu() {
        if let menuContext {
            menuContext.menuTriggered = false
            menuContext.onDismiss?()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9, blendDuration: 1)) {
                menuContext.menuShown = false
            }
            UIView.animate(withDuration: 0.2, delay: 0.1, options: []) {
                self.blurredBackground.alpha = 0
            }
            UIView.animate(withDuration: 0.2, delay: 0.15, options: []) {
                self.portalView?.alpha = 0
            }
        }
        isUserInteractionEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, hostingView, menuContext] in
            if let self, self.hostingView === hostingView {
                if let hostingView {
                    hostingView.removeFromSuperview()
                }
                self.hostingView = nil
                self.isHidden = true
                if self.superview != nil {
                    self.removeFromSuperview()
                }
                menuContext?.submenuId = "0"
                menuContext?.locations = [:]
            }
        }
    }
    
    @objc private func tapGesture() {
        dismissMenu()
    }
}

