
import UIKit
import SwiftUI

private let edgePadding: CGFloat = 4
private let maxWidth: CGFloat = 250

struct MenuContainer<Content: View>: View {
    
    @ObservedObject var menuContext: MenuContext
    
    @ViewBuilder var content: () -> Content
    
    @State private var screenSize: CGSize = .init(width: 400, height: 1200)
    @State private var hasScroll: Bool = false
    
    let distanceFromAnchor: CGFloat = 8
    
    var body: some View {
        let _ = Self._printChanges()
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                if menuContext.menuShown {
                    content()
                        .clipShape(.rect(cornerRadius: 12))
                        .shadow(color: menuContext.sourceView == nil ? .black.opacity(0.25) : .clear, radius: 40, x: 0, y: 4)
                        .transition(.scale(scale: 0.2, anchor: .top).combined(with: .opacity))
                        .gesture(gesture)
                        .frame(maxWidth: maxWidth)
                        .onPreferenceChange(HasScrollableContentPreference.self) { hasScroll in
                            self.hasScroll = hasScroll
                        }
                }
            }
            .padding(.leading, max(edgePadding, min(menuContext.sourceFrame.midX - 0.5 * maxWidth, screenSize.width - edgePadding - maxWidth)))
            .padding(.trailing, edgePadding)
            .padding(.top, menuContext.sourceFrame.maxY + distanceFromAnchor)
            .padding(.bottom, 34)
        }
        .onGeometryChange(for: CGSize.self, of: \.size, action: { screenSize = $0 })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 1)) {
                menuContext.menuShown = true
                menuContext.prefix = ""
            }
        }
        .environmentObject(menuContext)
        .ignoresSafeArea(.all)
    }
    
    var gesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { g in
                if abs(g.translation.height) < 10 || !hasScroll {
                    menuContext.update(location: g.location)
                } else {
                    menuContext.deselectItem()
                }
            }
            .onEnded { g in
                if abs(g.translation.height) < 10 || !hasScroll {
                    menuContext.triggerCurrentAction()
                } else {
                    menuContext.deselectItem()
                }
            }
    }
}
