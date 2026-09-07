import UIComponents
import UIKit
import WalletContext

public typealias UniversalSearchIconConfiguration = IconView.Configuration

@MainActor
public struct UniversalSearchIcon {
    private let configureIconView: (IconView) -> Void

    public init(_ configuration: UniversalSearchIconConfiguration) {
        self.configureIconView = { iconView in
            iconView.config(with: configuration)
        }
    }

    public init(configure: @escaping (IconView) -> Void) {
        self.configureIconView = configure
    }

    func configure(_ iconView: IconView) {
        configureIconView(iconView)
    }
}

@MainActor
public struct UniversalSearchChatResult {
    public let title: String
    public let subtitle: String

    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}

@MainActor
public struct UniversalSearchTokenResult {
    public let icon: UniversalSearchIcon
    public let title: String
    public let badge: String?
    public let price: String
    public let amount: String?
    public let balanceValue: String?

    public init(
        icon: UniversalSearchIconConfiguration,
        title: String,
        badge: String? = nil,
        price: String,
        amount: String? = nil,
        balanceValue: String? = nil
    ) {
        self.icon = UniversalSearchIcon(icon)
        self.title = title
        self.badge = badge
        self.price = price
        self.amount = amount
        self.balanceValue = balanceValue
    }

    public init(
        icon: UniversalSearchIcon,
        title: String,
        badge: String? = nil,
        price: String,
        amount: String? = nil,
        balanceValue: String? = nil
    ) {
        self.icon = icon
        self.title = title
        self.badge = badge
        self.price = price
        self.amount = amount
        self.balanceValue = balanceValue
    }
}

@MainActor
public struct UniversalSearchCollectibleResult {
    public let icon: UniversalSearchIcon
    public let title: String
    public let subtitle: String

    public init(icon: UniversalSearchIconConfiguration, title: String, subtitle: String) {
        self.icon = UniversalSearchIcon(icon)
        self.title = title
        self.subtitle = subtitle
    }

    public init(icon: UniversalSearchIcon, title: String, subtitle: String) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }
}

@MainActor
public struct UniversalSearchCollectionResult {
    public let title: String
    public let subtitle: String

    public init(title: String, subtitle: String = lang("Collection")) {
        self.title = title
        self.subtitle = subtitle
    }
}

@MainActor
public struct UniversalSearchAppResult {
    public let icon: UniversalSearchIcon
    public let title: String
    public let subtitle: String
    public let showsTelegramBadge: Bool
    public let actionTitle: String?

    public init(
        icon: UniversalSearchIconConfiguration,
        title: String,
        subtitle: String,
        showsTelegramBadge: Bool = false,
        actionTitle: String? = lang("Open")
    ) {
        self.icon = UniversalSearchIcon(icon)
        self.title = title
        self.subtitle = subtitle
        self.showsTelegramBadge = showsTelegramBadge
        self.actionTitle = actionTitle
    }

    public init(
        icon: UniversalSearchIcon,
        title: String,
        subtitle: String,
        showsTelegramBadge: Bool = false,
        actionTitle: String? = lang("Open")
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.showsTelegramBadge = showsTelegramBadge
        self.actionTitle = actionTitle
    }
}

@MainActor
public struct UniversalSearchWalletResult {
    public let icon: UniversalSearchIcon
    public let title: String
    public let subtitle: String

    public init(icon: UniversalSearchIconConfiguration, title: String, subtitle: String) {
        self.icon = UniversalSearchIcon(icon)
        self.title = title
        self.subtitle = subtitle
    }

    public init(icon: UniversalSearchIcon, title: String, subtitle: String) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }
}

@MainActor
public struct UniversalSearchHistoryResult {
    public let title: String
    public let subtitle: String

    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}

@MainActor
public struct UniversalSearchSiteResult {
    public let title: String
    public let subtitle: String

    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}

@MainActor
public struct UniversalSearchPrompt {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

@MainActor
public struct UniversalSearchShortcutResult {
    public let icon: UniversalSearchIcon
    public let title: String
    public let subtitle: String?

    public init(icon: UniversalSearchIcon, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }
}

@MainActor
public struct UniversalSearchItem {
    public enum Content {
        case chat(UniversalSearchChatResult)
        case token(UniversalSearchTokenResult)
        case collectible(UniversalSearchCollectibleResult)
        case collection(UniversalSearchCollectionResult)
        case app(UniversalSearchAppResult)
        case wallet(UniversalSearchWalletResult)
        case shortcut(UniversalSearchShortcutResult)
        case askAgent(query: String)
        case recentSearch(UniversalSearchHistoryResult)
        case site(UniversalSearchSiteResult)
        case openWebsite(UniversalSearchSiteResult)
        case google(query: String)
        case prompt(UniversalSearchPrompt)
    }

    public let id: String
    public let content: Content

    public init(id: String, content: Content) {
        self.id = id
        self.content = content
    }
}

@MainActor
public struct UniversalSearchSection {
    public enum Layout {
        case list
        case paged(rowsPerPage: Int)
        case promptPages(rowsPerPage: Int)
    }

    public enum HeaderAccessory {
        public enum ToggleSelection: Int {
            case primary
            case secondary
        }

        case toggle(primary: String, secondary: String, selected: ToggleSelection)
        case text(String)
    }

    public let id: String
    public let title: String
    public let headerAccessory: HeaderAccessory?
    public let layout: Layout
    /// The uniform height used by every item in this section. When omitted, the
    /// height is inferred from the first item, so mixed item kinds must share a height.
    public let rowHeight: CGFloat?
    public let showsHeader: Bool
    public let showsLeadingSeparator: Bool
    public let items: [UniversalSearchItem]

    public init(
        id: String,
        title: String,
        headerAccessory: HeaderAccessory? = nil,
        layout: Layout = .list,
        rowHeight: CGFloat? = nil,
        showsHeader: Bool = true,
        showsLeadingSeparator: Bool = true,
        items: [UniversalSearchItem]
    ) {
        self.id = id
        self.title = title
        self.headerAccessory = headerAccessory
        self.layout = layout
        self.rowHeight = rowHeight
        self.showsHeader = showsHeader
        self.showsLeadingSeparator = showsLeadingSeparator
        self.items = items
    }
}
