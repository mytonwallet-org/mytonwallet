import Foundation

/// A user's wallet, used for intent classification context.
public protocol AgentUserAddress: Sendable {
    var name: String { get }
    var addresses: [String] { get }  // e.g. ["ton:UQ...", "solana:addr", "tron:addr"]
}
