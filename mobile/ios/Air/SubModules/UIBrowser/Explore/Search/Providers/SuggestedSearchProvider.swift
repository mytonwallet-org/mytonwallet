import Foundation
import WalletContext
import WalletCore

@MainActor
final class SuggestedSearchProvider: SingleShotSearchProvider {
    private let actions: ExploreSearchActions

    /// Matches e.g. `user.t.me`, capturing the username.
    private static let telegramHostRegex = /^\s*([a-zA-Z][a-zA-Z0-9_]{1,30}[a-zA-Z0-9])[.][tT][.][Mm][eE]\s*$/
    /// Matches e.g. `t.me/user`, capturing the username.
    private static let telegramPathRegex = /^\s*[tT][.][Mm][eE]\/([a-zA-Z][a-zA-Z0-9_]{1,30}[a-zA-Z0-9])\s*$/

    init(actions: ExploreSearchActions) {
        self.actions = actions
    }

    private static func telegramUsername(in text: String) -> String? {
        if let match = text.wholeMatch(of: telegramHostRegex) {
            return String(match.1)
        }
        if let match = text.wholeMatch(of: telegramPathRegex) {
            return String(match.1)
        }
        return nil
    }

    func search(_ query: SearchQuery) async -> [SearchResultSection] {
        guard !query.isEmpty else { return [] }

        var items: [any SearchResultItem] = []

        let queryText = query.text
        
        if let username = Self.telegramUsername(in: queryText) {
            items.append(
                SuggestedSiteSearchItem(
                    title: "Telegram: @\(username)",
                    subtitle: "t.me/\(username)/",
                    url: "https://t.me/\(username)/",
                    appUrl: "tg://resolve?domain=\(username)&profile",
                    iconName: "TelegramLogo24",
                    actions: actions
                )
            )
        }

        return items.isEmpty ? [] : [
            .init(
                id: .suggestions,
                order: SearchSectionOrder.suggestions,
                header: .init(title: lang("Suggestions")),
                items: items
            )
        ]
    }
}
