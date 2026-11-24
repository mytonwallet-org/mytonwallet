import Foundation

/// Names the backend uses in `restrictedFeatures`; a name it sends that is not listed here is ignored.
public enum RestrictedFeature: String, CaseIterable, Sendable {
    case dexSwap
    case crossChainSwap
    case cexSwap
    case cardOnRamp
    case rubOnRamp
    case offRamp
    case nftPurchase
    case exploreSites
}
