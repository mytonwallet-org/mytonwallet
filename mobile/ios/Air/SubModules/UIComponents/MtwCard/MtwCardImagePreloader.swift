import Foundation
import WalletCore

@MainActor
public enum MtwCardImagePreloader {
    private static var inFlightNumbers: Set<Int> = []

    public static func preload(_ nft: ApiNft?) {
        guard let nft, let number = nft.metadata?.mtwCardId, inFlightNumbers.insert(number).inserted else { return }
        Task { @MainActor in
            defer { inFlightNumbers.remove(number) }
            guard let seed = try? await CardBackgroundNftSource.seed(for: nft) else { return }
            _ = try? CardBackgroundRenderer.shared.image(seed: seed)
        }
    }
}
