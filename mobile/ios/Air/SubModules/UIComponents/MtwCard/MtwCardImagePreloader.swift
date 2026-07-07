import Foundation
import Kingfisher
import WalletCore

@MainActor
public enum MtwCardImagePreloader {
    private static var inFlightUrls: Set<URL> = []

    public static func preload(_ nft: ApiNft?) {
        guard let url = nft?.metadata?.mtwCardBackgroundUrl else { return }
        preload(url)
    }

    public static func preload(_ url: URL) {
        guard inFlightUrls.insert(url).inserted else { return }

        let task = KingfisherManager.shared.retrieveImage(
            with: url,
            options: [
                .backgroundDecode,
                .cacheOriginalImage,
                .alsoPrefetchToMemory,
            ]
        ) { _ in
            Task { @MainActor in
                inFlightUrls.remove(url)
            }
        }

        if task == nil {
            inFlightUrls.remove(url)
        }
    }
}
