
import UIKit
import SwiftUI

// workaround for release build bug (Xcode 16.4) - try to remove in later versions
extension CGRect: @retroactive @unchecked Sendable {}

public struct SelectableMenuItem<Content: View>: View, @unchecked Sendable {
    
    var id: String
    var action: @Sendable () -> ()
    @ViewBuilder var content: () -> Content
    
    @EnvironmentObject private var menuContext: MenuContext
    
    var isSelected: Bool { menuContext.currentItem == id }
    
    public init(id: String, action: @MainActor @escaping () -> Void, content: @escaping () -> Content) {
        self.id = id
        self.action = action
        self.content = content
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 11.5)
            Spacer(minLength: 0)
        }
        .background {
            if isSelected {
                Color.secondary.opacity(0.2)
            }
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { menuContext.locations[id] = $0 })
        .onAppear {
            menuContext.registerAction(id: id, action: action)
        }

    }
}


public struct WMenuButton: View {
    
    var id: String
    var title: String
    var leadingIcon: String?
    var trailingIcon: String?
    var action: () -> ()
    
    public init(id: String, title: String, leadingIcon: String? = nil, trailingIcon: String? = nil, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.action = action
    }
    
    
    public var body: some View {
        SelectableMenuItem(id: id, action: action) {
            HStack {
                HStack(spacing: 10) {
                    if let leadingIcon {
                        Image.airBundle(leadingIcon)
                            .padding(.vertical, -8)
                    }
                    Text(title)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let trailingIcon {
                    Image.airBundle(trailingIcon)
                        .padding(.vertical, -8)
                }
            }
        }
    }
}
