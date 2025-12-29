import Foundation

public enum ScanResult {
    case url(url: URL)
    case address(address: String, possibleChains: [ApiChain])
}
