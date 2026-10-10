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
        let model = ExploreVM(fetchSites: { try self.emptySites() }, fetchDapps: { id in
            requests.dapps.append(id)
            if id == "first" {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return []
        }, accountId: { requests.accountId }, retryDelay: .milliseconds(40))
        model.reachability.stopNotifier()
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

    private func makeModel(_ requests: Requests) -> ExploreVM {
        let result = try! emptySites()
        let model = ExploreVM(fetchSites: {
            requests.sites += 1
            if requests.shouldFail { throw Failure.offline }
            return result
        }, fetchDapps: { id in
            requests.dapps.append(id)
            if requests.shouldFail { throw Failure.offline }
            return []
        }, accountId: { requests.accountId }, retryDelay: .milliseconds(40))
        model.reachability.stopNotifier()
        return model
    }

    private func emptySites() throws -> ApiExploreSitesResult {
        try JSONDecoder().decode(ApiExploreSitesResult.self, from: Data(#"{"categories":[],"sites":[]}"#.utf8))
    }

    private enum Failure: Error { case offline }

    private final class Requests {
        var sites = 0
        var dapps: [String] = []
        var shouldFail = false
        var accountId: String? = "first"
    }
}
