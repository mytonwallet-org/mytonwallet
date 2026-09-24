import Foundation
import Testing
@testable import UISettings

@Suite("Mint card video preloading")
struct MintCardVideoCacheTests {
    @Test
    func coalescesDownloadsAndReusesFilesAcrossCacheInstances() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloads = Downloads()
        let cache = MintCardVideoCache(directory: directory, download: { try await downloads.load($0) })
        #expect(await downloads.urls.isEmpty)
        async let first = cache.fileURL(for: .standard)
        async let second = cache.fileURL(for: .standard)
        let (firstURL, secondURL) = await (first, second)
        let file = try #require(firstURL)
        #expect(file == secondURL)
        #expect(try Data(contentsOf: file) == Data("video fixture".utf8))
        let reopened = MintCardVideoCache(directory: directory, download: { try await downloads.load($0) })
        #expect(await reopened.fileURL(for: .standard) == file)
        #expect(await downloads.urls.count == 1)
    }

    @Test
    func preloadsOnlyAdjacentCardsIncludingWraparound() async {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloads = Downloads()
        let cache = MintCardVideoCache(directory: directory, download: { try await downloads.load($0) })
        await cache.preloadNeighbors(of: 0)
        #expect(await Set(downloads.urls.map(\.lastPathComponent)) == ["mtw_card_black.h264.mp4", "mtw_card_silver.h264.mp4"])
        await cache.preloadNeighbors(of: 0)
        #expect(await downloads.urls.count == 2)
    }

    @Test
    func failedDownloadsCanRetryAndExpiredFilesRemainUsableOffline() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloads = Downloads()
        let cache = MintCardVideoCache(directory: directory, download: { try await downloads.load($0) })
        await downloads.failNext()
        #expect(await cache.fileURL(for: .gold) == nil)
        let file = try #require(await cache.fileURL(for: .gold))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -25 * 60 * 60)], ofItemAtPath: file.path)
        await downloads.failNext()
        #expect(await cache.fileURL(for: .gold) == file)
        #expect(await downloads.urls.count == 3)
        #expect(try Data(contentsOf: file) == Data("video fixture".utf8))
    }

    private actor Downloads {
        var urls: [URL] = []
        private var shouldFail = false

        func failNext() { shouldFail = true }

        func load(_ url: URL) async throws -> Data {
            urls.append(url)
            if shouldFail {
                shouldFail = false
                throw URLError(.notConnectedToInternet)
            }
            try await Task.sleep(for: .milliseconds(20))
            return Data("video fixture".utf8)
        }
    }
}
