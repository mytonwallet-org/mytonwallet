import UIComponents
import UIKit
import UIUniversalSearch
import UniversalSearchCore
import UniversalSearchWalletCore
import WalletContext
import WalletCore
import WalletCoreTypes

@MainActor
public struct UniversalSearchResultsPresenter {
    static let startAgentConversationItemID = "agent-chat:start"

    public typealias Resolver = @MainActor (
        SearchDocument,
        UniversalSearchContext
    ) -> UniversalSearchResolvedResult?
    public typealias TokenResolver = @MainActor (
        String,
        String
    ) -> ApiToken?
    public typealias TokenBalanceResolver = @MainActor (
        String,
        String
    ) -> MTokenBalance?

    private enum Metrics {
        static let maximumItemsPerSection = 9
        static let rowsPerPage = 3
    }

    private struct ResolvedHit {
        let hit: UniversalSearchHit
        let result: UniversalSearchResolvedResult
    }

    private let resolver: Resolver

    public init() {
        self.init(tokenResolver: { _, slug in
            TokenStore.getToken(slug: slug)
        })
    }

    public init(tokenResolver: @escaping TokenResolver) {
        self.init(
            tokenResolver: tokenResolver,
            tokenBalanceResolver: { accountID, tokenSlug in
                BalanceDataStore.walletTokensData(accountId: accountID)?
                    .allTokenBalances
                    .first { $0.tokenSlug == tokenSlug && !$0.isStaking }
            }
        )
    }

    public init(
        tokenResolver: @escaping TokenResolver,
        tokenBalanceResolver: @escaping TokenBalanceResolver
    ) {
        self.resolver = { document, context in
            Self.resolveLiveResult(
                document,
                context: context,
                tokenResolver: tokenResolver,
                tokenBalanceResolver: tokenBalanceResolver
            )
        }
    }

    public init(resolver: @escaping Resolver) {
        self.resolver = resolver
    }

    public func presentation(
        for snapshot: UniversalSearchResultSnapshot,
        context: UniversalSearchContext
    ) -> UniversalSearchPresentation {
        guard !snapshot.query.isEmpty else { return .empty }

        let resolvedHits: [ResolvedHit] = snapshot.hits.compactMap { hit -> ResolvedHit? in
            guard hit.document.kind != .agentAction else { return nil }
            return resolver(hit.document, context).map { ResolvedHit(hit: hit, result: $0) }
        }
        if case .some(.openWebsite) = UniversalSearchWebIntent(snapshot.query.text),
           let topKind = resolvedHits.first?.hit.document.kind,
           topKind != .site,
           topKind != .application {
            return fallbackPresentation(for: snapshot.query)
        }
        guard let topHit = resolvedHits.first else {
            return fallbackPresentation(for: snapshot.query)
        }

        let remainingHits = resolvedHits.dropFirst()
        var sections = [UniversalSearchSection(
            id: "top-hit",
            title: topHitTitle(for: topHit.hit.document),
            showsLeadingSeparator: false,
            items: [topHit.result.item]
        )]

        let groups: [(id: String, title: String, kinds: Set<SearchEntityKind>)] = [
            ("tokens", lang("Tokens and Stocks"), [.token, .stock]),
            ("collectibles", lang("Collectibles"), [.collectible, .collection]),
            ("apps", lang("Apps"), [.application]),
            ("wallets", lang("Wallets"), [.wallet]),
            ("actions", lang("Actions"), [.walletAction]),
            ("settings", lang("Settings"), [.setting]),
            ("recent-chats", lang("Recent Chats"), [.agentChat]),
            ("recent-searches", lang("Recent Searches"), [.webSearchHistory]),
            ("sites", lang("Sites"), [.site]),
        ]

        var isFirstResultSection = true
        for group in groups {
            let hits = remainingHits
                .filter { group.kinds.contains($0.hit.document.kind) }
                .prefix(Metrics.maximumItemsPerSection)
            guard !hits.isEmpty else { continue }

            sections.append(UniversalSearchSection(
                id: group.id,
                title: group.title,
                layout: hits.count > Metrics.rowsPerPage
                    ? .paged(rowsPerPage: Metrics.rowsPerPage)
                    : .list,
                rowHeight: group.id == "actions" ? 52 : 56,
                showsLeadingSeparator: !isFirstResultSection,
                items: hits.map(\.result.item)
            ))
            isFirstResultSection = false
        }

        var routesByItemID = Dictionary(
            uniqueKeysWithValues: resolvedHits.map {
                ($0.result.item.id, $0.result.route)
            }
        )
        appendFallbackActions(
            query: snapshot.query.text,
            to: &sections,
            routesByItemID: &routesByItemID
        )

        return UniversalSearchPresentation(
            sections: sections,
            preselectedItemID: topHit.result.item.id,
            routesByItemID: routesByItemID
        )
    }

