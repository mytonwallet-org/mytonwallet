
import ContextMenuKit
import SwiftUI
import UIKit
import WalletContext

public struct SegmentedControlItem: Identifiable, Equatable, Hashable, Sendable {
    
    public let id: String
    var title: String
    var contextMenuProvider: SegmentedControlContextMenuProvider?
    var hidesMenuIcon: Bool
    var isDeletable: Bool
    public let viewController: WSegmentedControllerContent
        
    public init(
        id: String,
        title: String,
        contextMenuProvider: SegmentedControlContextMenuProvider? = nil,
        hidesMenuIcon: Bool = false,
        isDeletable: Bool = true,
        viewController: WSegmentedControllerContent
    ) {
        self.id = id
        self.title = title
        self.contextMenuProvider = contextMenuProvider
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
        contextMenuProvider != nil && !hidesMenuIcon
    }
    
    var canHaveAccessoryView: Bool {
        shouldShowMenuIconWhenActive
    }
}
