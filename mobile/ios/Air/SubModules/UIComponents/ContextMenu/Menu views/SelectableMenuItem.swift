
import UIKit
import SwiftUI
import Perception

// workaround for release build bug (Xcode 16.4) - try to remove in later versions
extension CGRect: @retroactive @unchecked Sendable {}

public struct SelectableMenuItem<Content: View>: View, @unchecked Sendable {
    
    var id: String
    var action: @Sendable () -> ()
    var dismissOnSelect: Bool
    @ViewBuilder var content: () -> Content
    
    @Environment(MenuContext.self) var menuContext
    
    var isSelected: Bool { menuContext.currentItem == id }
    
    public init(id: String, action: @MainActor @escaping () -> Void, dismissOnSelect: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.action = action
        self.dismissOnSelect = dismissOnSelect
        self.content = content
    }
    
    public var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 0) {
                content()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11.5)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .background {
                if isSelected {
                    Color.secondary.opacity(0.2)
                }
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { menuContext.locations[id] = $0 })
            .onAppear {
                menuContext.registerAction(id: id, action: _action)
            }
        }
    }
    
    func _action() {
        action()
        if dismissOnSelect {
            menuContext.dismiss()
        }
    }
}

public struct WMenuButton: View {
    
    var id: String
    var title: String
    var leadingIcon: IconConfig?
    var trailingIcon: IconConfig?
    var action: () -> ()
    var dismissOnSelect: Bool
    
    public init(id: String, title: String, leadingIcon: IconConfig? = nil, trailingIcon: IconConfig? = nil, action: @escaping () -> Void, dismissOnSelect: Bool = true) {
        self.id = id
        self.title = title
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.action = action
        self.dismissOnSelect = dismissOnSelect
    }
    
    public var body: some View {
        SelectableMenuItem(id: id, action: action, dismissOnSelect: dismissOnSelect) {
            HStack {
                HStack(spacing: 10) {
                    if let leadingIcon {
                        leadingIcon
                    }
                    Text(title)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let trailingIcon {
                    trailingIcon
                }
            }
        }
    }
}
