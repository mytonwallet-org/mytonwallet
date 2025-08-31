
import UIKit
import SwiftUI


public final class MenuContext: ObservableObject, @unchecked Sendable {
    
    @Published public var sourceView: UIView? = nil
    @Published var sourceFrame: CGRect = .zero
    @Published var anchor: Alignment = .bottom
    @Published var locations: [String: CGRect] = [:]
    @Published var currentLocation: CGPoint?
    @Published var currentItem: String?
    @Published public var menuShown: Bool = false
    @Published var prefix = ""
    
    var makeView: () -> AnyView
    
    var actions: [String: () -> ()] = [:]
    
    public var onAppear: (() -> ())?
    public var onDismiss: (() -> ())?
    
    public init() {
        self.makeView = {
            AnyView(EmptyView())
        }
    }
    
    public init<MenuContent: View>(@ViewBuilder content: @escaping () -> MenuContent) {
        self.makeView = {
            AnyView(content())
        }
    }
    
    public func setMenu<MenuContent: View>(@ViewBuilder content: @escaping () -> MenuContent) {
        self.makeView = {
            AnyView(content())
        }
    }
    
    func update(location: CGPoint) {
        currentLocation = location
        for (id, frame) in locations {
            if id.hasPrefix(prefix) && frame.contains(location) {
                if id != currentItem {
                    currentItem = id
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                return
            }
        }
        if currentItem != nil {
            currentItem = nil
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
    
    func registerAction(id: String, action: @escaping () -> ()) {
        actions[id] = action
    }
    
    func triggerCurrentAction() {
        if let currentItem, let action = actions[currentItem] {
            action()
        }
        deselectItem()
    }
    
    func deselectItem() {
        withAnimation(.spring) {
            currentLocation = .zero
            currentItem = nil
        }
    }
    
    @MainActor public func dismiss() {
        getMenuLayerView()?.dismissMenu()
    }
    
    func setPrefix(_ prefix: String) {
        self.prefix = prefix
        if currentItem?.hasPrefix(prefix) == true {
            currentItem = nil
        }
    }
}
