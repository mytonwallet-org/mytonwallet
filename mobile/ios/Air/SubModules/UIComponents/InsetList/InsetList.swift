
import SwiftUI
import WalletContext


public struct InsetList<Content: View>: View {
    
    public var topPadding: CGFloat
    
    public var spacing: CGFloat

    private let topId = "_insetListTop"
    private var scrollToTopTrigger: AnyHashable?

    @ViewBuilder
    public var content: Content
    
    public init(topPadding: CGFloat = 8, spacing: CGFloat = 24, scrollToTopTrigger: AnyHashable? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.topPadding = topPadding
        self.spacing = spacing
        self.scrollToTopTrigger = scrollToTopTrigger
        self.content = content()
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: topPadding)
                        .id(topId)

                    VStack(spacing: spacing) {
                        content
                    }
                }
            }
            .onChange(of: scrollToTopTrigger) { _ in
                proxy.scrollTo(topId, anchor: .top)
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

