
import SwiftUI
import SwiftUIIntrospect

public extension View {
    @ViewBuilder
    func backportScrollClipDisabled() -> some View {
        if #available(iOS 17, *) {
            self.scrollClipDisabled()
        } else {
            self.introspect(.scrollView, on: .iOS(.v16)) { scrollView in scrollView.clipsToBounds = false }
        }
    }
  
    @ViewBuilder
    func backportSafeAreaPadding(_ edges: Edge.Set, _ length: CGFloat) -> some View {
        if #available(iOS 17, *) {
            self.safeAreaPadding(edges, length)
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
    
    @ViewBuilder
    func backportSensoryFeedback(value: Bool) -> some View {
        if #available(iOS 17, *) {
            self.sensoryFeedback(trigger: value) { oldValue, newValue in
                if newValue {
                    return .impact(flexibility: .soft, intensity: 0.5)
                }
                return nil
            }
        } else {
            self
        }
    }
}
