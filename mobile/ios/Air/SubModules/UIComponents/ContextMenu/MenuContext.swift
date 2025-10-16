
import UIKit
import SwiftUI

let MENU_EDGE_PADDING: CGFloat = 4
private let distanceFromAnchor: CGFloat = 8

public final class MenuContext: ObservableObject, @unchecked Sendable {
    
    @Published public var sourceView: UIView? = nil
    @Published public var sourceFrame: CGRect = .zero
    @Published var anchor: Alignment = .bottom
    @Published var locations: [String: CGRect] = [:]
    @Published var currentLocation: CGPoint?
    @Published var currentItem: String?
    @Published public var menuShown: Bool = false
    @Published var submenuId = "0"
    @Published var visibleSubmenus: Set<String> = []
    @Published public var minWidth: CGFloat? = 180.0
    @Published public var maxWidth: CGFloat? = 280.0
    @Published public var verticalOffset: CGFloat = 0
    
    public var makeConfig: () -> MenuConfig = { MenuConfig(menuItems: []) }
    public var makeSubmenuConfig: (() -> MenuConfig)?
    
    var actions: [String: () -> ()] = [:]
    
    public var onAppear: (() -> ())?
    public var onDismiss: (() -> ())?
    
    public init() {}
    
    func update(location: CGPoint) {
        currentLocation = location
        for (id, frame) in locations {
            if id.hasPrefix(submenuId) && frame.contains(location) {
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
    
    @MainActor public func present() {
        if !menuShown {
            if let view = getMenuLayerView() {
                view.showMenu(menuContext: self)
            }
        }
    }
    
    @MainActor public func dismiss() {
        getMenuLayerView()?.dismissMenu()
    }
    
    var showBelowSource: Bool {
        sourceFrame.maxY < 700
    }
    
    var source: CGPoint {
        CGPoint(x: sourceFrame.midX, y: showBelowSource ? sourceFrame.maxY + distanceFromAnchor + verticalOffset : sourceFrame.minY - distanceFromAnchor + verticalOffset)
    }
    
    var sourceX: CGFloat {
        sourceFrame.midX - MENU_EDGE_PADDING
    }
    
    var showShadow: Bool {
        sourceView == nil
    }
    
    public func switchTo(submenuId: String) {
        visibleSubmenus = [self.submenuId, submenuId]
        withAnimation(.smooth(duration: 0.3)) {
            self.submenuId = submenuId
            if currentItem?.hasPrefix(submenuId) == true {
                currentItem = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.submenuId == submenuId {
                self.visibleSubmenus = []
            }
        }
    }
}
