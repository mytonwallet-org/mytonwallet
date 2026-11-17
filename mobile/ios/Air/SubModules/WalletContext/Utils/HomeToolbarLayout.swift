import CoreGraphics

/// Where the home toolbar's buttons stand around its search field, along the toolbar's axis from its leading end.
///
/// The buttons before the field form one group and the buttons after it another. A group with a shared background
/// is one capsule, in which the buttons touch.
public struct HomeToolbarLayout: Equatable, Sendable {
    public struct Slot: Equatable, Sendable {
        public var item: HomeToolbarItem
        public var isBeforeField: Bool
        /// The distance from the toolbar's leading end for a button before the field, and from its trailing end to
        /// the button's far edge for a button after it
        public var offset: CGFloat
    }

    public static let buttonSize: CGFloat = 48
    public static let buttonGap: CGFloat = 8
    public static let fieldGap: CGFloat = 12
    /// The field's width below which the toolbar takes no more buttons
    public static let minimumFieldWidth: CGFloat = 96
    /// The field's width below which a toolbar leaves out buttons it was given on a wider screen
    public static let minimumShownFieldWidth: CGFloat = 64

    public private(set) var slots: [Slot] = []
    /// The space the buttons before the field take, with their gap to the field
    public private(set) var fieldLeadingInset: CGFloat = 0
    public private(set) var fieldTrailingInset: CGFloat = 0

    /// - Parameter items: The shown items in order, the search field among them
    public init(items: [HomeToolbarItem], sharesBackground: Bool) {
        let fieldIndex = items.firstIndex(of: .search) ?? 0
        let before = Array(items[..<fieldIndex])
        let after = Array(items[fieldIndex...].dropFirst())
        let stride = Self.buttonSize + (sharesBackground ? 0 : Self.buttonGap)
        for (index, item) in before.enumerated() {
            slots.append(Slot(item: item, isBeforeField: true, offset: CGFloat(index) * stride))
        }
        for (index, item) in after.enumerated() {
            slots.append(Slot(item: item, isBeforeField: false, offset: CGFloat(after.count - 1 - index) * stride))
        }
        fieldLeadingInset = Self.getGroupSpan(count: before.count, stride: stride)
        fieldTrailingInset = Self.getGroupSpan(count: after.count, stride: stride)
    }

    public func slot(for item: HomeToolbarItem) -> Slot? {
        slots.first { $0.item == item }
    }

    /// The length along the axis that the buttons take, leaving the rest to the field
    public var buttonsSpan: CGFloat { fieldLeadingInset + fieldTrailingInset }

    /// The leading offset of `slot` in a toolbar `length` long
    public func getStart(of slot: Slot, length: CGFloat) -> CGFloat {
        slot.isBeforeField ? slot.offset : length - slot.offset - Self.buttonSize
    }

    /// Whether a toolbar `length` long still has a usable search field with `item` shown too
    public static func canHold(
        _ item: HomeToolbarItem,
        in configuration: HomeToolbarConfiguration,
        length: CGFloat
    ) -> Bool {
        if configuration.isShown(item) { return true }
        var configuration = configuration
        configuration.hiddenItems.remove(item)
        let layout = HomeToolbarLayout(items: configuration.visibleItems, sharesBackground: configuration.sharesBackground)
        return length - layout.buttonsSpan >= minimumFieldWidth
    }

    /// `items` less the buttons that would leave the search field too little room in a toolbar `length` long. The
    /// buttons last in order give way first; the actions button always stays.
    public static func getFittingItems(
        _ items: [HomeToolbarItem],
        sharesBackground: Bool,
        length: CGFloat
    ) -> [HomeToolbarItem] {
        var items = items
        while HomeToolbarLayout(items: items, sharesBackground: sharesBackground).buttonsSpan > length - minimumShownFieldWidth,
              let index = items.lastIndex(where: \.isHideable) {
            items.remove(at: index)
        }
        return items
    }

    /// `order` with `item` moved to the place whose slot center is nearest to `position`, a distance from the
    /// toolbar's leading end. `shownItems` are the items that take space, `item` among them.
    public static func getOrder(
        moving item: HomeToolbarItem,
        in order: [HomeToolbarItem],
        shownItems: Set<HomeToolbarItem>,
        sharesBackground: Bool,
        toward position: CGFloat,
        length: CGFloat
    ) -> [HomeToolbarItem] {
        let others = order.filter { $0 != item }
        var bestOrder = order
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in 0...others.count {
            var candidate = others
            candidate.insert(item, at: index)
            let layout = HomeToolbarLayout(
                items: candidate.filter(shownItems.contains),
                sharesBackground: sharesBackground
            )
            let center: CGFloat
            if item == .search {
                center = (layout.fieldLeadingInset + length - layout.fieldTrailingInset) / 2
            } else if let slot = layout.slot(for: item) {
                center = layout.getStart(of: slot, length: length) + buttonSize / 2
            } else {
                continue
            }
            let distance = abs(center - position)
            // Hidden items between two shown ones give several orders the same look: the current one wins
            if distance < bestDistance || (distance == bestDistance && candidate == order) {
                bestDistance = distance
                bestOrder = candidate
            }
        }
        return bestOrder
    }

    private static func getGroupSpan(count: Int, stride: CGFloat) -> CGFloat {
        count == 0 ? 0 : CGFloat(count - 1) * stride + buttonSize + fieldGap
    }
}
