import Foundation
import UIInAppBrowser
import WalletContext
import WalletCore

struct ExploreSearchResultItem: Equatable, Identifiable {
    enum Source: Equatable {
        case site(ApiSite)
        case connectedDapp(ApiDapp)
        case history(BrowserHistoryItem)
    }

    let source: Source
    var showFavicon: Bool = false

    var id: String {
        switch source {
        case .site(let s): s.url
        case .connectedDapp(let d): d.url
        case .history(let h): (showFavicon ? "match_" : "history_") + h.url
        }
    }

    var name: String {
        switch source {
        case .site(let s): s.name
        case .connectedDapp(let d): d.name
        case .history(let h): h.title
        }
    }

    var iconURL: String {
        switch source {
        case .site(let s): s.icon
        case .connectedDapp(let d): d.iconUrl
        case .history(let h): h.favicon
        }
    }

    @MainActor var subtitle: String {
        switch source {
        case .site(let s): return s.description
        case .connectedDapp(let d): return d.displayUrl
        case .history(let h):
            let host = URL(string: h.url)?.host ?? h.url
            let relative = SearchDateFormatting.relativeString(for: h.visitDate)
            return "\(host) · \(relative)"
        }
    }

    var shouldOpenExternally: Bool {
        switch source {
        case .site(let s): s.shouldOpenExternally
        case .connectedDapp, .history: false
        }
    }

    var showOpenButton: Bool {
        switch source {
        case .site, .connectedDapp: true
        case .history: false
        }
    }

    var url: String {
        switch source {
        case .site(let s): s.url
        case .connectedDapp(let d): d.url
        case .history(let h): h.url
        }
    }

    func prefixMatches(keyword: String) -> Bool {
        switch source {
        case .site(let s):
            return s.name.lowercased().hasPrefix(keyword)
                || s.description.lowercased().hasPrefix(keyword)
                || SearchURLMatching.urlHasPrefix(s.url, prefix: keyword)
        case .connectedDapp(let d):
            return d.name.lowercased().hasPrefix(keyword) || SearchURLMatching.urlHasPrefix(d.url, prefix: keyword)
        case .history(let h):
            return h.title.lowercased().hasPrefix(keyword) || SearchURLMatching.urlHasPrefix(h.url, prefix: keyword)
        }
    }
}

@MainActor
struct ResultSearchItem: SearchResultItem {
    let payload: ExploreSearchResultItem
    let isExactMatch: Bool
    let actions: ExploreSearchActions

    var id: String { payload.id }
    var deduplicationKey: String? {  payload.url.lowercased() }

    func performDefaultAction() {
        switch payload.source {
        case .site(let site): actions.openSite(site)
        case .connectedDapp(let dapp): actions.openDapp(dapp)
        case .history(let historyItem): actions.openHistory(historyItem)
        }
    }

    func makeView(isTopMatch: Bool) -> AnySearchItemView {
        AnySearchItemView {
            if isTopMatch {
                SearchResultTopMatchItemRow(item: payload) { performDefaultAction() }
            } else {
                SearchResultItemRow(item: payload) { performDefaultAction() }
            }
        }
    }
}

@MainActor
struct WalletSearchResultItem: SearchResultItem {
    let network: ApiNetwork
    let chain: ApiChain
    let inputAddressOrDomain: String
    let address: String
    let name: String?
    let domain: String?
    let actions: ExploreSearchActions
    var id: String { "wallet_\(chain.rawValue)_\(address)" }
    var isExactMatch: Bool { true }

    func performDefaultAction() {
        actions.showTemporaryViewAccount(network, [chain.rawValue: inputAddressOrDomain])
    }

    func makeView(isTopMatch: Bool) -> AnySearchItemView {
        AnySearchItemView {
            WalletTopMatchRow(chain: chain, address: address, name: name, domain: domain) {
                performDefaultAction()
            }
        }
    }
}

@MainActor
struct MyWalletSearchResultItem: SearchResultItem {
    let account: MAccount
    let chain: ApiChain
    let address: String
    let isFullMatch: Bool
    let actions: ExploreSearchActions

    var id: String { "mywallet_\(account.id)_\(chain.rawValue)" }
    var isExactMatch: Bool { isFullMatch }

    func performDefaultAction() {
        actions.openWallet(account)
    }

    func makeView(isTopMatch: Bool) -> AnySearchItemView {
        AnySearchItemView {
            MyWalletRow(
                account: account,
                name: account.title?.nilIfEmpty,
                address: address,
                isTopMatch: isTopMatch,
                tapAction: { performDefaultAction() }
            )
        }
    }
}

@MainActor
struct RecentSearchResultItem: SearchResultItem {
    let text: String
    let actions: ExploreSearchActions
    let isCompact: Bool
    
    var id: String { "recent_" + text }

    func performDefaultAction() {
        actions.insertToSearchString(text)
    }

    func makeView(isTopMatch: Bool) -> AnySearchItemView {
        AnySearchItemView {
            RecentSearchItemRow(text: text, isCompact: isCompact) { performDefaultAction() }
        }
    }
}

@MainActor
struct OpenLinkResultItem: SearchResultItem {
    let openableURL: SearchOpenableURL
    let actions: ExploreSearchActions
    let isCompact: Bool

    var id: String { "openlink_\(openableURL.url.absoluteString)" }

    func performDefaultAction() {
        actions.openUrl(openableURL)
    }

    func makeView(isTopMatch: Bool) -> AnySearchItemView {
        AnySearchItemView {
            RecentSearchItemRow(text: openableURL.displayText, isCompact: isCompact, iconName: "link") { performDefaultAction() }
        }
    }
}

@MainActor
struct SearchGoogleResultItem: SearchResultItem {
    let text: String
    let actions: ExploreSearchActions
    let isCompact: Bool
    
    var id: String { "google_" + text }

    func performDefaultAction() {
        actions.searchGoogle(text)
    }

    func makeView(isTopMatch: Bool) -> AnySearchItemView {
        AnySearchItemView {
            RecentSearchItemRow(text: text, isCompact: isCompact) { performDefaultAction() }
        }
    }
}

@MainActor
struct SuggestedSearchResultItem: SearchResultItem {
    let text: String
    let actions: ExploreSearchActions
    var visitDate: Date
    
    var id: String { "suggested_" + text }

    func performDefaultAction() {
        actions.insertToSearchString(text)
    }

    func makeView(isTopMatch: Bool) -> AnySearchItemView {
        AnySearchItemView {
            SuggestedSearchItemRow(text: text, visitDate: visitDate) { performDefaultAction() }
        }
    }
}

@MainActor
struct SuggestedSiteSearchItem: SearchResultItem {
    let title: String
    let subtitle: String
    let url: String
    let appUrl: String?
    let iconName: String
    let actions: ExploreSearchActions

    var id: String { "suggested_" + url }
    var deduplicationKey: String? { url.lowercased() }

    func performDefaultAction() {
        actions.openExternalURL(url, appUrl)
    }

    func makeView(isTopMatch: Bool) -> AnySearchItemView {
        AnySearchItemView {
            SuggestedSiteRow(title: title, subtitle: subtitle, url: url, iconName: iconName) {
                performDefaultAction()
            }
        }
    }
}
