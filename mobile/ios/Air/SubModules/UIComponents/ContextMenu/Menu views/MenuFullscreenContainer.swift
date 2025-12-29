
import UIKit
import SwiftUI
import Perception

/// Positions MenuDrawAreaContainer below sourceFrame
struct MenuFullscreenContainer: View {
    
    var menuContext: MenuContext
    @State private var size: CGSize = .zero
    
    var body: some View {
        WithPerceptionTracking {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                //            Color.red.frame(rect: menuContext.sourceFrame)
                MenuDrawAreaContainer(sourceX: menuContext.sourceX, showBelowSource: menuContext.showBelowSource)
                    .padding(.top, menuContext.showBelowSource ? menuContext.source.y : 100)
                    .padding(.bottom, menuContext.showBelowSource ? 34 : size.height - menuContext.source.y)
                    .padding(.horizontal, MENU_EDGE_PADDING)
                
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea(.all)
            .environment(menuContext)
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
        }
    }
}
