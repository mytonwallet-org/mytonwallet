import Foundation
import Testing
@testable import WalletCore

@Suite("Perps onboarding story media")
struct PerpsStoryMediaCacheTests {
    @Test
    func prefetchStoresPreviewsAndClipsOnceAcrossCacheInstances() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloads = Downloads()
        let cache = PerpsStoryMediaCache(directory: directory, download: { try await downloads.load($0, $1) })
        let stories = [Self.story("intro"), Self.story("long")]

        #expect(await cache.prefetch(stories))
        #expect(await downloads.requests.count == 4)
        #expect(await downloads.requests.filter { $0.1 == .video }.map(\.0) == stories.map(\.url))
        let preview = try #require(cache.cachedFile(for: stories[0].preview))
        #expect(try Data(contentsOf: preview) == Data(stories[0].preview.absoluteString.utf8))

        let reopened = PerpsStoryMediaCache(directory: directory, download: { try await downloads.load($0, $1) })
        await reopened.prefetch(stories)
        #expect(await downloads.requests.count == 4)
        #expect(reopened.cachedFile(for: stories[1].url) != nil)
    }

    @Test(arguments: [PerpsStoryMediaCache.Kind.preview, .video])
    func failedMediaStaysUncachedAndIsFetchedOnTheNextPrefetch(kind: PerpsStoryMediaCache.Kind) async {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloads = Downloads()
        let cache = PerpsStoryMediaCache(directory: directory, download: { try await downloads.load($0, $1) })
        let story = Self.story("intro")
        let failedUrl = kind == .preview ? story.preview : story.url

        await downloads.fail(failedUrl)
        #expect(await !cache.prefetch([story]))
        #expect(cache.cachedFile(for: failedUrl) == nil)

        #expect(await cache.prefetch([story]))
        #expect(cache.cachedFile(for: failedUrl) != nil)
        #expect(await downloads.requests.filter { $0.0 == failedUrl }.count == 2)
        #expect(await downloads.requests.count == 3)
    }

    @Test
    func prefetchRemovesFilesOfStoriesNoLongerServed() async {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloads = Downloads()
        let cache = PerpsStoryMediaCache(directory: directory, download: { try await downloads.load($0, $1) })
        let old = Self.story("intro", folder: "old")
        let new = Self.story("intro", folder: "new")

        await cache.prefetch([old])
        await cache.prefetch([new])
        #expect(cache.cachedFile(for: old.url) == nil)
        #expect(cache.cachedFile(for: old.preview) == nil)
        #expect(cache.cachedFile(for: new.url) != nil)
    }

    @Test(arguments: [PerpsStoryMediaCache.Kind.preview, .video])
    func supersededPrefetchKeepsCurrentMediaAndStopsSchedulingClips(kind: PerpsStoryMediaCache.Kind) async {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let downloads = Downloads()
        let cache = PerpsStoryMediaCache(directory: directory, download: { try await downloads.load($0, $1) })
        let old = [Self.story("intro", folder: "old"), Self.story("long", folder: "old")]
        let current = Self.story("intro", folder: "current")
        let pausedUrl = kind == .preview ? old[0].preview : old[0].url
        await downloads.pause(pausedUrl)
        let pending = Task { await cache.prefetch(old) }
        await downloads.waitUntilPaused(pausedUrl)

        #expect(await cache.prefetch([current]))
        await downloads.resume(pausedUrl)
        #expect(await !pending.value)

        #expect(cache.cachedFile(for: current.preview) != nil)
        #expect(cache.cachedFile(for: current.url) != nil)
        #expect(await !downloads.requests.contains { $0.0 == old[1].url })
        if kind == .preview {
            #expect(await !downloads.requests.contains { $0.0 == old[0].url })
        }
    }

    @Test
    func marketSnapshotKeepsItsCatalogueWhenStoriesCannotBeRead() throws {
        let decoder = JSONDecoder()
        let withoutStories = Data(#"{"assets":[],"assetsFetchedAt":1}"#.utf8)
        #expect(try decoder.decode(ApiPerpsMarketSnapshot.self, from: withoutStories).onboarding == nil)

        let malformed = Data(#"{"assets":[],"assetsFetchedAt":1,"onboarding":{"stories":[{"id":"intro"}]}}"#.utf8)
        let snapshot = try decoder.decode(ApiPerpsMarketSnapshot.self, from: malformed)
        #expect(snapshot.assetsFetchedAt == 1)
        #expect(snapshot.onboarding == nil)

        let story = Self.story("intro")
        let encoded = try JSONEncoder().encode(ApiPerpsMarketSnapshot(assets: [], assetsFetchedAt: 1,
                                                                      onboarding: .init(stories: [story])))
        #expect(try decoder.decode(ApiPerpsMarketSnapshot.self, from: encoded).onboarding?.stories == [story])
    }

    private static func story(_ id: String, folder: String = "h") -> ApiPerpsOnboardingStory {
        let base = URL(string: "https://s3.mywallet.io/public/perps/stories/\(folder)/")!
        return .init(id: id, url: base.appending(path: "\(id).mp4"), preview: base.appending(path: "\(id).webp"),
                     duration: 7, bytes: 1)
    }

    private actor Downloads {
        var requests: [(URL, PerpsStoryMediaCache.Kind)] = []
        private var failing: Set<URL> = []
        private var paused: Set<URL> = []
        private var pending: [URL: CheckedContinuation<Void, Never>] = [:]
        private var waiters: [URL: CheckedContinuation<Void, Never>] = [:]

        func fail(_ url: URL) { failing.insert(url) }
        func pause(_ url: URL) { paused.insert(url) }

        func waitUntilPaused(_ url: URL) async {
            guard pending[url] == nil else { return }
            await withCheckedContinuation { waiters[url] = $0 }
        }

        func resume(_ url: URL) {
            paused.remove(url)
            pending.removeValue(forKey: url)?.resume()
        }

        func load(_ url: URL, _ kind: PerpsStoryMediaCache.Kind) async throws -> Data {
            requests.append((url, kind))
            if paused.contains(url) {
                await withCheckedContinuation {
                    pending[url] = $0
                    waiters.removeValue(forKey: url)?.resume()
                }
            }
            if failing.remove(url) != nil { throw URLError(.notConnectedToInternet) }
            return Data(url.absoluteString.utf8)
        }
    }
}
