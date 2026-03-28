import Foundation

/// Resolves token queries to `Asset` objects using fuzzy matching.
///
/// The library does NOT fetch assets — the caller is responsible for providing them
/// via `updateAssets(_:)`. This keeps the library free of network dependencies.
///
/// ```swift
/// let resolver = TokenResolver()
/// await resolver.updateAssets(myFetchedAssets)
/// let asset = await resolver.resolve("TON")
/// ```
public actor TokenResolver {

    private var assets: [any AgentAsset] = []
    private var bySymbol: [String: any AgentAsset] = [:]
    private var byName: [String: any AgentAsset] = [:]

    public init() {}

    /// Update the asset list. Call this whenever you fetch fresh data.
    public func updateAssets(_ newAssets: [any AgentAsset]) {
        var newBySymbol: [String: any AgentAsset] = [:]
        var newByName: [String: any AgentAsset] = [:]
        for asset in newAssets {
            let symbol = asset.symbol.uppercased()
            let name = asset.name.lowercased()
            if !symbol.isEmpty && newBySymbol[symbol] == nil {
                newBySymbol[symbol] = asset
            }
            if !name.isEmpty && newByName[name] == nil {
                newByName[name] = asset
            }
        }

        self.assets = newAssets
        self.bySymbol = newBySymbol
        self.byName = newByName
    }

    /// Resolve a token query to a full Asset. Handles fuzzy/plural matching.
    /// Returns nil if not found.
    public func resolve(_ query: String?) -> (any AgentAsset)? {
        guard let query = query?.trimmingCharacters(in: .whitespaces), !query.isEmpty else {
            return nil
        }
        return fuzzyMatch(query)
    }

    /// Convenience: resolve to just the slug.
    public func resolveSlug(_ query: String?) -> String? {
        resolve(query)?.slug
    }

    private func fuzzyMatch(_ query: String) -> (any AgentAsset)? {
        let normQuery = normalize(query)
        guard !normQuery.isEmpty else { return nil }

        // 1. Exact symbol match
        if let asset = bySymbol[query.uppercased()] {
            return asset
        }

        // 2. Exact name match
        if let asset = byName[query.lowercased()] {
            return asset
        }

        // 3. Normalized symbol match
        for (symbol, asset) in bySymbol {
            if normalize(symbol) == normQuery {
                return asset
            }
        }

        // 4. Normalized name match
        for (name, asset) in byName {
            if normalize(name) == normQuery {
                return asset
            }
        }

        // 5. Singular fallback: strip trailing 's' from query only (e.g., "notcoins" -> "notcoin")
        if normQuery.count > 3 && normQuery.hasSuffix("s") {
            let singular = String(normQuery.dropLast())
            for (symbol, asset) in bySymbol where normalize(symbol) == singular {
                return asset
            }
            for (name, asset) in byName where normalize(name) == singular {
                return asset
            }
        }

        return nil
    }

    /// Normalize a token query: lowercase, strip non-alphanumeric.
    private func normalize(_ text: String) -> String {
        let result = text.lowercased().trimmingCharacters(in: .whitespaces)
        return result.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
