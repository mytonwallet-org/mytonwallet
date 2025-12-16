
import UIKit
import SwiftUI
import Perception

let MENU_EDGE_PADDING: CGFloat = 4
private let distanceFromAnchor: CGFloat = 8

@Perceptible
@MainActor public final class MenuContext: Sendable {
    
    @PerceptionIgnored
    public var sourceView: UIView? = nil
    @PerceptionIgnored
    public var sourceFrame: CGRect = .zero
    @PerceptionIgnored
    var anchor: Alignment = .bottom
    
    var locations: [String: CGRect] = [:]
    var currentLocation: CGPoint?
    var currentItem: String?
    public var menuShown: Bool = false
    var submenuId = "0"
    var visibleSubmenus: Set<String> = []
    
    @PerceptionIgnored
    public var minWidth: CGFloat? = 180.0
    @PerceptionIgnored
    public var maxWidth: CGFloat? = 280.0
    @PerceptionIgnored
    public var verticalOffset: CGFloat = 0
    
    @PerceptionIgnored
    public var makeConfig: () -> MenuConfig = { MenuConfig(menuItems: []) }
    @PerceptionIgnored
    public var makeSubmenuConfig: (() -> MenuConfig)?
    
    @PerceptionIgnored
    var actions: [String: () -> ()] = [:]
    
    @PerceptionIgnored
    public var onAppear: (() -> ())?
    @PerceptionIgnored
    public var onDismiss: (() -> ())?
    
    public init() {}
    
    func update(location: CGPoint) {
        currentLocation = location
        let previousItem = currentItem
        for (id, frame) in locations {
            if id.hasPrefix(submenuId) && frame.contains(location) {
                if id != currentItem {
                    currentItem = id
                    // Only play haptic when changing FROM one item to another (not on initial touch)
                    if previousItem != nil {
                        Haptics.play(.selection)
                    }
                }
                return
            }
        }
        if currentItem != nil {
            currentItem = nil
            Haptics.play(.selection)
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
