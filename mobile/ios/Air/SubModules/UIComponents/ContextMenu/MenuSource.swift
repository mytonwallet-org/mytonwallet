
import UIKit
import SwiftUI


extension View {
    @ViewBuilder
    public func menuSource(
        isEnabled: Bool = true,
        isTapGestureEnabled: Bool = true,
        isHoldAndDragGestureEnabled: Bool = true,
        coordinateSpace: CoordinateSpace = .global,
        menuContext: MenuContext?
    ) -> some View {
        if let menuContext, isEnabled {
            modifier(
                MenuSourceViewModifier(
                    coordinateSpace: coordinateSpace,
                    menuContext: menuContext,
                    isTapGestureEnabled: isTapGestureEnabled,
                    isHoldAndDragGestureEnabled: isHoldAndDragGestureEnabled,
                )
            )
        } else {
            self
        }
    }
}

struct MenuSourceViewModifier: ViewModifier {
    
    private var coordinateSpace: CoordinateSpace
    private var menuContext: MenuContext
    private var isTapGestureEnabled: Bool
    private var isHoldAndDragGestureEnabled: Bool
    
    init(coordinateSpace: CoordinateSpace, menuContext: MenuContext, isTapGestureEnabled: Bool, isHoldAndDragGestureEnabled: Bool) {
        self.coordinateSpace = coordinateSpace
        self.menuContext = menuContext
        self.isTapGestureEnabled = isTapGestureEnabled
        self.isHoldAndDragGestureEnabled = isHoldAndDragGestureEnabled
    }
    
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
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: coordinateSpace) }, action: { menuContext.sourceFrame = $0 })
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
