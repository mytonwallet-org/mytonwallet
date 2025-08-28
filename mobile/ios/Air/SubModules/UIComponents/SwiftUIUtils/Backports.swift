
import SwiftUI

public extension View {
    @ViewBuilder
    func backportScrollClipDisabled() -> some View {
        if #available(iOS 17, *) {
            self.scrollClipDisabled()
        } else {
            self
        }
    }
    
    @ViewBuilder
    func backportScrollBounceBehaviorBasedOnSize() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func backportContentMargins(_ length: CGFloat) -> some View {
        if #available(iOS 17, *) {
            self.contentMargins(.horizontal, length, for: .scrollContent)
        } else {
            self.padding(.horizontal, length)
        }
    }
    
    @ViewBuilder
    func backportGeometryGroup() -> some View {
        if #available(iOS 17, *) {
            self.geometryGroup()
        } else {
            self
        }
    }
}
