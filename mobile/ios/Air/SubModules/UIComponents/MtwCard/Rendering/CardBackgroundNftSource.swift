import Foundation
import WalletCore

@MainActor
enum CardBackgroundNftSource {
    private static var inFlight: [Int: Task<CardBackgroundSeed, Error>] = [:]
    private static var seeds: [Int: CardBackgroundSeed] = [:]

    static func seed(for nft: ApiNft) async throws -> CardBackgroundSeed {
        let library = try CardBackgroundLibrary.shared.get()
        // Normally all traits already arrive with the NFT and are stored by WalletCore.
        // Only older cached NFTs need a metadata request; never fetch a legacy bitmap.
        if let attributes = nft.metadata?.attributes {
            let json = try JSONEncoder().encode(["attributes": attributes])
            if let seed = try? CardBackgroundSeed.parse(String(decoding: json, as: UTF8.self), attributes: library.attributes) {
                return seed
            }
        }
        guard let number = nft.metadata?.mtwCardId, number > 0 else { throw URLError(.badURL) }
        if let seed = seeds[number] { return seed }
        if let task = inFlight[number] { return try await task.value }
        let task = Task<CardBackgroundSeed, Error> {
            if let recipe = await CardBackgroundRecipeDiskCache.shared.read(number),
               let seed = try? CardBackgroundSeed.parse(recipe, attributes: library.attributes) { return seed }
            let card = try await CardBackgroundRemoteCard.fetch(number: number, attributes: library.attributes)
            await CardBackgroundRecipeDiskCache.shared.write(card.seed.metadataJSON, number: number)
            return card.seed
        }
        inFlight[number] = task
        defer { inFlight[number] = nil }
        let seed = try await task.value
        if seeds.count >= 256 { seeds.removeAll(keepingCapacity: true) }
        seeds[number] = seed
        return seed
    }
}

private actor CardBackgroundRecipeDiskCache {
    static let shared = CardBackgroundRecipeDiskCache()
    private let directory = URL.cachesDirectory.appending(path: "CardBackgroundRecipes-v1", directoryHint: .isDirectory)

    func read(_ number: Int) -> String? {
        try? String(contentsOf: directory.appendingPathComponent("\(number).json"), encoding: .utf8)
    }

    func write(_ recipe: String, number: Int) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try recipe.write(to: directory.appendingPathComponent("\(number).json"), atomically: true, encoding: .utf8)
            let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            if files.count > 256 {
                let sorted = files.sorted {
                    let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return a < b
                }
                for file in sorted.prefix(files.count - 256) { try? manager.removeItem(at: file) }
            }
        } catch { /* Cache failure must not prevent rendering a fetched card. */ }
    }
}