    public func browsePresentation(
        for snapshot: UniversalSearchBrowseSnapshot,
        selectedModes: [String: UniversalSearchBrowseMode] = [:],
        context: UniversalSearchContext
    ) -> UniversalSearchPresentation {
        let currentConversation = resolvedBrowseDocuments(
            snapshot.recentDocuments,
            kinds: [.agentChat],
            context: context
        ).first ?? startAgentConversationResult()
        let agentSuggestions = resolvedBrowseDocuments(
            snapshot.trendingDocuments,
            kinds: [.agentAction],
            context: context
        )

        let groups: [(id: String, title: String, kinds: Set<SearchEntityKind>)] = [
            ("tokens", lang("Tokens and Stocks"), [.token, .stock]),
            ("apps", lang("Apps"), [.application]),
        ]
        var sections = [UniversalSearchSection(
            id: "chats",
            title: lang("Chats"),
            showsLeadingSeparator: false,
            items: [currentConversation.item]
        )]
        if !agentSuggestions.isEmpty {
            sections.append(UniversalSearchSection(
                id: "agent-suggestions",
                title: "",
                layout: .promptPages(rowsPerPage: Metrics.rowsPerPage),
                showsHeader: false,
                showsLeadingSeparator: false,
                items: agentSuggestions.map(\.item)
            ))
        }
        var routesByItemID = Dictionary(uniqueKeysWithValues: (
            [currentConversation] + agentSuggestions
        ).map {
            ($0.item.id, $0.route)
        })

        for group in groups {
            let recent = resolvedBrowseDocuments(
                snapshot.recentDocuments,
                kinds: group.kinds,
                context: context
            )
            let trending = resolvedBrowseDocuments(
                snapshot.trendingDocuments,
                kinds: group.kinds,
                context: context
            )
            guard !recent.isEmpty || !trending.isEmpty else { continue }

            let preferredMode = selectedModes[group.id] ?? .recent
            let selectedMode: UniversalSearchBrowseMode = switch preferredMode {
            case .recent where !recent.isEmpty:
                .recent
            case .trending where !trending.isEmpty:
                .trending
            case .recent:
                .trending
            case .trending:
                .recent
            }
            let selectedResults = selectedMode == .recent ? recent : trending
            let selectedItems = selectedResults.map(\.item)
            for result in selectedResults {
                routesByItemID[result.item.id] = result.route
            }
            let headerAccessory: UniversalSearchSection.HeaderAccessory = if recent.isEmpty {
                .text(lang("Trending"))
            } else if trending.isEmpty {
                .text(lang("$universal_search_recent"))
            } else {
                .toggle(
                    primary: lang("$universal_search_recent"),
                    secondary: lang("Trending"),
                    selected: selectedMode == .recent ? .primary : .secondary
                )
            }
            sections.append(UniversalSearchSection(
                id: group.id,
                title: group.title,
                headerAccessory: headerAccessory,
                layout: selectedItems.count > Metrics.rowsPerPage
                    ? .paged(rowsPerPage: Metrics.rowsPerPage)
                    : .list,
                showsLeadingSeparator: !sections.isEmpty,
                items: selectedItems
            ))
        }

        return UniversalSearchPresentation(
            sections: sections,
            preselectedItemID: nil,
            routesByItemID: routesByItemID
        )
    }

