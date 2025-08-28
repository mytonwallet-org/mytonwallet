
import SwiftUI
import UIKit
import WalletContext

public struct SegmentedControlItem: Identifiable, Equatable {
    
    public var index: Int
    public var id: String
    public var content: AnyView
    
    public init(index: Int, id: String, content: AnyView) {
        self.index = index
        self.id = id
        self.content = content
    }
    
    public static func == (lhs: SegmentedControlItem, rhs: SegmentedControlItem) -> Bool {
        lhs.id == rhs.id
    }
}
