import Foundation

/// A token asset interface. Conform your own model to this protocol
/// and pass instances via `TokenResolver.updateAssets(_:)`.
public protocol AgentAsset: Sendable {
    var slug: String { get }
    var symbol: String { get }
    var name: String { get }
    var chainId: String { get }
    var decimals: Int { get }
    var tokenAddress: String? { get }
    var priceUsd: Double? { get }
    var percentChange24h: Double? { get }
}
