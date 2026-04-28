
import UIKit
import WalletContext
import SwiftUI

public extension MAccount {
    var displayName: String {
        let displayName = if let walletName = self.title?.nilIfEmpty {
            walletName
        } else {
            formatStartEndAddress(firstAddress)
        }
        #if DEBUG
//        let id = id.split(separator: "-")[0]
//        return "[\(id)] \(displayName)"
        return displayName
        #else
        return displayName
        #endif
    }
    
    func matches(_ searchString: Regex<Substring>) -> Bool {
        if displayName.contains(searchString) { return true }
        for (_, chainInfo) in byChain {
            if chainInfo.matches(searchString) { return true }
        }
        return false
    }
        
    var avatarContent: AvatarContent {
        if let walletName = self.title?.nilIfEmpty, let initial = walletName.first {
            return .initial(String(initial))
        } else {
            let lastSix = firstAddress.suffix(6)
            let first = String(lastSix.prefix(3))
            let last = String(lastSix.suffix(3))
            return .sixCharaters(first, last)
        }
    }
    
    struct AddressLine: Equatable, Hashable {
        public var isTestnet: Bool
        public enum LeadingIcon {
            case ledger, view
            public var image: Image {
                switch self {
                case .ledger:
                    Image.airBundle("inline_ledger")
                case .view:
                    Image.airBundle("inline_view")
                }
            }
        }
        public var leadingIcon: LeadingIcon?
        public struct Item: Equatable, Hashable, Identifiable {
            public var chain: ApiChain
            public var text: String
            public var textToCopy: String
            public var isDomain: Bool
            public var isLast: Bool = false
            public var id: String { chain.rawValue }
        }
        public struct DisplayItem: Equatable, Hashable, Identifiable {
            public var item: Item
            public var showsAddress: Bool
            public var id: String { item.id }
        }
        public var items: [Item]
        public var testnetImage: Image {
            Image.airBundle("inline_testnet")
        }

        public func displayItems(maxChainCount: Int?, multichainAddressCount: Int) -> [DisplayItem] {
            let displayItems = Self.items(items, maxChainCount: maxChainCount)
            let addressCount = if displayItems.count == 1 {
                1
            } else {
                min(max(0, multichainAddressCount), displayItems.count)
            }
            return displayItems.enumerated().map { idx, item in
                DisplayItem(item: item, showsAddress: idx < addressCount)
            }
        }

        /// Builds NSAttributedString similar to `MtwCardAddressLine` (list style)
        public func attributedString(font: UIFont, color: UIColor, maxChainCount: Int? = nil, multichainAddressCount: Int = 2) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let iconSize: CGFloat = font.pointSize
            let singleChainCount = 6
            let multiChainEndCount = 6
            let displayItems = displayItems(maxChainCount: maxChainCount, multichainAddressCount: multichainAddressCount)
            let itemsCount = displayItems.count

            let attributes: [NSAttributedString.Key : Any] = [.font: font, .foregroundColor: color]
            let space = NSAttributedString(string: " ", attributes: attributes)

            func appendIcon(_ name: String) {
                guard let image = UIImage(named: name, in: AirBundle, compatibleWith: nil) else { return }
                let scaled = image.resizedToFit(size: CGSize(width: iconSize, height: iconSize))
                let attachment = NSTextAttachment()
                attachment.image = scaled.withTintColor(color, renderingMode: .alwaysOriginal)
                attachment.bounds = CGRect(x: 0, y: (font.capHeight - iconSize) / 2, width: iconSize, height: iconSize)
                result.append(NSAttributedString(attachment: attachment))
            }

            func appendSymbol(_ name: String) {
                let configuration = UIImage.SymbolConfiguration(font: font, scale: .small)
                guard let image = UIImage(named: name, in: AirBundle, compatibleWith: nil)?
                    .withConfiguration(configuration)
                    .withTintColor(color, renderingMode: .alwaysOriginal)
                else {
                    return
                }
                let attachment = NSTextAttachment(image: image)
                result.append(NSAttributedString(attachment: attachment))
            }

            if isTestnet {
                appendIcon("inline_testnet")
                result.append(space)
            }
            if let leadingIcon {
                switch leadingIcon {
                case .ledger: appendIcon("inline_ledger")
                case .view: appendIcon("inline_view")
                }
                result.append(space)
            }

