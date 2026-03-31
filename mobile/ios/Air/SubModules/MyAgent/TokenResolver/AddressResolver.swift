import Foundation

/// Resolves named addresses in intents to the correct chain.
///
/// When the LLM returns a wallet name (e.g. "Main") instead of a raw address,
/// this resolver looks up the name in the user's wallet addresses and replaces it
/// with the raw address — preferring the address on the token's chain.
public struct AddressResolver: Sendable {
    private let tokenResolver: TokenResolver

    public init(tokenResolver: TokenResolver) {
        self.tokenResolver = tokenResolver
    }

    /// Resolve named addresses in an intent against the user's wallet addresses and saved addresses.
    ///
    /// Handles both `intent.to` (sendToken) and `intent.address` (receive).
    /// If a field matches a user address or saved address name, it is replaced with the raw address.
    /// When the token's chain is known, the address on that chain is preferred.
    /// Otherwise falls back to the first name match.
    public func resolve(
        intent: Intent,
        userAddresses: [any AgentUserAddress],
        savedAddresses: [any AgentUserAddress] = []
    ) async -> Intent {
        guard !userAddresses.isEmpty || !savedAddresses.isEmpty else { return intent }

        let combined = userAddresses + savedAddresses

        // Resolve the token's chain once (used for both fields)
        let tokenChain = await resolveTokenChain(intent.token)

        var result = intent

        // Resolve `to` field (sendToken) — check saved addresses first (more likely recipients),
        // then user addresses
        if let resolved = resolveField(result.to, userAddresses: savedAddresses, tokenChain: tokenChain)
            ?? resolveField(result.to, userAddresses: userAddresses, tokenChain: tokenChain) {
            result = result.replacing(to: resolved)
        }

        // Resolve `address` field (receive) — user addresses first (own wallets for receiving)
        if let resolved = resolveField(result.address, userAddresses: combined, tokenChain: tokenChain) {
            result = result.replacing(address: resolved)
        }

        return result
    }

    /// Resolve addresses in all intents from a classification result.
    public func resolve(
        intents: [Intent],
        userAddresses: [any AgentUserAddress],
        savedAddresses: [any AgentUserAddress] = []
    ) async -> [Intent] {
        var resolved: [Intent] = []
        for intent in intents {
            resolved.append(await resolve(intent: intent, userAddresses: userAddresses, savedAddresses: savedAddresses))
        }
        return resolved
    }

    // MARK: - Private

    /// Resolve a field value (name or raw address) to the correct chain's raw address.
    ///
    /// 1. Match by name → pick the address on the token's chain, or fall back to first match.
    /// 2. Match by raw address → if the matched address is on a different chain than the token,
    ///    find another address with the same name on the token's chain.
    private func resolveField(_ value: String?, userAddresses: [any AgentUserAddress], tokenChain: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }

        let valueLower = value.lowercased()

        // 1. Try matching by name
        let nameMatches = userAddresses.filter { $0.name.lowercased() == valueLower }
        if !nameMatches.isEmpty {
            if let chain = tokenChain {
                let prefix = chain.lowercased() + ":"
                for wallet in nameMatches {
                    if let addrStr = wallet.addresses.first(where: { $0.lowercased().hasPrefix(prefix) }) {
                        return String(addrStr.dropFirst(prefix.count))
                    }
                }
            }
            // Fallback: return first address (strip chain prefix)
            if let first = nameMatches[0].addresses.first {
                let parts = first.split(separator: ":", maxSplits: 1)
                return parts.count == 2 ? String(parts[1]) : first
            }
            return nil
        }

        // 2. Try matching by raw address — check for chain mismatch
        if let chain = tokenChain {
            let targetPrefix = chain.lowercased() + ":"
            for wallet in userAddresses {
                // Check if this wallet contains the value as an address on a non-target chain
                let containsOnOtherChain = wallet.addresses.contains(where: { addrStr in
                    let parts = addrStr.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { return false }
                    return String(parts[1]) == value && parts[0].lowercased() != chain
                })
                if containsOnOtherChain {
                    // Find the address on the target chain in the same wallet
                    if let addrStr = wallet.addresses.first(where: { $0.lowercased().hasPrefix(targetPrefix) }) {
                        return String(addrStr.dropFirst(targetPrefix.count))
                    }
                }
            }
        }

        return value
    }

    /// Resolve a token query to its chain (lowercased), or nil if unknown.
    private func resolveTokenChain(_ token: String?) async -> String? {
        guard let asset = await tokenResolver.resolve(token) else { return nil }
        return asset.chainId.lowercased()
    }
}
