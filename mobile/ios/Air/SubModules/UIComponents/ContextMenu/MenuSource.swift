
import UIKit
import SwiftUI


extension View {
    
    @ViewBuilder
    public func menuSource(
        isEnabled: Bool = true,
        isTapGestureEnabled: Bool = true,
        coordinateSpace: CoordinateSpace = .global,
        menuContext: MenuContext
    ) -> some View {
        if isEnabled {
            modifier(MenuSourceViewModifier(coordinateSpace: coordinateSpace, menuContext: menuContext, isTapGestureEnabled: isTapGestureEnabled))
        } else {
            self
        }
    }
}

struct MenuSourceViewModifier: ViewModifier {
    
    private var coordinateSpace: CoordinateSpace
    private var menuContext: MenuContext
    private var isTapGestureEnabled: Bool
    
    init(coordinateSpace: CoordinateSpace, menuContext: MenuContext, isTapGestureEnabled: Bool) {
        self.coordinateSpace = coordinateSpace
        self.menuContext = menuContext
        self.isTapGestureEnabled = isTapGestureEnabled
    }
    
    func body(content: Content) -> some View {
        content
            .padding(8)
            .contentShape(.rect)
            .gesture(tapGesture, isEnabled: isTapGestureEnabled)
            .gesture(holdAndDragGesture)
            .padding(-8)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: coordinateSpace) }, action: { menuContext.sourceFrame = $0 })
            .animation(.snappy, value: menuContext.menuShown)
            .environmentObject(menuContext)
    }
    
    var tapGesture: some Gesture {
        TapGesture().onEnded({
            showMenu()
        })
    }
    
    var holdAndDragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25, maximumDistance: 10)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { v in
                switch v {
                case .first:
                    break
                case .second(_, let drag):
                    showMenu()
                    if let drag {
                        menuContext.update(location: drag.location)
                    }
                }
            }
            .onEnded { v in
                switch v {
                case .first(_):
                    break
                case .second(_, _):
                    menuContext.triggerCurrentAction()
                }
            }
    }
    
    func showMenu() {
        menuContext.present()
    }
}
