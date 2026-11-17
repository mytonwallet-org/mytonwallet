import Dependencies
import Foundation
import WalletCore
import XCTest
@testable import UIBrowser

@MainActor
final class ExplorePreparationTests: XCTestCase {
    override func invokeTest() {
        withDependencies {
            $0.context = .live
        } operation: {
            super.invokeTest()
        }
    }

    func testSuccessfulPreparationIncludingEmptyResultsIsReusedOnAppearance() async throws {
        let requests = Requests()
        let model = makeModel(requests)
        model.refresh()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(requests.sites, 1)
        XCTAssertEqual(requests.dapps, ["first"])
        model.setActive(true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(requests.sites, 1)
        XCTAssertEqual(requests.dapps, ["first"])
    }

    func testFailedPreparationDoesNotRetryUntilActiveAndStopsWhenHidden() async throws {
        let requests = Requests()
        requests.shouldFail = true
        let model = makeModel(requests)
        model.refresh()
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(requests.sites, 1)
        XCTAssertEqual(requests.dapps.count, 1)
        model.setActive(true)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertGreaterThan(requests.sites, 2)
        XCTAssertGreaterThan(requests.dapps.count, 2)
        model.setActive(false)
        // Hiding cancels retries, but an already queued data request may finish.
        try await Task.sleep(for: .milliseconds(180))
        let siteCount = requests.sites
        let dappCount = requests.dapps.count
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(requests.sites, siteCount)
        XCTAssertEqual(requests.dapps.count, dappCount)
    }

    func testHiddenAccountChangesInvalidatePreparationAndIgnoreLateResults() async throws {
        let requests = Requests()
        var pending: CheckedContinuation<[ApiDapp], any Error>?
        let model = ExploreVM(getCachedSites: { nil }, fetchSites: { try self.emptySites() }, fetchDapps: { id in
            requests.dapps.append(id)
            if id == "first" {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return []
        }, accountId: { requests.accountId }, retryDelay: .milliseconds(40))
        model.reachability.stopNotifier()
        model.reachability.whenReachable?(model.reachability)
        model.refresh()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(pending)
        requests.accountId = "second"
        model.walletCore(event: .accountChanged(accountId: "second", isNew: false))
        XCTAssertEqual(requests.dapps, ["first"])
        model.setActive(true)
        try await Task.sleep(for: .milliseconds(50))
        pending?.resume(throwing: Failure.offline)
        model.setActive(false)
        model.setActive(true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(requests.dapps, ["first", "second"])
    }

    func testActiveRetryDoesNotRetainItsModel() async throws {
        let requests = Requests()
        requests.shouldFail = true
        var model: ExploreVM? = makeModel(requests)
        weak var weakModel = model
        model?.setActive(true)
        try await Task.sleep(for: .milliseconds(20))
        model = nil
        XCTAssertNil(weakModel)
        let count = requests.sites
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(requests.sites, count)
    }

    func testCachedCatalogIsAvailableImmediatelyAndSurvivesFailedRefresh() async throws {
        let result = try makeCatalog()
        let requests = Requests()
        let model = ExploreVM(getCachedSites: { result }, fetchSites: {
            requests.sites += 1
            throw Failure.offline
        }, fetchDapps: { _ in [] }, accountId: { nil }, retryDelay: .milliseconds(40))
        model.reachability.stopNotifier()
        model.reachability.whenReachable?(model.reachability)
        XCTAssertEqual(model.exploreSites.values.first?.name, "Cached site")
        XCTAssertEqual(model.loadingState, .loaded)
        model.refresh()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(requests.sites, 1)
        XCTAssertEqual(model.exploreSites.values.first?.name, "Cached site")
        XCTAssertEqual(model.loadingState, .loaded)
        model.setActive(true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(requests.sites, 1)
        model.setActive(false)
    }

    func testCachedCatalogRefreshesSilentlyWhenConnectivityReturns() async throws {
        let cached = try makeCatalog()
        var updated = cached
        updated.featuredTitle = "Updated"
        var requestCount = 0
        var pending: CheckedContinuation<ApiExploreSitesResult, any Error>?
        let model = ExploreVM(getCachedSites: { cached }, fetchSites: {
            requestCount += 1
            if requestCount == 1 { throw Failure.offline }
            return try await withCheckedThrowingContinuation { pending = $0 }
        }, fetchDapps: { _ in [] }, accountId: { nil }, retryDelay: .milliseconds(40))
        model.reachability.stopNotifier()
        let whenReachable = model.reachability.whenReachable
        let whenUnreachable = model.reachability.whenUnreachable
        model.reachability.whenReachable = nil
        model.reachability.whenUnreachable = nil
        whenUnreachable?(model.reachability)
        model.setActive(true)
        defer { model.setActive(false) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(model.loadingState, .loaded)
        XCTAssertEqual(model.exploreSites.values.first?.name, "Cached site")
        whenReachable?(model.reachability)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(requestCount, 2)
        XCTAssertNotNil(pending)
        XCTAssertEqual(model.loadingState, .loaded)
        XCTAssertEqual(model.featuredTitle, "Cached")
        pending?.resume(returning: updated)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.loadingState, .loaded)
        XCTAssertEqual(model.featuredTitle, "Updated")
    }

    func testUncachedFailureShowsRetryAndSuccessfulRetryReplacesIt() async throws {
        let requests = Requests()
        requests.shouldFail = true
        let model = makeModel(requests)
        XCTAssertEqual(model.loadingState, .loading)
        model.refresh()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.loadingState, .failed)
        requests.shouldFail = false
        model.refresh()
        XCTAssertEqual(model.loadingState, .loading)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.loadingState, .loaded)
        XCTAssertEqual(requests.sites, 2)
    }

    func testInitialUnresolvedNetworkPathKeepsLoadingUntilTheRequestFails() async throws {
        let model = ExploreVM(getCachedSites: { nil }, fetchSites: {
            throw Failure.offline
        }, fetchDapps: { _ in [] }, accountId: { nil })
        model.reachability.stopNotifier()
        model.reachability.whenUnreachable?(model.reachability)
        // Stopping the monitor does not cancel already queued path updates
        model.reachability.whenReachable = nil
        model.reachability.whenUnreachable = nil
        XCTAssertEqual(model.loadingState, .loading)
        model.refresh()
        XCTAssertEqual(model.loadingState, .loading)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.loadingState, .offline)
    }

    func testRetryPreservesOfflineFallbackWhileRequestIsPending() async throws {
        var requestCount = 0
        var pending: CheckedContinuation<ApiExploreSitesResult, any Error>?
        let model = ExploreVM(getCachedSites: { nil }, fetchSites: {
            requestCount += 1
            return try await withCheckedThrowingContinuation { pending = $0 }
        }, fetchDapps: { _ in [] }, accountId: { nil })
        model.reachability.stopNotifier()
        let whenReachable = model.reachability.whenReachable
        let whenUnreachable = model.reachability.whenUnreachable
        model.reachability.whenReachable = nil
        model.reachability.whenUnreachable = nil
        whenReachable?(model.reachability)
        model.refresh()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(pending)
        whenUnreachable?(model.reachability)
        XCTAssertEqual(model.loadingState, .offline)
        model.refresh()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(model.loadingState, .offline)
        whenReachable?(model.reachability)
        XCTAssertEqual(model.loadingState, .loading)
        pending?.resume(returning: try emptySites())
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.loadingState, .loaded)
    }

