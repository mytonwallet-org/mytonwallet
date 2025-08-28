
import SwiftUI
import UIKit
import WalletContext


public final class SegmentedControlModel: ObservableObject {
    
    @Published public var items: [SegmentedControlItem]
    @Published public var selection: SegmentedControlSelection?
    @Published public var font: Font
    @Published public var primaryColor: UIColor
    @Published public var secondaryColor: UIColor
    @Published public var capsuleColor: UIColor
    @Published public var isReordering: Bool = false
    
    public var onSelect: (SegmentedControlItem) -> () = { _ in }
    public var onItemsReordered: ([SegmentedControlItem]) async -> () = { _ in }
    
    public init(
        items: [SegmentedControlItem],
        selection: SegmentedControlSelection? = nil,
        font: Font = .system(size: 14, weight: .medium),
        primaryColor: UIColor = UIColor.label,
        secondaryColor: UIColor = UIColor.secondaryLabel,
        capsuleColor: UIColor = UIColor.tintColor
    ) {
        self.items = items
        self.selection = selection
        self.font = font
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.capsuleColor = capsuleColor
    }
    
    public func setRawProgress(_ rawProgress: CGFloat) {
        let count = items.count
        guard count >= 2 else { return }
        let index = min(count - 2, Int(rawProgress))
        let progress = rawProgress - CGFloat(index)
        let item1 = items[index]
        let item2 = items[index + 1]
        selection = .init(item1: item1.id, item2: item2.id, progress: progress)
    }
    
    public var rawProgress: CGFloat? {
        if let selection, let item1 = getItemById(itemId: selection.item1) {
            return CGFloat(item1.index) + (selection.progress ?? 0.0)
        }
        return nil
    }
    
    public var selectedItem: SegmentedControlItem? {
        guard !items.isEmpty, let rawProgress else { return nil }
        let count = items.count
        let idx = min(count - 1, max(0, Int(rawProgress + 0.5)))
        return items[idx]
    }
    
    func distanceToItem(itemId: String) -> CGFloat {
        guard let rawProgress, let item = getItemById(itemId: itemId) else { return .infinity }
        return abs(CGFloat(item.index) - rawProgress)
    }
    
    func getItemById(itemId: String) -> SegmentedControlItem? {
        items.first(where: { $0.id == itemId })
    }
    
    public func setItems(_ newItems: [SegmentedControlItem]) {
        self.items = newItems
        if !items.isEmpty {
            self.selection = .init(item1: newItems[0].id)
        }
    }
    
    public func startReordering() {
        isReordering = true
    }
    
    public func stopReordering() {
        isReordering = false
        Task { await onItemsReordered(self.items) }
    }
}
