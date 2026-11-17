import Foundation

public enum HomeToolbarItem: String, CaseIterable, Hashable, Sendable {
    case search
    case accounts
    case scan
    case actions
    case buy
    case fund
    case trade
    case sell
    case send
    case earn

    /// The items of the actions menu, in its default order
    public static let actionItems: [HomeToolbarItem] = [.buy, .fund, .trade, .sell, .send, .earn, .scan]

    public var isHideable: Bool { self != .search && self != .actions }
    public var isAction: Bool { Self.actionItems.contains(self) }
}

/// Hidden items keep their place in `order`
public struct HomeToolbarConfiguration: Equatable, Sendable {
    public var order: [HomeToolbarItem]
    public var hiddenItems: Set<HomeToolbarItem>
    public var sharesBackground: Bool
    public var actionsOrder: [HomeToolbarItem]
    /// The top bar side of the account button while it is off the toolbar
    public var isAccountsAtStart: Bool

    public static let defaultHiddenItems = Set(HomeToolbarItem.allCases.filter {
        $0 == .accounts || ($0.isAction && $0 != .scan)
    })

    public init(
        order: [HomeToolbarItem] = HomeToolbarItem.allCases,
        hiddenItems: Set<HomeToolbarItem> = HomeToolbarConfiguration.defaultHiddenItems,
        sharesBackground: Bool = true,
        actionsOrder: [HomeToolbarItem] = HomeToolbarItem.actionItems,
        isAccountsAtStart: Bool = false
    ) {
        let order = order.removingDuplicates()
        let missing = HomeToolbarItem.allCases.filter { !order.contains($0) }
        let actionsOrder = actionsOrder.filter(\.isAction).removingDuplicates()
        self.order = order + missing
        self.hiddenItems = hiddenItems.filter(\.isHideable)
        self.sharesBackground = sharesBackground
        self.actionsOrder = actionsOrder + HomeToolbarItem.actionItems.filter { !actionsOrder.contains($0) }
        self.isAccountsAtStart = isAccountsAtStart
    }

    public init(showsAccounts: Bool, showsScan: Bool = true, sharesBackground: Bool = true) {
        self.init(sharesBackground: sharesBackground)
        setShown(showsAccounts, .accounts)
        setShown(showsScan, .scan)
    }

    public var showsAccounts: Bool { isShown(.accounts) }
    public var showsScan: Bool { isShown(.scan) }

    /// The shown items in toolbar order
    public var visibleItems: [HomeToolbarItem] { order.filter(isShown) }

    public func isShown(_ item: HomeToolbarItem) -> Bool { !hiddenItems.contains(item) }

    public mutating func setShown(_ isShown: Bool, _ item: HomeToolbarItem) {
        guard item.isHideable else { return }
        if isShown { hiddenItems.remove(item) } else { hiddenItems.insert(item) }
    }

    /// The configuration with `items` hidden as well, for an account that cannot use them
    public func hiding(_ items: Set<HomeToolbarItem>) -> HomeToolbarConfiguration {
        var configuration = self
        configuration.hiddenItems.formUnion(items.filter(\.isHideable))
        return configuration
    }
}

public enum ToolbarSettings {
    public static let configurationKey = "toolbarConfiguration"
    public static let accountsKey = "toolbarShowsAccounts"
    public static let scanKey = "toolbarShowsScan"
    public static let sharedBackgroundKey = "toolbarSharesBackground"
    public static let didChangeNotification = Notification.Name("ToolbarSettingsDidChange")

    private static let orderField = "order"
    private static let hiddenField = "hidden"
    private static let sharedBackgroundField = "sharedBackground"
    private static let actionsOrderField = "actionsOrder"
    private static let accountsAtStartField = "accountsAtStart"

    public static func configuration(in defaults: UserDefaults = .standard) -> HomeToolbarConfiguration {
        guard let stored = defaults.dictionary(forKey: configurationKey) else {
            // Installs from before the toolbar could be rearranged keep their three switches
            return HomeToolbarConfiguration(
                showsAccounts: defaults.bool(forKey: accountsKey),
                showsScan: defaults.object(forKey: scanKey) as? Bool ?? true,
                sharesBackground: defaults.object(forKey: sharedBackgroundKey) as? Bool ?? true
            )
        }
        let order = readItems(stored[orderField])
        // Items added since the configuration was stored take their default visibility
        let hiddenItems = Set(readItems(stored[hiddenField])).union(
            HomeToolbarConfiguration.defaultHiddenItems.filter { !order.contains($0) }
        )
        return HomeToolbarConfiguration(
            order: order,
            hiddenItems: hiddenItems,
            sharesBackground: stored[sharedBackgroundField] as? Bool ?? true,
            actionsOrder: readItems(stored[actionsOrderField]),
            isAccountsAtStart: stored[accountsAtStartField] as? Bool ?? false
        )
    }

    /// Stores `configuration` and tells the toolbars to pick it up
    public static func setConfiguration(_ configuration: HomeToolbarConfiguration, in defaults: UserDefaults = .standard) {
        guard configuration != self.configuration(in: defaults) || defaults.dictionary(forKey: configurationKey) == nil else {
            return
        }
        defaults.set([
            orderField: configuration.order.map(\.rawValue),
            hiddenField: configuration.hiddenItems.map(\.rawValue).sorted(),
            sharedBackgroundField: configuration.sharesBackground,
            actionsOrderField: configuration.actionsOrder.map(\.rawValue),
            accountsAtStartField: configuration.isAccountsAtStart,
        ] as [String: Any], forKey: configurationKey)
        notifyDidChange()
    }

    public static func notifyDidChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    private static func readItems(_ value: Any?) -> [HomeToolbarItem] {
        (value as? [String] ?? []).compactMap(HomeToolbarItem.init(rawValue:))
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
