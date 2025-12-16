
import UIKit
import SwiftUI
import Popovers
import Perception

struct MenuClippingContainer: View {
    
    var sourceX: CGFloat
    var showBelowSource: Bool

    @State var preferredSizes: [String: CGSize] = [:]
    @State var hasScroll: Bool = false
    
    @Environment(MenuContext.self) var menuContext
    @Environment(\.containerSize) private var containerSize: CGSize
    
    var body: some View {
        GeometryReader { geom in
            WithPerceptionTracking {
                ZStack {
                    Color.clear
                    if menuContext.menuShown {
                        HStack {
                            let menu = menuContext.makeConfig()
                            if let submemu = menuContext.makeSubmenuConfig?() {
                                StackedContent {
                                    MenuViewFromConfig(menuConfig: menu, width: effectiveWidth)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                } content2: {
                                    MenuViewFromConfig(menuConfig: submemu, width: effectiveWidth)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                        .background {
                                            Rectangle().fill(Material.regular)
                                        }
                                }
                                .background {
                                    Rectangle().fill(Material.regular)
                                }
                            } else {
                                MenuViewFromConfig(menuConfig: menu, width: effectiveWidth)
                                    .background {
                                        Rectangle().fill(Material.regular)
                                    }
                            }
                        }
                        .simultaneousGesture(gesture)
                        .clipShape(.rect(cornerRadius: S.menuCornerRadius))
                        .transition(.scale(scale: 0.2, anchor: showBelowSource ? .top : .bottom).combined(with: .opacity))
                    }
                }
                .frame(width: effectiveWidth, height: effectiveHeight, alignment: showBelowSource ? .top : .bottom)
                .clipShape(.rect(cornerRadius: S.menuCornerRadius))
                .shadow(color: menuContext.showShadow ? .black.opacity(0.25) : .clear, radius: 40, x: 0, y: 4)
                .frame(rect: CGRect(
                    x: xOffset,
                    y: showBelowSource ? 0 : containerSize.height - effectiveHeight,
                    width: effectiveWidth,
                    height: effectiveHeight
                ))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85, blendDuration: 1)) {
                menuContext.menuShown = true
            }
        }
        .environment(menuContext)
        .onPreferenceChange(SizePreference.self) { preferredSizes in
            if !preferredSizes.isEmpty {
                self.preferredSizes = preferredSizes
            }
        }
        .onPreferenceChange(HasScrollPreference.self) { hasScroll = $0 }
    }
    
    var preferredSize: CGSize {
        if let s = preferredSizes[menuContext.submenuId] {
            return s
        }
        return CGSize(width: 100, height: 100)
    }
    
    var effectiveHeight: CGFloat {
        min(preferredSize.height, containerSize.height)
    }
    
    var effectiveWidth: CGFloat {
        var w =  min(preferredSize.width, containerSize.width)
        if let minWidth = menuContext.minWidth, w < minWidth {
            w = minWidth
        }
        if let maxWidth = menuContext.maxWidth, w > maxWidth {
            w = maxWidth
        }
        return w
    }
    
    var xOffset: CGFloat {
        let offset = sourceX - effectiveWidth / 2
        if offset < 0 {
            return 0
        }
        if offset + effectiveWidth > containerSize.width {
            return max(0, containerSize.width - effectiveWidth)
        }
        return offset
    }
    
    var gesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { g in
                if hasScroll && abs(g.translation.height) > 10 {
                    menuContext.deselectItem()
                } else {
                    menuContext.update(location: g.location)
                }
            }
            .onEnded { g in
                if hasScroll && abs(g.translation.height) > 10 {
                    menuContext.deselectItem()
                } else {
                    menuContext.triggerCurrentAction()
                }
            }
    }
}
