import Kingfisher

extension WalletCoreData {
    /// Clears native downloaded data only. Account settings, credentials, SDK storage and dapp sessions are preserved.
    @MainActor public static func clearCaches() async throws {
        try await ActivityStore.clearCache()
        await TokenStore.clearCache()
        try await NftStore.clearCache()
        ImageDownloader.default.cancelAll()
        await ImageCache.default.clearCache()
    }
}
