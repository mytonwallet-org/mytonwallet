import Foundation
import WalletCoreTypes

public enum ScanResult: Sendable {
    case url(url: URL)
    case address(address: String, possibleChains: [ApiChain])
}
