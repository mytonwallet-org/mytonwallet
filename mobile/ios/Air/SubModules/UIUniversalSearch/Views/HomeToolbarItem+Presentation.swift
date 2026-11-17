import UIComponents
import UIKit
import WalletContext

/// A drag that is rearranging the home toolbar
public struct HomeToolbarEdit: Equatable, Sendable {
    /// The dragged item, whose button stays empty
    public var item: HomeToolbarItem
    public var order: [HomeToolbarItem]
    /// Whether the toolbar keeps the place where the item would drop
    public var reservesSlot: Bool

    public init(item: HomeToolbarItem, order: [HomeToolbarItem], reservesSlot: Bool) {
        self.item = item
        self.order = order
        self.reservesSlot = reservesSlot
    }
}

public extension HomeToolbarItem {
    var title: String {
        switch self {
        case .search: lang("Search")
        case .accounts: lang("Accounts")
        case .scan: lang("Scan QR")
        case .actions: lang("Actions")
        case .buy: lang("Buy")
        case .fund: lang("Fund")
        case .trade: lang("Trade")
        case .sell: lang("Sell")
        case .send: lang("Send")
        case .earn: lang("Earn")
        }
    }

    var toolbarAccessibilityIdentifier: String {
        self == .scan ? "home_scan_qr_button" : "home_toolbar_\(rawValue)_button"
    }

    /// The glyph of the item's toolbar button, drawn with the stroke of the toolbar's plus. The accounts button shows
    /// the wallet's avatar instead.
    @MainActor
    func makeToolbarImage() -> UIImage? {
        switch self {
        case .accounts:
            nil
        case .search:
            UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        case .scan:
            UIImage(systemName: "viewfinder", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        case .actions:
            UIImage.airBundle("UniversalSearchPlus").withRenderingMode(.alwaysTemplate)
        case .buy: UIImage.airBundle("ToolbarBuy")
        case .fund: UIImage.airBundle("ToolbarFund")
        case .trade: UIImage.airBundle("ToolbarTrade")
        case .sell: UIImage.airBundle("ToolbarSell")
        case .send: UIImage.airBundle("ToolbarSend")
        case .earn: UIImage.airBundle("ToolbarEarn")
        }
    }
}
