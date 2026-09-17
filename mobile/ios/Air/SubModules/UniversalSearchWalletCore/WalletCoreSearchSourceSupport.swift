import Foundation
import UniversalSearchCore

enum WalletCoreSearchSourceAuthority {
    static let local = 100
    static let catalog = 80
}

public enum WalletCoreSearchAttributeKey {
    public static let accountID = SearchAttributeKey("wallet-core.account-id")
    public static let address = SearchAttributeKey("wallet-core.address")
    public static let addressName = SearchAttributeKey("wallet-core.address-name")
    public static let chain = SearchAttributeKey("wallet-core.chain")
    public static let domain = SearchAttributeKey("wallet-core.domain")
    public static let iconURL = SearchAttributeKey("wallet-core.icon-url")
    public static let inputAddressOrDomain = SearchAttributeKey("wallet-core.input-address-or-domain")
    public static let isResolvingDomain = SearchAttributeKey("wallet-core.is-resolving-domain")
    public static let network = SearchAttributeKey("wallet-core.network")
    public static let opensExternally = SearchAttributeKey("wallet-core.opens-externally")
    public static let tokenSlug = SearchAttributeKey("wallet-core.token-slug")
    public static let url = SearchAttributeKey("wallet-core.url")
}

enum WalletCoreApplicationIdentity {
    static func canonicalID(url: String) -> String {
        let fallback = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let parsedURL = URL(string: fallback),
              let rawHost = parsedURL.host?.lowercased() else {
            return fallback
        }

        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        if host == "t.me" || host == "telegram.me" {
            let username = parsedURL.pathComponents
                .first { $0 != "/" }?
                .lowercased()
            return username.map { "t.me/\($0)" } ?? "t.me"
        }
        return host
    }

    static func hostAlias(url: String) -> String? {
        guard let parsedURL = URL(string: url),
              let rawHost = parsedURL.host?.lowercased() else {
            return nil
        }
        return rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
    }
}

func makeSearchFields(
    _ candidates: [(String?, SearchFieldKind, SearchFieldMatchPolicy)]
) -> [SearchField] {
    var seen = Set<SearchField>()
    return candidates.compactMap { value, kind, policy in
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        let field = SearchField(value, kind: kind, matchPolicy: policy)
        return seen.insert(field).inserted ? field : nil
    }
}

func makeSearchAttributes(
    _ candidates: [(SearchAttributeKey, String?)]
) -> [SearchAttribute] {
    var seen = Set<SearchAttributeKey>()
    return candidates.compactMap { key, value in
        guard seen.insert(key).inserted,
              let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return SearchAttribute(key: key, value: value)
    }
}
