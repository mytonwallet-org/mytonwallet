
import SwiftUI
import UIKit
import WalletContext

public struct SegmentedControlItem: Identifiable, Equatable, Hashable {
    
    public var id: String
    var title: String
    var menuContext: MenuContext?
    var hidesMenuIcon: Bool
    var isDeletable: Bool
    var viewController: WSegmentedControllerContent
        
    public init(id: String, title: String, menuContext: MenuContext? = nil, hidesMenuIcon: Bool = false, isDeletable: Bool = true, viewController: WSegmentedControllerContent) {
        self.id = id
        self.title = title
        self.menuContext = menuContext
        self.hidesMenuIcon = hidesMenuIcon
        self.isDeletable = isDeletable
        self.viewController = viewController
    }
    
    public static func ==(lhs: SegmentedControlItem, rhs: SegmentedControlItem) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
    }
    
    var shouldShowMenuIconWhenActive: Bool {
        menuContext != nil && !hidesMenuIcon
    }
}
