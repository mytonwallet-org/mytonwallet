
import UIKit
import SwiftUI

extension View {
    @ViewBuilder
    public func menuSource(
        isEnabled: Bool = true,
        isTapGestureEnabled: Bool = true,
        isHoldAndDragGestureEnabled: Bool = true,
        coordinateSpace: CoordinateSpace = .global,
        menuContext: MenuContext?,
        /// Extra insets to be added to menu.sourceFrame calculated via menu.onGetSourceFrame
        edgeInsets: UIEdgeInsets = .zero
    ) -> some View {
        if let menuContext, isEnabled {
            modifier(
                MenuSourceViewModifier(
                    coordinateSpace: coordinateSpace,
                    menuContext: menuContext,
                    isTapGestureEnabled: isTapGestureEnabled,
                    isHoldAndDragGestureEnabled: isHoldAndDragGestureEnabled,
                    edgeInsets: edgeInsets,
                )
            )
        } else {
            self
        }
    }
}

private struct MenuSourceViewModifier: ViewModifier {
    let coordinateSpace: CoordinateSpace
    let menuContext: MenuContext
    let isTapGestureEnabled: Bool
    let isHoldAndDragGestureEnabled: Bool
    let edgeInsets: UIEdgeInsets
        
    func body(content: Content) -> some View {
        content
            .padding(8)
            .contentShape(.rect)
            .gesture(tapGesture, isEnabled: isTapGestureEnabled)
            .holdAndDragGesture(
                isEnabled: isHoldAndDragGestureEnabled,
                onBegan: { _ in
                    menuContext.present()
                },
                onChanged: { point in
                    menuContext.present()
                    menuContext.update(location: point)
                },
                onEnded: {
                    menuContext.triggerCurrentAction()
                }
            )
            .padding(-8)
            .background(FrameReportingView(menuContext: menuContext, edgeInsets: edgeInsets))
    }
    
    var tapGesture: some Gesture {
        TapGesture().onEnded({
            showMenu()
        })
    }
    
    func showMenu() {
        menuContext.present()
    }
}

/// Registers a menuContext.getSourceFrame closure to resolve frame in window coords at menu.present() time.
/// This works more reliable than .onGeometryChange().
private struct FrameReportingView: UIViewRepresentable {
    let menuContext: MenuContext
    let edgeInsets: UIEdgeInsets

    func makeUIView(context: Context) -> UIView { _FrameReportingUIView(menuContext: menuContext, edgeInsets: edgeInsets) }
    func updateUIView(_ uiView: UIView, context: Context) { (uiView as? _FrameReportingUIView)?.menuContext = menuContext }
}

private final class _FrameReportingUIView: UIView {
    weak var menuContext: MenuContext?
    let edgeInsets: UIEdgeInsets
    
    init(menuContext: MenuContext?, edgeInsets: UIEdgeInsets) {
        self.menuContext = menuContext
        self.edgeInsets = edgeInsets
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
                
        // There can be a few views for the same menu context on the screen at a moment
        // We will only respect (i.e., set the handler for) the last one, which effectively resign the former ones
        if window != nil {
            menuContext?.onGetSourceViewLayout = { [weak self] in
                guard let self, window != nil, !bounds.isEmpty else { return nil }
                return .init(frame: convert(bounds.inset(by: edgeInsets), to: nil))
            }
        }
    }
}

// MARK: - UIKit integration

public extension UIView {
    func attachMenu(menuContext: MenuContext) {
        let delegate = MenuSourceUIKitGestureDelegate(menuContext: menuContext, sourceView: self)
        objc_setAssociatedObject(self, &menuSourceDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        
        isUserInteractionEnabled = true
    }
}

private var menuSourceDelegateKey: UInt8 = 0
private var menuSourceSuppressNextTapKey: UInt8 = 0

public extension UIView {
    /// Returns `true` if the tap should be suppressed (menu was just shown). Call from tap handler.
    /// One-time check: if the flag is set, it is cleared and true is returned; subsequent calls return false until the menu is shown again.
    @discardableResult func consumeMenuShownTapIfNeeded() -> Bool {
        let suppress = (objc_getAssociatedObject(self, &menuSourceSuppressNextTapKey) as? NSNumber)?.boolValue ?? false
        if suppress {
            objc_setAssociatedObject(self, &menuSourceSuppressNextTapKey, nil, .OBJC_ASSOCIATION_RETAIN)
            return true
        }
        return false
    }
}

private final class MenuSourceUIKitGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    let menuContext: MenuContext
    weak var sourceView: UIView?
    
    private let longPress = UILongPressGestureRecognizer(target: nil, action: nil)
    private var tap: UITapGestureRecognizer?

    init(menuContext: MenuContext, sourceView: UIView) {
        self.menuContext = menuContext
        self.sourceView = sourceView
        self.menuContext.sourceView = sourceView
        
        super.init()

        longPress.minimumPressDuration = 0.25
        longPress.allowableMovement = 10
        longPress.delegate = self
        longPress.addTarget(self, action: #selector(longPressed(_:)))
        sourceView.addGestureRecognizer(longPress)

        if menuContext.presentOnTap {
            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tapRecognizer.delegate = self
            sourceView.addGestureRecognizer(tapRecognizer)
            self.tap = tapRecognizer
        }
    }

    @objc private func tapped(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended, let sourceView else { return }
        objc_setAssociatedObject(sourceView, &menuSourceSuppressNextTapKey, true as NSNumber, .OBJC_ASSOCIATION_RETAIN)
        menuContext.present()
    }

    @objc private func longPressed(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard let sourceView else { return }
        
        let point = gestureRecognizer.location(in: nil)
        switch gestureRecognizer.state {
        case .began:
            objc_setAssociatedObject(sourceView, &menuSourceSuppressNextTapKey, true as NSNumber, .OBJC_ASSOCIATION_RETAIN)
            menuContext.present()
        case .changed:
            menuContext.present()
            menuContext.update(location: point)
        case .ended, .cancelled:
            menuContext.triggerCurrentAction()
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // cancel pan gesture recognizers to prevent simultaneous scrolling while navigating menu items
        if otherGestureRecognizer is UIPanGestureRecognizer {
            return false
        }
        
        return true
    }
}