    private func startAgentConversationResult() -> UniversalSearchResolvedResult {
        UniversalSearchResolvedResult(
            item: UniversalSearchItem(
                id: Self.startAgentConversationItemID,
                content: .chat(UniversalSearchChatResult(
                    title: lang("Ask Agent"),
                    subtitle: lang("$universal_search_start_conversation")
                ))
            ),
            route: .agent(query: nil)
        )
    }

    private func resolvedBrowseDocuments(
        _ documents: [SearchDocument],
        kinds: Set<SearchEntityKind>,
        context: UniversalSearchContext
    ) -> [UniversalSearchResolvedResult] {
        var results: [UniversalSearchResolvedResult] = []
        for document in documents where kinds.contains(document.kind) {
            guard let result = resolver(document, context) else { continue }
            results.append(result)
            if results.count == Metrics.maximumItemsPerSection {
                break
            }
        }
        return results
    }

    private func topHitTitle(for document: SearchDocument) -> String {
        switch document.kind {
        case .token:
            lang("Token")
        case .stock:
            lang("Stock")
        case .collectible:
            lang("Collectible")
        case .collection:
            lang("Collection")
        case .application:
            lang("App")
        case .wallet where document.signals.traits.contains(.external):
            lang("View Wallet")
        case .wallet:
            lang("Wallet")
        case .agentChat:
            lang("Recent Chat")
        case .walletAction:
            lang("Action")
        case .setting:
            lang("Settings")
        case .site, .webSearchHistory:
            lang("Recent Search")
        default:
            ""
        }
    }

    private func fallbackPresentation(
        for query: UniversalSearchQuery
    ) -> UniversalSearchPresentation {
        var sections: [UniversalSearchSection] = []
        var routesByItemID: [String: UniversalSearchFeatureRoute] = [:]
        var preselectedItemID: String?

        if case .some(.openWebsite(let url, let displayText)) = UniversalSearchWebIntent(query.text) {
            let itemID = "web-action:open:\(url.absoluteString.lowercased())"
            let item = UniversalSearchItem(
                id: itemID,
                content: .openWebsite(UniversalSearchSiteResult(
                    title: displayText,
                    subtitle: lang("Open Website")
                ))
            )
            sections.append(UniversalSearchSection(
                id: "open-website",
                title: lang("Open Website"),
                showsLeadingSeparator: false,
                items: [item]
            ))
            routesByItemID[itemID] = .website(url: url, title: nil)
            preselectedItemID = itemID
        }

        appendFallbackActions(
            query: query.text,
            to: &sections,
            routesByItemID: &routesByItemID
        )
        if preselectedItemID == nil, shouldPreferAgent(for: query.text) {
            preselectedItemID = agentActionID(for: query.text)
        }
        return UniversalSearchPresentation(
            sections: sections,
            preselectedItemID: preselectedItemID,
            routesByItemID: routesByItemID
        )
    }

    private func appendFallbackActions(
        query: String,
        to sections: inout [UniversalSearchSection],
        routesByItemID: inout [String: UniversalSearchFeatureRoute]
    ) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        let agentID = agentActionID(for: query)
        sections.append(UniversalSearchSection(
            id: "ask-agent",
            title: lang("Ask Agent"),
            showsLeadingSeparator: sections.isEmpty,
            items: [UniversalSearchItem(id: agentID, content: .askAgent(query: query))]
        ))
        routesByItemID[agentID] = .agent(query: query)

