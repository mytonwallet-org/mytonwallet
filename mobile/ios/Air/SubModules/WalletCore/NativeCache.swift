import Foundation
import Kingfisher

extension WalletCoreData {
    @MainActor public static func configureImageCache() {
        // Decoded images share the app's memory with view caches and Metal resources.
        ImageCache.default.memoryStorage.config.totalCostLimit = min(128 * 1024 * 1024, Int(ProcessInfo.processInfo.physicalMemory / 32))
        ImageCache.default.diskStorage.config.sizeLimit = 512 * 1024 * 1024
    }

    /// Clears native downloaded data only. Account settings, credentials, SDK storage and dapp sessions are preserved.
    @MainActor public static func clearCaches() async throws {
        try await ActivityStore.clearCache()
        await TokenStore.clearCache()
        try await NftStore.clearCache()
        ImageDownloader.default.cancelAll()
        await ImageCache.default.clearCache()
    }
}
