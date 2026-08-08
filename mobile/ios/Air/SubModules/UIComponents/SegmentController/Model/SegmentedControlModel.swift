
import SwiftUI
import UIKit
import WalletContext
import Perception

public enum SegmentedControlStyle {
    case regular
    case colorHeader
    case header
    case rootHeader
    case compactRootHeader
}

struct SegmentedControlConstants {
    var spacing: CGFloat = 8
    var height: CGFloat = 24
    var topInset: CGFloat = 9
    var innerPadding: CGFloat = 10
    let accessoryWidth: CGFloat = 9.333
    var backgroundPadding: CGFloat = 0
    var fullHeight: CGFloat { height + topInset }
    var fullHeightWithBackground: CGFloat { fullHeight + backgroundPadding * 2 }
}

struct SegmentedControlItemLayout: Equatable {
    let id: SegmentedControlItem.ID
    let labelFrame: CGRect
    let interactionFrame: CGRect
    let accessoryVisibility: CGFloat
}

@Perceptible @MainActor
public final class SegmentedControlModel {
    
    public internal(set) var items: [SegmentedControlItem]
    public var selection: SegmentedControlSelection?

    var isReordering: Bool = false
    
    @PerceptionIgnored
    let constants: SegmentedControlConstants
    @PerceptionIgnored
    let style: SegmentedControlStyle
    @PerceptionIgnored
    let font: UIFont
    @PerceptionIgnored
    var primaryColor: UIColor
    @PerceptionIgnored
    var secondaryColor: UIColor
    @PerceptionIgnored
    var capsuleColor: UIColor
    
    @PerceptionIgnored
    public var onSelect: (SegmentedControlItem) -> () = { _ in }
    @PerceptionIgnored
    public var onItemsReorder: ([SegmentedControlItem]) async -> () = { _ in }
    
    internal var elementSizes: [String: CGSize] = [:]
    
    init(
        items: [SegmentedControlItem],
        selection: SegmentedControlSelection? = nil,
        primaryColor: UIColor = UIColor.label,
        secondaryColor: UIColor = UIColor.secondaryLabel,
        capsuleColor: UIColor = UIColor.tintColor,
        style: SegmentedControlStyle,
    ) {
        self.items = items
        self.selection = selection
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.capsuleColor = capsuleColor
        
        var constants = SegmentedControlConstants()
        let font: UIFont
        switch style {
        case .regular:
            font = WTypography.uiFont(.supportingEmphasized)
        case .colorHeader, .header:
            font = WTypography.uiFont(.subheadlineEmphasized)
            constants.spacing = 0
            constants.height = 34
            constants.topInset = 0
            constants.innerPadding = 16
            constants.backgroundPadding = 3
        case .rootHeader, .compactRootHeader:
            font = WTypography.uiFont(.subheadlineEmphasized)
            constants.spacing = 0
            constants.height = 36
            constants.topInset = 0
            constants.innerPadding = style == .compactRootHeader ? 13 : 24
            constants.backgroundPadding = 4
        }
        self.constants = constants
        self.style = style
        self.font = font
    }
    
    public func setRawProgress(_ rawProgress: CGFloat) {
        guard rawProgress.isFinite else { return }
        let count = items.count
        guard count >= 2, self.rawProgress != rawProgress else { return }
        let index = min(count - 2, max(0, Int(rawProgress)))
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

    func calculateContentWidth(includeBackground: Bool) -> CGFloat {
        guard items.count > 0 else { return 0 }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var width = items.reduce(CGFloat.zero) { width, item in
            width + (item.title as NSString).size(withAttributes: attrs).width
        }
        if items.contains(where: \.canHaveAccessoryView) {
            width += constants.accessoryWidth
        }
        width += CGFloat(items.count) * 2 * constants.innerPadding
        width += CGFloat(items.count - 1) * constants.spacing
        
        if includeBackground {
            width += 2 * constants.backgroundPadding
        }
        return ceil(width)
    }

    func itemLayouts() -> [SegmentedControlItemLayout]? {
        var x: CGFloat = 0
        var layouts: [SegmentedControlItemLayout] = []
        layouts.reserveCapacity(items.count)

        for item in items {
            guard let size = elementSizes[item.id] else { return nil }
            let accessoryVisibility = item.canHaveAccessoryView
                ? 1 - distanceToItem(itemId: item.id)
                : 0
            let labelFrame = CGRect(x: x, y: 0, width: size.width, height: constants.height)
            let interactionFrame = CGRect(
                x: x,
                y: 0,
                width: size.width + constants.accessoryWidth * accessoryVisibility,
                height: constants.height
            )
            layouts.append(
                SegmentedControlItemLayout(
                    id: item.id,
                    labelFrame: labelFrame,
                    interactionFrame: interactionFrame,
                    accessoryVisibility: accessoryVisibility
                )
            )
            x = interactionFrame.maxX + constants.spacing
        }
        return layouts
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
                x += size.width + constants.spacing
            }
        }
        let x2 = x + w1 + constants.spacing
        if items.first(id: selection.item1)?.shouldShowMenuIconWhenActive == true {
            w1 += constants.accessoryWidth
        }
        if let item2 = selection.item2, items.first(id: item2)?.shouldShowMenuIconWhenActive == true {
            w2 += constants.accessoryWidth
        }
        let frame1 = CGRect(x: x, y: 0, width: w1, height: constants.height)
        let frame2 = CGRect(x: x2, y: 0, width: w2, height: constants.height)
        let progress = (selection.progress ?? 0.0).clamped(to: 0...1)
        return interpolate(from: frame1, to: frame2, progress: progress)
    }
    
    func setSize(itemId: String, size: CGSize) {
        if elementSizes[itemId] != size {
            elementSizes[itemId] = size
        }
    }
}
