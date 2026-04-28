import Foundation
import WalletCore

enum PortfolioPalette {
    static let defaultColors: [String] = [
        "#3497ED",
        "#2373DB",
        "#9ED448",
        "#5FB641",
        "#F5BD25",
        "#F79E39",
        "#E65850",
        "#5D5CDC",
    ]

    static let native = "#3497ED"
    static let stable = "#5FB641"
    static let altcoins = "#F79E39"

    static func color(at index: Int) -> String {
        defaultColors[index % defaultColors.count]
    }

    static func chainColor(for chain: ApiChain) -> String {
        switch chain {
        case .ton:
            return "#3497ED"
        case .tron:
            return "#E65850"
        case .solana:
            return "#5D5CDC"
        default:
            return color(at: 0)
        }
    }

    static func normalize(color: String?) -> String? {
        guard let trimmed = color?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }

        if trimmed.hasPrefix("#") {
            return trimmed
        }

        return "#\(trimmed)"
    }
}