            for (idx, displayItem) in displayItems.enumerated() {
                let item = displayItem.item
                if idx > 0 {
                    result.append(NSAttributedString(string: ", ", attributes: attributes))
                }
                appendSymbol("inline.chain.\(item.chain.rawValue)")
                guard displayItem.showsAddress else { continue }
                let text: String
                if item.isDomain {
                    text = item.text
                } else {
                    text = formatStartEndAddress(item.text,
                                                 prefix: itemsCount == 1 ? singleChainCount : 0,
                                                 suffix: itemsCount == 1 ? singleChainCount : multiChainEndCount)
                }
                result.append(NSAttributedString(string: text, attributes: attributes))
            }

            return result
        }

        private static func items(_ items: [Item], maxChainCount: Int?) -> [Item] {
            let limitedItems = if let maxChainCount {
                Array(items.prefix(max(0, maxChainCount)))
            } else {
                items
            }
            return limitedItems.enumerated().map { idx, item in
                var item = item
                item.isLast = idx == limitedItems.count - 1
                return item
            }
        }
    }

    func addressLine(orderedChains: [(ApiChain, AccountChain)], tokenChains: Set<ApiChain>? = nil, isGramWallet: Bool = IS_GRAM_WALLET) -> AddressLine {
        let orderedChains = Self.addressLineChains(
            orderedChains: orderedChains,
            tokenChains: tokenChains,
            isGramWallet: isGramWallet
        )
        return makeAddressLine(orderedChains: orderedChains)
    }

    static func addressLineChains(orderedChains: [(ApiChain, AccountChain)], tokenChains: Set<ApiChain>?, isGramWallet: Bool) -> [(ApiChain, AccountChain)] {
        guard
            isGramWallet,
            let tokenChains,
            tokenChains.subtracting([.ton]).isEmpty,
            let tonChain = orderedChains.first(where: { $0.0 == .ton })
        else {
            return orderedChains
        }
        return [tonChain]
    }
    
    private func makeAddressLine(orderedChains: [(ApiChain, AccountChain)]) -> AddressLine {
        let isTestnet = network == .testnet
        let leadingIcon: AddressLine.LeadingIcon? = isTemporary == true ? nil : isView ? .view : isHardware ? .ledger : nil
        var items: [AddressLine.Item] = []
        for (idx, chainInfo) in orderedChains.enumerated() {
            let (chain, info) = chainInfo
            let isDomain: Bool
            let text: String
            let textToCopy: String
            if let domain = info.domain?.nilIfEmpty {
                isDomain = true
                text = domain
                textToCopy = domain
            } else {
                isDomain = false
                text = info.address
                textToCopy = info.address
            }
            items += AddressLine.Item(
                chain: chain,
                text: text,
                textToCopy: textToCopy,
                isDomain: isDomain,
                isLast: idx == orderedChains.count - 1
            )
        }
        return AddressLine(isTestnet: isTestnet, leadingIcon: leadingIcon, items: items)
    }
}

public extension AccountContext {
    var orderedChains: [(ApiChain, AccountChain)] {
        let defaultOrderedChains = account.orderedChains
        guard defaultOrderedChains.count > 1 else {
            return defaultOrderedChains
        }

        let defaultOrder = Dictionary(uniqueKeysWithValues: defaultOrderedChains.enumerated().map { offset, element in
            (element.0, offset)
        })
        let chainBalances = balanceUsdByChain ?? [:]

        return defaultOrderedChains.sorted { lhs, rhs in
            let lhsBalance = chainBalances[lhs.0] ?? 0
            let rhsBalance = chainBalances[rhs.0] ?? 0

            if lhsBalance != rhsBalance {
                return lhsBalance > rhsBalance
            }

            return defaultOrder[lhs.0, default: Int.max] < defaultOrder[rhs.0, default: Int.max]
        }
    }

    var addressLine: MAccount.AddressLine {
        account.addressLine(orderedChains: orderedChains, tokenChains: addressLineTokenChains)
    }

    private var addressLineTokenChains: Set<ApiChain>? {
        guard let tokens = walletTokensData?.orderedTokenBalances else { return nil }
        var chains: Set<ApiChain> = []
        for token in tokens {
            guard let chain = getChainBySlug(token.tokenSlug) ?? token.token?.chain else {
                return nil
            }
            chains.insert(chain)
        }
        return chains
    }
}


public enum AvatarContent {
    case initial(String)
    case sixCharaters(String, String)
    case typeIcon(String)
    case image(String)
    // custom images, etc...
}
