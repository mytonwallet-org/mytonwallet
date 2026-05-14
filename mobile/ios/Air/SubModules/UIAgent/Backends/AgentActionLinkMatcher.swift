import Foundation
import WalletContext

enum AgentActionLinkMatcher {
    static let deeplinkRegex: NSRegularExpression = {
        let prefixes = compatibleActionLinkPrefixes
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\s*\\(((?:\(prefixes))[^)\\s]+)\\)$")
    }()

    private static var compatibleActionLinkPrefixes: [String] {
        var prefixes = [SELF_PROTOCOL]
        for universalUrl in SELF_UNIVERSAL_URLS {
            prefixes.append(universalUrl)
            if universalUrl.hasPrefix("https://") {
                prefixes.append("http://" + String(universalUrl.dropFirst("https://".count)))
            }
        }
        if IS_GRAM_WALLET {
            prefixes.append("mtw://")
            prefixes.append("https://my.tt/")
            prefixes.append("http://my.tt/")
            prefixes.append("https://go.mytonwallet.org/")
            prefixes.append("http://go.mytonwallet.org/")
        }
        return Array(Set(prefixes))
    }
}
