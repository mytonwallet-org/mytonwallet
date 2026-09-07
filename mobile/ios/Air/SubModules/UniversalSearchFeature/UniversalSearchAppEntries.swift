import Foundation
import UniversalSearchCore
import WalletContext
import WalletCore

struct UniversalSearchAppEntry: Sendable {
    let id: String
    let kind: SearchEntityKind
    let titleKey: String
    var subtitleKey: String?
    var aliases: [String] = []
    var keywords: [String] = []
    let iconName: String
    let route: UniversalSearchFeatureRoute
}

enum UniversalSearchAppEntries {
    struct Availability: Sendable {
        var actions: Set<UniversalSearchWalletAction> = []
        var hasConnectedApps = false
        var hasWalletVersions = false
        var hasSecurity = false
        var hasSubwallets = false

        @MainActor static func current(account: MAccount?) -> Self {
            guard let account else { return .init() }
            var actions: Set<UniversalSearchWalletAction> = [.scan]
            if account.supportsReceive { actions.insert(.fund) }
            if account.supportsSend {
                actions.insert(.send)
                if !ConfigStore.shared.shouldRestrictSell { actions.insert(.sell) }
            }
            if account.supportsSwap { actions.insert(.swap) }
            if account.supportsEarn { actions.insert(.earn) }
            if !account.isView,
               !ConfigStore.shared.shouldRestrictSwapsAndOnRamp,
               OnRampCurrencyPolicy.defaultChain(for: account) != nil {
                actions.insert(.buyWithCard)
            }
            return Self(
                actions: actions,
                hasConnectedApps: !account.isView && (DappsStore.dappsCount ?? 0) > 0,
                hasWalletVersions: !account.isHardware && AccountStore.walletVersionsData?.versions.isEmpty == false,
                hasSecurity: AuthSupport.status.requiresAuthorization,
                hasSubwallets: account.type == .mnemonic && account.orderedChains.contains { chain, _ in
                    account.supportsSubwallets(on: chain)
                }
            )
        }
    }

    // Titles, subtitles and aliases share Android's AppSearchEntries localization keys.
    static let all: [UniversalSearchAppEntry] = [
        action(.fund, title: "Fund", icon: "DepositIconLarge", aliases: ["Receive", "Add Crypto"], keywords: ["deposit"]),
        action(.send, title: "Send", icon: "SendIconLarge", keywords: ["transfer"]),
        action(.swap, title: "Swap", icon: "SearchSwapIcon", aliases: ["Trade"], keywords: ["exchange", "convert"]),
        action(.earn, title: "Earn", icon: "EarnIconLarge", aliases: ["Stake"], keywords: ["staking"]),
        action(.buyWithCard, title: "Buy with Card", icon: "BuyIconLarge", aliases: ["Buy"]),
        action(.sell, title: "Sell", icon: "SellIconLarge"),
        action(.scan, title: "Scan", icon: "ScanIconLarge", aliases: ["Scan QR Code"]),
        setting(.appearance, title: "Appearance", subtitle: "Night Mode, Palette, Card", icon: "AppearanceIcon",
                aliases: ["Theme", "Palette"], keywords: ["night mode", "dark mode"]),
        setting(.notifications, title: "Notifications & Sounds", subtitle: "Wallets, Sounds",
                icon: "NotificationsSettingsIcon", aliases: ["Notifications"]),
        setting(.assets, title: "Assets & Activity", subtitle: "Base Currency, Token Order, Hidden NFTs",
                icon: "AssetsAndActivityIcon", aliases: ["Base Currency"], keywords: ["token order"]),
        setting(.dapps, title: "Connected Apps", icon: "DappsIcon", aliases: ["Connected Sites"],
                keywords: ["dapps", "disconnect"]),
        setting(.language, title: "Language", icon: "LanguageIcon"),
        setting(.walletVersions, title: "Wallet Versions", subtitle: "Your assets on other TON contracts",
                icon: "WalletVersionsIcon"),
        setting(.security, title: "Security", icon: "SecurityIcon"),
        setting(.subwallets, title: "Subwallets", icon: "SubwalletsIcon"),
        setting(.hiddenNfts, title: "Hidden NFTs", icon: "AssetsAndActivityIcon"),
        setting(.disclaimer, title: "Use Responsibly", icon: "ResponsibilityIcon30"),
        setting(.about, title: "About", icon: "AboutIcon"),
    ]

    static func available(in availability: Availability) -> [UniversalSearchAppEntry] {
        all.filter { entry in
            switch entry.route {
            case .walletAction(let action): availability.actions.contains(action)
            case .settings(.dapps): availability.hasConnectedApps
            case .settings(.walletVersions): availability.hasWalletVersions
            case .settings(.security): availability.hasSecurity
            case .settings(.subwallets): availability.hasSubwallets
            default: true
            }
        }
    }

    static func documents(
        availability: Availability,
        localize: (String) -> String
    ) -> [SearchDocument] {
        available(in: availability).map { entry in
            var fields = [SearchField(localize(entry.titleKey), kind: .title)]
            for key in [entry.titleKey] + entry.aliases {
                fields.append(SearchField(key, kind: .alias))
                fields.append(SearchField(localize(key), kind: .alias))
            }
            fields += entry.keywords.map { SearchField($0, kind: .keyword) }
            if let subtitleKey = entry.subtitleKey {
                fields.append(SearchField(localize(subtitleKey), kind: .description))
            }
            return SearchDocument(
                id: SearchEntityID(entry.id),
                kind: entry.kind,
                fields: fields
            )
        }
    }

    private static func action(
        _ action: UniversalSearchWalletAction,
        title: String,
        icon: String,
        aliases: [String] = [],
        keywords: [String] = []
    ) -> UniversalSearchAppEntry {
        UniversalSearchAppEntry(
            id: "action:\(action.rawValue)", kind: .walletAction, titleKey: title,
            aliases: aliases, keywords: keywords, iconName: icon, route: .walletAction(action)
        )
    }

    private static func setting(
        _ section: AppSettingsSection,
        title: String,
        subtitle: String? = nil,
        icon: String,
        aliases: [String] = [],
        keywords: [String] = []
    ) -> UniversalSearchAppEntry {
        UniversalSearchAppEntry(
            id: "setting:\(section.rawValue)", kind: .setting, titleKey: title,
            subtitleKey: subtitle, aliases: aliases, keywords: keywords, iconName: icon,
            route: .settings(section)
        )
    }
}

struct UniversalSearchAppEntrySource: UniversalSearchSource {
    static let id = SearchSourceID("feature:app-entries")
    let sourceID = Self.id
    var scoping: UniversalSearchSourceScoping { .account }

    func snapshot(for context: UniversalSearchContext) async throws -> UniversalSearchSourceSnapshot {
        let documents = await MainActor.run {
            guard let accountID = context.scopeID,
                  accountID == AccountStore.accountId,
                  let account = AccountStore.accountsById[accountID] else { return [SearchDocument]() }
            return UniversalSearchAppEntries.documents(
                availability: .current(account: account),
                localize: { lang($0) }
            )
        }
        return UniversalSearchSourceSnapshot(
            sourceID: sourceID, authority: 100, generatedAt: Date(), documents: documents
        )
    }
}
