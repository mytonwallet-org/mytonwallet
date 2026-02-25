
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
        public var items: [Item]
        public var testnetImage: Image {
            Image.airBundle("inline_testnet")
        }
    }
    
    var addressLine: AddressLine {
        let isTestnet = network == .testnet
        let leadingIcon: AddressLine.LeadingIcon? = isTemporary == true ? nil : isView ? .view : isHardware ? .ledger : nil
        var items: [AddressLine.Item] = []
        let orderedChains = orderedChains
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


public enum AvatarContent {
    case initial(String)
    case sixCharaters(String, String)
    case typeIcon(String)
    case image(String)
    // custom images, etc...
}
