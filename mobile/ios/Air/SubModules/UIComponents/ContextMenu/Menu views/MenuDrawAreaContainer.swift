
import UIKit
import SwiftUI

struct MenuDrawAreaContainer: View {
    
    var sourceX: CGFloat
    var showBelowSource: Bool
    
    @State private var containerSize: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.clear
            if containerSize != .zero {
                MenuClippingContainer(sourceX: sourceX, showBelowSource: showBelowSource)
            }
        }
        .environment(\.containerSize, containerSize)
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            self.containerSize = size
        }
    }
}
