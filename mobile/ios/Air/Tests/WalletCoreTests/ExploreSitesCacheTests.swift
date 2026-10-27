import Foundation
import Testing
@testable import WalletCore

@MainActor
@Suite("Explore Sites Cache")
struct ExploreSitesCacheTests {
    @Test
    func `startup and minutely loads share the catalog until fifteen minutes`() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_000_000)
        var now = startedAt
        var requests = 0
        let cache = ExploreSitesCache(
            fetch: { _, _ in
                requests += 1
                return catalog("Catalog \(requests)")
            },
            now: { now },
            currentLanguage: { "en" }
        )

        #expect(try await cache.load(langCode: "en").featuredTitle == "Catalog 1")
        #expect(try await cache.load(langCode: "en").featuredTitle == "Catalog 1")
        for minute in 1..<15 {
            now = startedAt.addingTimeInterval(TimeInterval(minute * 60))
            #expect(try await cache.load(langCode: "en").featuredTitle == "Catalog 1")
        }
        now = startedAt.addingTimeInterval(15 * 60 - 1)
        #expect(try await cache.load(langCode: "en").featuredTitle == "Catalog 1")
        #expect(requests == 1)

        now = startedAt.addingTimeInterval(15 * 60)
        #expect(try await cache.load(langCode: "en").featuredTitle == "Catalog 2")
        #expect(requests == 2)

        #expect(try await cache.load(langCode: "en", forceRefresh: true).featuredTitle == "Catalog 2")
        #expect(requests == 2)
        now = startedAt.addingTimeInterval(16 * 60 - 1)
        #expect(try await cache.load(langCode: "en", forceRefresh: true).featuredTitle == "Catalog 2")
        #expect(requests == 2)

        now = startedAt.addingTimeInterval(16 * 60)
        #expect(try await cache.load(langCode: "en", forceRefresh: true).featuredTitle == "Catalog 3")
        #expect(try await cache.load(langCode: "en").featuredTitle == "Catalog 3")
        #expect(requests == 3)
    }

    @Test
    func `validity begins when the request finishes`() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_000_000)
        var now = startedAt
        var requests = 0
        let started = CatalogRequestGate()
        let response = CatalogRequestGate()
        let cache = ExploreSitesCache(
            fetch: { _, _ in
                requests += 1
                started.open()
                await response.wait()
                return catalog("Catalog \(requests)")
            },
            now: { now },
            currentLanguage: { "en" }
        )
        let first = Task { try await cache.load(langCode: "en") }
        await started.wait()
        now = startedAt.addingTimeInterval(10 * 60)
        response.open()
        _ = try await first.value

        now = startedAt.addingTimeInterval(25 * 60 - 1)
        #expect(try await cache.load(langCode: "en").featuredTitle == "Catalog 1")
        #expect(requests == 1)

        now = startedAt.addingTimeInterval(25 * 60)
        #expect(try await cache.load(langCode: "en").featuredTitle == "Catalog 2")
        #expect(requests == 2)
    }

    @Test
    func `parallel loads share one in flight request`() async throws {
        var requests = 0
        let started = CatalogRequestGate()
        let secondStarted = CatalogRequestGate()
        let response = CatalogRequestGate()
        let cache = ExploreSitesCache(
            fetch: { _, _ in
                requests += 1
                started.open()
                await response.wait()
                return catalog("Shared")
            },
            currentLanguage: { "en" }
        )
        let first = Task { try await cache.load(langCode: "en") }
        await started.wait()
        let second = Task {
            secondStarted.open()
            return try await cache.load(langCode: "en")
        }
        await secondStarted.wait()
        response.open()

        #expect(try await first.value.featuredTitle == "Shared")
        #expect(try await second.value.featuredTitle == "Shared")
        #expect(requests == 1)
    }

    @Test
    func `failed requests are retried and successful responses are cached`() async throws {
        var now = Date(timeIntervalSince1970: 1_000_000)
        var requests = 0
        let cache = ExploreSitesCache(
            fetch: { _, _ in
                requests += 1
                if requests == 1 || requests == 3 {
                    throw CatalogRequestError()
                }
                return catalog("Recovered")
            },
            now: { now },
            currentLanguage: { "en" }
        )

        await #expect(throws: CatalogRequestError.self) {
            try await cache.load(langCode: "en")
        }
        #expect(try await cache.load(langCode: "en").featuredTitle == "Recovered")
        #expect(try await cache.load(langCode: "en").featuredTitle == "Recovered")
        #expect(requests == 2)

        now = now.addingTimeInterval(60)
        await #expect(throws: CatalogRequestError.self) {
            try await cache.load(langCode: "en", forceRefresh: true)
        }
        #expect(try await cache.load(langCode: "en").featuredTitle == "Recovered")
        #expect(requests == 3)
    }

    @Test
    func `language keys keep separate cached responses`() async throws {
        var requestedLanguages: [String] = []
        let cache = ExploreSitesCache(
            fetch: { _, langCode in
                requestedLanguages.append(langCode)
                return catalog(langCode)
            },
            currentLanguage: { "en" }
        )

        #expect(try await cache.load(langCode: "en").featuredTitle == "en")
        #expect(try await cache.load(langCode: "ru").featuredTitle == "ru")
        #expect(try await cache.load(langCode: "en").featuredTitle == "en")
        #expect(try await cache.load(langCode: "ru").featuredTitle == "ru")
        #expect(requestedLanguages == ["en", "ru"])
    }

    @Test
    func `landscape keys keep separate cached responses`() async throws {
        var requestedOrientations: [Bool] = []
        let cache = ExploreSitesCache(
            fetch: { isLandscape, _ in
                requestedOrientations.append(isLandscape)
                return catalog(isLandscape ? "Landscape" : "Portrait")
            },
            currentLanguage: { "en" }
        )

        #expect(try await cache.load(langCode: "en").featuredTitle == "Portrait")
        #expect(try await cache.load(isLandscape: true, langCode: "en").featuredTitle == "Landscape")
        #expect(try await cache.load(langCode: "en").featuredTitle == "Portrait")
        #expect(try await cache.load(isLandscape: true, langCode: "en").featuredTitle == "Landscape")
        #expect(requestedOrientations == [false, true])
    }

    @Test
    func `changing the application language invalidates cached responses`() async throws {
        var language = "en"
        var requests = 0
        let cache = ExploreSitesCache(
            fetch: { _, langCode in
                requests += 1
                return catalog("\(langCode) \(requests)")
            },
            currentLanguage: { language }
        )

        #expect(try await cache.load(langCode: "en").featuredTitle == "en 1")
        #expect(try await cache.load(langCode: "ru").featuredTitle == "ru 2")
        language = "ru"
        #expect(try await cache.load(langCode: "ru").featuredTitle == "ru 3")
        language = "en"
        #expect(try await cache.load(langCode: "en").featuredTitle == "en 4")
        #expect(requests == 4)
    }

    @Test
    func `late responses cannot repopulate the cache after a language change`() async throws {
        var language = "en"
        var requests = 0
        let started = CatalogRequestGate()
        let oldResponse = CatalogRequestGate()
        let cache = ExploreSitesCache(
            fetch: { _, langCode in
                requests += 1
                let request = requests
                if request == 1 {
                    started.open()
                    await oldResponse.wait()
                }
                return catalog("\(langCode) \(request)")
            },
            currentLanguage: { language }
        )
        let first = Task { try await cache.load(langCode: "en") }
        await started.wait()

        language = "ru"
        #expect(try await cache.load(langCode: "ru").featuredTitle == "ru 2")
        oldResponse.open()
        _ = try await first.value

        #expect(try await cache.load(langCode: "en").featuredTitle == "en 3")
        #expect(try await cache.load(langCode: "ru").featuredTitle == "ru 2")
        #expect(requests == 3)
    }
}

private func catalog(_ title: String) -> ApiExploreSitesResult {
    ApiExploreSitesResult(featuredTitle: title, categories: [], sites: [])
}

private struct CatalogRequestError: Error {}

@MainActor
private final class CatalogRequestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
