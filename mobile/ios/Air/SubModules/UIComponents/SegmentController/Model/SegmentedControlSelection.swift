
import SwiftUI
import UIKit
import WalletContext

public struct SegmentedControlSelection: Equatable, Hashable {
    public var item1: SegmentedControlItem.ID
    public var item2: SegmentedControlItem.ID?
    public var progress: CGFloat?
    
    public init(item1: SegmentedControlItem.ID, item2: SegmentedControlItem.ID? = nil, progress: CGFloat? = nil) {
        self.item1 = item1
        self.item2 = item2
        self.progress = progress
    }
    
    var effectiveSelectedItemID: SegmentedControlItem.ID {
        if let item2, let progress, progress > 0.5 {
            return item2
        }
        return item1
    }
}
