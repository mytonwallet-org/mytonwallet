
import UIKit
import SwiftUI
import Perception

public struct StackedContent<Content1: View, Content2: View>: View {
    
    @Environment(\.containerSize) private var containerSize: CGSize
    
    private var content1: Content1
    private var content2: Content2
    
    @Environment(MenuContext.self) var menuContext
    
    @State private var rootWidth: CGFloat = 200
    
    @State private var rootHasScroll = false
    @State private var detailHasScroll = false
    
    public init(@ViewBuilder content1: () -> Content1, @ViewBuilder content2: () -> Content2) {
        self.content1 = content1()
        self.content2 = content2()
    }
    
    public var body: some View {
        WithPerceptionTracking {
            ZStack(alignment: .top) {
                content1
                    .backportGeometryGroup()
                    .offset(x: menuContext.submenuId == "0" ? 0 : -40)
                    .opacity(isSubmenuVisible("0") ? 1 : 0)
                    .onPreferenceChange(HasScrollPreference.self) { rootHasScroll = $0 }
                
                content2
                    .backportGeometryGroup()
                    .offset(x: menuContext.submenuId == "1" ? 0 : rootWidth + 25)
                    .shadow(color: .black.opacity(0.2), radius: 16)
                    .opacity(isSubmenuVisible("1") ? 1 : 0)
                    .onPreferenceChange(HasScrollPreference.self) { detailHasScroll = $0 }
            }
            .onPreferenceChange(SizePreference.self) { sizes in
                if let width = sizes["0"]?.width, width > 0, width > rootWidth {
                    rootWidth = width
                }
            }
            .preference(key: HasScrollPreference.self, value: menuContext.submenuId == "1" ? detailHasScroll : rootHasScroll)
            .compositingGroup()
        }
    }
    
    func isSubmenuVisible(_ id: String) -> Bool {
        id == "0" || menuContext.submenuId == id || menuContext.visibleSubmenus.contains(id)
    }
}
