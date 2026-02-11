
import SwiftUI
import UIKit
import WalletContext
import Perception

@Perceptible
public final class SegmentedControlModel {
    
    public internal(set) var items: [SegmentedControlItem]
    public var selection: SegmentedControlSelection?

    public var isReordering: Bool = false
    public let font: Font;
    
    @PerceptionIgnored
    public let uikitFont = UIFont.systemFont(ofSize: 14, weight: .medium)

    @PerceptionIgnored
    public var primaryColor: UIColor
    @PerceptionIgnored
    public var secondaryColor: UIColor
    @PerceptionIgnored
    public var capsuleColor: UIColor
    
    @PerceptionIgnored
    public var onSelect: (SegmentedControlItem) -> () = { _ in }
    @PerceptionIgnored
    public var onItemsReorder: ([SegmentedControlItem]) async -> () = { _ in }
    
    internal var elementSizes: [String: CGSize] = [:]
    internal var isScrollingRequired: Bool = false
    
    public init(
        items: [SegmentedControlItem],
        selection: SegmentedControlSelection? = nil,
        primaryColor: UIColor = UIColor.label,
        secondaryColor: UIColor = UIColor.secondaryLabel,
        capsuleColor: UIColor = UIColor.tintColor
    ) {
        self.items = items
        self.selection = selection
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.capsuleColor = capsuleColor
        self.font = Font(uikitFont)
        updateIfScrollingRequired()
    }
    
    public func setRawProgress(_ rawProgress: CGFloat) {
        let count = items.count
        guard count >= 2, self.rawProgress != rawProgress else { return }
        let index = min(count - 2, Int(rawProgress))
        let progress = rawProgress - CGFloat(index)
        let item1 = items[index]
        let item2 = items[index + 1]
        selection = .init(item1: item1.id, item2: item2.id, progress: progress)
    }
    
    public var rawProgress: CGFloat? {
        if let selection, let index = getItemIndexById(itemId: selection.item1) {
            return CGFloat(index) + (selection.progress ?? 0.0)
        }
        return nil
    }
    
    public var selectedItem: SegmentedControlItem? {
        guard !items.isEmpty, let rawProgress else { return nil }
        let count = items.count
        let idx = min(count - 1, max(0, Int(rawProgress + 0.5)))
        return items[idx]
    }
    
    public func setItems(_ newItems: [SegmentedControlItem]) {
        let oldSelection = self.selection
        self.items = newItems
        if !items.isEmpty {
            // try to keep selection
            if let oldSelection, nil != getItemIndexById(itemId: oldSelection.effectiveSelectedItemID) {
                self.selection = .init(item1: oldSelection.effectiveSelectedItemID)                
            } else {
                self.selection = .init(item1: newItems[0].id)
            }
        }
        updateIfScrollingRequired()
    }
    
    public func distanceToItem(itemId: String) -> CGFloat {
        guard let rawProgress, let index = getItemIndexById(itemId: itemId) else { return 1 }
        return min(1, abs(CGFloat(index) - rawProgress))
    }

    public func directionalDistanceToItem(itemId: String) -> CGFloat {
        guard let rawProgress, let index = getItemIndexById(itemId: itemId) else { return 1 }
        return clamp(CGFloat(index) - rawProgress, to: -1...1)
    }

    // MARK: Reordering
    
    public func startReordering() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.smooth(duration: 0.15)) {
                self.isReordering = true
            }
        }
    }
    
    public func stopReordering() {
        withAnimation(.smooth(duration: 0.15)) {
            self.isReordering = false
        }
    }
        
    internal func requestItemsReorder(_ items: [SegmentedControlItem]) {
        // This is just request to apply new item ordering. No self.items is affected here
        // the delegate will perform all the self.items management on its own
        Task {
            await onItemsReorder(items)
        }
    }
    
    // MARK: Internals
    
    private func updateIfScrollingRequired() {
        self.isScrollingRequired = _measureIsScrollingRequired()
    }
    
    func _measureIsScrollingRequired() -> Bool {
        guard items.count > 0 else {
            return false
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: uikitFont]
        var width: CGFloat = items.map { item in
            (item.title as NSString).size(withAttributes: attrs).width
        }.reduce(0, +)
        width += CGFloat(items.count) * 2 * SegmentedControlConstants.innerPadding
        width += CGFloat(items.count - 1) * SegmentedControlConstants.spacing
        width += SegmentedControlConstants.accessoryWidth
        return width > screenWidth - 32.0
    }
    
    func getItemById(itemId: String) -> SegmentedControlItem? {
        items.first(where: { $0.id == itemId })
    }
    
    public func getItemIndexById(itemId: String) -> Int? {
        items.firstIndex(where: { $0.id == itemId })
    }
    
    var selectionFrame: CGRect? {
        guard let selection else { return nil }
        let items = self.items
        let itemIds = items.map(\.id)
        let elementSizes = self.elementSizes
        
        var x: CGFloat = 0
        var w1: CGFloat = 0
        var w2: CGFloat = 0
        for itemId in itemIds {
            guard let size = elementSizes[itemId] else { return nil }
            if itemId == selection.item1 {
                w1 = size.width
                if selection.item2 == nil {
                    break
                }
            } else if itemId == selection.item2 {
                w2 = size.width
                break
            } else {
                x += size.width + SegmentedControlConstants.spacing
            }
        }
        let x2 = x + w1 + SegmentedControlConstants.spacing
        if items.first(id: selection.item1)?.shouldShowMenuIconWhenActive == true {
            w1 += SegmentedControlConstants.accessoryWidth
        }
        if let item2 = selection.item2, items.first(id: item2)?.shouldShowMenuIconWhenActive == true {
            w2 += SegmentedControlConstants.accessoryWidth
        }
        let frame1 = CGRect(x: x, y: 0, width: w1, height: SegmentedControlConstants.height)
        let frame2 = CGRect(x: x2, y: 0, width: w2, height: SegmentedControlConstants.height)
        let progress = selection.progress ?? 0
        return interpolate(from: frame1, to: frame2, progress: progress)
    }
    
    func setSize(itemId: String, size: CGSize) {
        if elementSizes[itemId] != size {
            elementSizes[itemId] = size
        }
    }
}
