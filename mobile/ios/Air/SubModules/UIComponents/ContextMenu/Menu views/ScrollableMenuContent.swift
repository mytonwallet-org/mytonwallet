
import UIKit
import SwiftUI


public struct ScrollableMenuContent<Content: View>: View {
    
    @ViewBuilder var content: () -> Content
    
    @EnvironmentObject private var menuContext: MenuContext
    
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    public var body: some View {
        basePage
        .background {
            Rectangle()
                .fill(Material.regular)
        }
        .clipShape(.rect(cornerRadius: 12))
    }
    
    var basePage: some View {
        ViewThatFits(in: .vertical) {
            content()
            ScrollView {
                content()
                    .preference(key: HasScrollableContentPreference.self, value: true)
            }
            .backportScrollBounceBehaviorBasedOnSize()
        }
        .clipShape(.rect(cornerRadius: 12))
    }
}


struct HasScrollableContentPreference: PreferenceKey {
    static var defaultValue = false
    
    static func reduce(value: inout Bool, nextValue: () -> Value) {
        value = value || nextValue()
    }
}
