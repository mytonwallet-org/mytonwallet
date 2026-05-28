
import SwiftUI
import WalletContext


public struct InsetList<Content: View>: View {
    
    public var topPadding: CGFloat
    
    public var spacing: CGFloat
    
    @ViewBuilder
    public var content: Content
    
    public init(topPadding: CGFloat = 8, spacing: CGFloat = 24, @ViewBuilder content: @escaping () -> Content) {
        self.topPadding = topPadding
        self.spacing = spacing
        self.content = content()
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: topPadding)

                VStack(spacing: spacing) {
                    content
                }
            }
        }
    }
}


public enum InsetListContext {
    case base
    case elevated
}


public extension EnvironmentValues {
    @Entry var insetListContext: InsetListContext?
}