    func testBrowsingAlwaysIncludesStatusWhenNoVisibleCatalogIsAvailable() throws {
        for state: ExploreVM.LoadingState in [.loading, .failed, .offline, .loaded] {
            let sections = ExploreVC.makeBrowsingSections(
                connectedDapps: [], featuredTitle: nil, exploreSites: [], siteCategories: [],
                shouldRestrictSites: false, isLockdownModeEnabled: false, loadingState: state
            )
            XCTAssertEqual(sections.count, 1)
            XCTAssertEqual(sections.first?.items, [.loadingStatus(state)])
        }
    }

    private func makeModel(_ requests: Requests) -> ExploreVM {
        let result = try! emptySites()
        let model = ExploreVM(getCachedSites: { nil }, fetchSites: {
            requests.sites += 1
            if requests.shouldFail { throw Failure.offline }
            return result
        }, fetchDapps: { id in
            requests.dapps.append(id)
            if requests.shouldFail { throw Failure.offline }
            return []
        }, accountId: { requests.accountId }, retryDelay: .milliseconds(40))
        model.reachability.stopNotifier()
        model.reachability.whenReachable?(model.reachability)
        return model
    }

    private func emptySites() throws -> ApiExploreSitesResult {
        try JSONDecoder().decode(ApiExploreSitesResult.self, from: Data(#"{"categories":[],"sites":[]}"#.utf8))
    }

    private func makeCatalog() throws -> ApiExploreSitesResult {
        try JSONDecoder().decode(ApiExploreSitesResult.self, from: Data(#"{"featuredTitle":"Cached","categories":[{"id":1,"name":"Games"}],"sites":[{"url":"https://example.com","name":"Cached site","icon":"","description":"","categoryId":1,"canBeRestricted":false}]}"#.utf8))
    }

    private enum Failure: Error { case offline }

    private final class Requests {
        var sites = 0
        var dapps: [String] = []
        var shouldFail = false
        var accountId: String? = "first"
    }
}
