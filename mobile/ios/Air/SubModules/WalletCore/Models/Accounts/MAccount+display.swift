
import UIKit
import WalletContext


public extension MAccount {
    var displayName: String {
        let displayName = if let walletName = self.title?.nilIfEmpty {
            walletName
        } else {
            formatStartEndAddress(firstAddress ?? "")
        }
        #if DEBUG
        let id = id.split(separator: "-")[0]
        return "[\(id)] \(displayName)"
        #else
        return displayName
        #endif
    }
        
    var avatarContent: AvatarContent {
        if let walletName = self.title?.nilIfEmpty, let initial = walletName.first {
            return .initial(String(initial))
        } else {
            let address = tonAddress ?? "      "
            let lastSix = address.suffix(6)
            let first = String(lastSix.prefix(3))
            let last = String(lastSix.suffix(3))
            return .sixCharaters(first, last)
        }
    }
}


public enum AvatarContent {
    case initial(String)
    case sixCharaters(String, String)
    case typeIcon(String)
    case image(String)
    // custom images, etc...
}