        let googleID = "web-action:google:\(query.lowercased())"
        sections.append(UniversalSearchSection(
            id: "search-google",
            title: lang("Search in Google"),
            rowHeight: 52,
            showsLeadingSeparator: false,
            items: [UniversalSearchItem(id: googleID, content: .google(query: query))]
        ))
        routesByItemID[googleID] = .google(query: query)
    }

    private func agentActionID(for query: String) -> String {
        "agent-action:\(query.lowercased())"
    }

    private func shouldPreferAgent(for query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = normalized.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2 else { return false }
        if normalized.hasSuffix("?") || words.count >= 3 {
            return true
        }
        let conversationalOpeners: Set<Substring> = [
            "add", "buy", "can", "find", "help", "how", "learn", "send",
            "show", "swap", "track", "transfer", "what", "when", "where", "why",
        ]
        return words.first.map(conversationalOpeners.contains) == true
    }

    private static func resolveLiveResult(
        _ document: SearchDocument,
        context: UniversalSearchContext,
        tokenResolver: TokenResolver,
        tokenBalanceResolver: TokenBalanceResolver
    ) -> UniversalSearchResolvedResult? {
        switch document.kind {
        case .walletAction, .setting:
            resolveAppEntry(document, context: context)
        case .token, .stock:
            resolveToken(
                document,
                context: context,
                tokenResolver: tokenResolver,
                tokenBalanceResolver: tokenBalanceResolver
            )
        case .collectible:
            resolveCollectible(document, context: context)
        case .collection:
            resolveCollection(document, context: context)
        case .application:
            resolveApplication(document)
        case .wallet:
            if document.signals.traits.contains(.external),
               document.attributeValue(for: WalletCoreSearchAttributeKey.accountID) == nil {
                resolveExternalWallet(document)
            } else {
                resolveWallet(document)
            }
        case .agentChat:
            resolveAgentChat(document)
        case .agentAction:
            resolveAgentSuggestion(document)
        case .site:
            resolveSite(document)
        case .webSearchHistory:
            resolveWebSearchHistory(document)
        default:
            nil
        }
    }

    private static func resolveAgentChat(
        _ document: SearchDocument
    ) -> UniversalSearchResolvedResult? {
        guard let title = document.attributeValue(for: UniversalSearchFeatureAttributeKey.title),
              let subtitle = document.attributeValue(for: UniversalSearchFeatureAttributeKey.subtitle) else {
            return nil
        }
        return UniversalSearchResolvedResult(
            item: UniversalSearchItem(
                id: document.id.rawValue,
                content: .chat(UniversalSearchChatResult(title: title, subtitle: subtitle))
            ),
            route: .agent(query: nil)
        )
    }

    private static func resolveAppEntry(
        _ document: SearchDocument,
        context: UniversalSearchContext
    ) -> UniversalSearchResolvedResult? {
        guard let accountID = context.scopeID,
              accountID == AccountStore.accountId,
              let account = AccountStore.accountsById[accountID],
              let entry = UniversalSearchAppEntries.available(in: .current(account: account))
                .first(where: { $0.id == document.id.rawValue }),
              let image = UniversalSearchAppEntryIcon.image(for: entry) else { return nil }
        return UniversalSearchResolvedResult(
            item: UniversalSearchItem(
                id: entry.id,
                content: .shortcut(UniversalSearchShortcutResult(
                    icon: UniversalSearchIcon(.init(image: image, shape: .square)),
                    title: lang(entry.titleKey),
                    subtitle: entry.subtitleKey.map { lang($0) }
                ))
            ),
            route: entry.route
        )
    }

    private static func resolveAgentSuggestion(
        _ document: SearchDocument
    ) -> UniversalSearchResolvedResult? {
        guard let title = document.attributeValue(for: UniversalSearchFeatureAttributeKey.title),
              let prompt = document.attributeValue(for: UniversalSearchFeatureAttributeKey.query) else {
            return nil
        }
        return UniversalSearchResolvedResult(
            item: UniversalSearchItem(
                id: document.id.rawValue,
                content: .prompt(UniversalSearchPrompt(text: title))
            ),
            route: .agent(query: prompt)
        )
    }

    private static func resolveSite(
        _ document: SearchDocument
    ) -> UniversalSearchResolvedResult? {
        guard let title = document.attributeValue(for: UniversalSearchFeatureAttributeKey.title),
              let urlString = document.attributeValue(for: WalletCoreSearchAttributeKey.url),
              let url = URL(string: urlString) else {
            return nil
        }
        let host = url.host(percentEncoded: false) ?? url.host ?? urlString
        let subtitle = historySubtitle(
            prefix: host,
            dateString: document.attributeValue(for: UniversalSearchFeatureAttributeKey.updatedAt)
        )
        return UniversalSearchResolvedResult(
            item: UniversalSearchItem(
                id: document.id.rawValue,
                content: .site(UniversalSearchSiteResult(title: title, subtitle: subtitle))
            ),
            route: .website(url: url, title: title)
        )
    }

    private static func resolveWebSearchHistory(
        _ document: SearchDocument
    ) -> UniversalSearchResolvedResult? {
        guard let query = document.attributeValue(for: UniversalSearchFeatureAttributeKey.query) else {
            return nil
        }
        return UniversalSearchResolvedResult(
            item: UniversalSearchItem(
                id: document.id.rawValue,
                content: .recentSearch(UniversalSearchHistoryResult(
                    title: query,
                    subtitle: historySubtitle(
                        prefix: lang("Google"),
                        dateString: document.attributeValue(
                            for: UniversalSearchFeatureAttributeKey.updatedAt
                        )
                    )
                ))
            ),
            route: .google(query: query)
        )
    }

    private static func historySubtitle(prefix: String, dateString: String?) -> String {
        guard let dateString,
              let date = ISO8601DateFormatter().date(from: dateString) else {
            return prefix
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return "\(prefix) · \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private static func resolveToken(
        _ document: SearchDocument,
        context: UniversalSearchContext,
        tokenResolver: TokenResolver,
        tokenBalanceResolver: TokenBalanceResolver
    ) -> UniversalSearchResolvedResult? {
        guard let accountID = context.scopeID,
              let tokenSlug = document.attributeValue(for: WalletCoreSearchAttributeKey.tokenSlug),
              let token = tokenResolver(accountID, tokenSlug) else {
            return nil
        }

        let balance = tokenBalanceResolver(accountID, tokenSlug)
        let price = token.price.map {
            BaseCurrencyAmount.fromDouble($0, TokenStore.baseCurrency)
                .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
        } ?? " "
        let amount = balance.map {
            TokenAmount($0.balance, token).formatted(.defaultAdaptive, roundHalfUp: false)
        } ?? token.symbol
        let balanceValue = balance?.toBaseCurrency.map {
            BaseCurrencyAmount.fromDouble($0, TokenStore.baseCurrency)
                .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
        }
        let icon = UniversalSearchIcon { iconView in
            iconView.config(
                with: token,
                isStaking: false,
                isWalletView: false,
                stakingAccessory: nil,
                shouldShowChain: !token.isNative
            )
        }
        let item = UniversalSearchItem(
            id: document.id.rawValue,
            content: .token(UniversalSearchTokenResult(
                icon: icon,
                title: token.displayName(strippingLabelWhenShown: true),
                badge: token.isRwaStock ? token.label : nil,
                price: price,
                amount: amount,
                balanceValue: balanceValue
            ))
        )
        return UniversalSearchResolvedResult(
            item: item,
            route: .token(accountID: accountID, token: token)
        )
    }

    private static func resolveCollectible(
        _ document: SearchDocument,
        context: UniversalSearchContext
    ) -> UniversalSearchResolvedResult? {
        guard let accountID = document.attributeValue(
            for: WalletCoreSearchAttributeKey.accountID
        ) ?? context.scopeID,
              document.id.rawValue.hasPrefix("collectible:"),
              let displayNft = NftStore.getNft(
                  accountId: accountID,
                  nftId: String(document.id.rawValue.dropFirst("collectible:".count))
              ),
              !displayNft.shouldHide,
              let chainValue = document.attributeValue(for: WalletCoreSearchAttributeKey.chain),
              let chain = ApiChain(rawValue: chainValue),
              let address = document.attributeValue(for: WalletCoreSearchAttributeKey.address),
              displayNft.nft.chain == chain,
              displayNft.nft.address == address else {
            return nil
        }
        let nft = displayNft.nft

        let title = nft.name?.nilIfEmpty ?? lang("NFT")
        let imageURL = document.attributeValue(for: WalletCoreSearchAttributeKey.iconURL)
            .flatMap(URL.init(string:))
        let icon = remoteIcon(url: imageURL, title: title, shape: .roundedSquare)
        let item = UniversalSearchItem(
            id: document.id.rawValue,
            content: .collectible(UniversalSearchCollectibleResult(
                icon: icon,
                title: title,
                subtitle: lang("NFT")
            ))
        )
        return UniversalSearchResolvedResult(
            item: item,
            route: .collectible(accountID: accountID, nft: nft)
        )
    }

    private static func resolveCollection(
        _ document: SearchDocument,
        context: UniversalSearchContext
    ) -> UniversalSearchResolvedResult? {
        guard let accountID = document.attributeValue(
            for: WalletCoreSearchAttributeKey.accountID
        ) ?? context.scopeID,
              let chainValue = document.attributeValue(for: WalletCoreSearchAttributeKey.chain),
              let chain = ApiChain(rawValue: chainValue),
              let address = document.attributeValue(for: WalletCoreSearchAttributeKey.address),
              let title = document.fieldValue(for: .title) else {
            return nil
        }

        let collection = NftCollection(chain: chain, address: address, name: title)
        let item = UniversalSearchItem(
            id: document.id.rawValue,
            content: .collection(UniversalSearchCollectionResult(
                title: title,
                subtitle: lang("Collection")
            ))
        )
        return UniversalSearchResolvedResult(
            item: item,
            route: .collection(accountID: accountID, collection: collection)
        )
    }

    private static func resolveApplication(
        _ document: SearchDocument
    ) -> UniversalSearchResolvedResult? {
        guard let title = document.fieldValue(for: .title),
              let urlString = document.attributeValue(for: WalletCoreSearchAttributeKey.url),
              let url = URL(string: urlString) else {
            return nil
        }

        let imageURL = document.attributeValue(for: WalletCoreSearchAttributeKey.iconURL)
        let host = url.host(percentEncoded: false) ?? url.host ?? urlString
        let item = UniversalSearchItem(
            id: document.id.rawValue,
            content: .app(UniversalSearchAppResult(
                icon: UniversalSearchIcon { iconView in
                    iconView.config(withDappIconURL: imageURL)
                },
                title: title,
                subtitle: host,
                showsTelegramBadge: host.hasSuffix(".t.me") || host == "t.me",
                actionTitle: lang("Open")
            ))
        )
        return UniversalSearchResolvedResult(
            item: item,
            route: .application(
                url: url,
                title: title,
                opensExternally: document.attributeValue(
                    for: WalletCoreSearchAttributeKey.opensExternally
                ) == "true"
            )
        )
    }

    private static func resolveWallet(
        _ document: SearchDocument
    ) -> UniversalSearchResolvedResult? {
        guard let accountID = document.attributeValue(for: WalletCoreSearchAttributeKey.accountID),
              let account = AccountStore.accountsById[accountID] else {
            return nil
        }

        let subtitle = BalanceDataStore.balanceTotals(accountId: accountID)?
            .totalBalance
            .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
            ?? account.orderedChains.first?.1.domain?.nilIfEmpty
            ?? formatStartEndAddress(account.firstAddress)
        let icon = UniversalSearchIcon { iconView in
            iconView.config(with: account)
        }
        let item = UniversalSearchItem(
            id: document.id.rawValue,
            content: .wallet(UniversalSearchWalletResult(
                icon: icon,
                title: account.displayName,
                subtitle: subtitle
            ))
        )
        let route: UniversalSearchFeatureRoute
        if account.isTemporaryView {
            route = .externalWallet(
                network: account.network,
                addressOrDomainByChain: Dictionary(
                    uniqueKeysWithValues: account.orderedChains.map { chain, info in
                        (chain.rawValue, info.preferredCopyString)
                    }
                )
            )
        } else {
            route = .wallet(account)
        }
        return UniversalSearchResolvedResult(item: item, route: route)
    }

    private static func resolveExternalWallet(
        _ document: SearchDocument
    ) -> UniversalSearchResolvedResult? {
        guard let networkValue = document.attributeValue(
                  for: WalletCoreSearchAttributeKey.network
              ),
              let network = ApiNetwork(rawValue: networkValue),
              let chainValue = document.attributeValue(
                  for: WalletCoreSearchAttributeKey.chain
              ),
              let chain = ApiChain(rawValue: chainValue),
              let input = document.attributeValue(
                  for: WalletCoreSearchAttributeKey.inputAddressOrDomain
              ),
              let address = document.attributeValue(
                  for: WalletCoreSearchAttributeKey.address
              ) else {
            return nil
        }

        let addressName = document.attributeValue(
            for: WalletCoreSearchAttributeKey.addressName
        )?.nilIfEmpty
        let domain = document.attributeValue(
            for: WalletCoreSearchAttributeKey.domain
        )?.nilIfEmpty
        let title = addressName ?? domain ?? formatStartEndAddress(address)
        let subtitle: String
        if addressName != nil, let domain {
            subtitle = "\(domain) • \(formatStartEndAddress(address))"
        } else if addressName != nil || domain != nil {
            subtitle = formatStartEndAddress(address)
        } else {
            subtitle = chain.title
        }

        let icon: UniversalSearchIcon
        if let addressName {
            let placeholder = MAccount(
                id: document.id.rawValue,
                title: addressName,
                type: .view,
                byChain: [chain: AccountChain(address: address)],
                isTemporary: true
            )
            icon = UniversalSearchIcon { iconView in
                iconView.config(with: placeholder)
            }
        } else {
            icon = UniversalSearchIcon(UniversalSearchIconConfiguration(
                image: chain.image,
                shape: .roundedSquare
            ))
        }
        let item = UniversalSearchItem(
            id: document.id.rawValue,
            content: .wallet(UniversalSearchWalletResult(
                icon: icon,
                title: title,
                subtitle: subtitle
            ))
        )
        return UniversalSearchResolvedResult(
            item: item,
            route: .externalWallet(
                network: network,
                addressOrDomainByChain: externalWalletInputs(
                    input: input,
                    displayChain: chain
                )
            )
        )
    }

    private static func externalWalletInputs(
        input: String,
        displayChain: ApiChain
    ) -> [String: String] {
        let chains = displayChain.isEvm && displayChain.isValidAddress(input)
            ? ApiChain.evmChains.filter { $0.isValidAddress(input) }
            : [displayChain]
        return Dictionary(uniqueKeysWithValues: chains.map { ($0.rawValue, input) })
    }

    private static func remoteIcon(
        url: URL?,
        title: String,
        shape: UniversalSearchIconConfiguration.Shape
    ) -> UniversalSearchIcon {
        let initials = title.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(1)
            .uppercased()
        return UniversalSearchIcon { iconView in
            iconView.config(
                withRemoteImageURL: url,
                placeholder: UniversalSearchIconConfiguration(
                    initials: initials,
                    backgroundColor: AirTintColor.withAlphaComponent(0.65),
                    shape: shape,
                    initialsFont: UIFont.roundedNative(ofSize: 10, weight: .bold)
                )
            )
        }
    }
}

private extension SearchDocument {
    func fieldValue(for kind: SearchFieldKind) -> String? {
        fields.first { $0.kind == kind }?.value
    }
}
