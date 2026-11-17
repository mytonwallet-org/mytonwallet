import Combine
import Foundation
import WalletCore
import XCTest
@testable import UIAssets

@MainActor
final class MarketLoadingTests: XCTestCase {
    func testMissingCacheAndTokenUpdatesDoNotPublishSamples() async throws {
        let requestStarted = expectation(description: "Refresh started")
        let request = ResponseGate<ApiMarketAssetsResponse>(started: requestStarted)
        let cacheLoaded = expectation(description: "Cache loaded")
        let model = MarketScreenModel(fetchAssets: { _ in try await request.load() }, loadCachedAssets: { _ in
            cacheLoaded.fulfill()
            return nil
        })
        let unexpectedContent = expectation(description: "No fabricated content")
        unexpectedContent.isInverted = true
        let observation = model.$sections.dropFirst().filter { !$0.isEmpty }.sink { _ in unexpectedContent.fulfill() }
        model.start()
        await fulfillment(of: [requestStarted, cacheLoaded], timeout: 2)
        model.reloadTokens()
        await fulfillment(of: [unexpectedContent], timeout: 0.2)
        observation.cancel()
        XCTAssertTrue(model.sections.isEmpty)
        XCTAssertTrue(model.isLoading)

        let response = try makeResponse(id: "fresh")
        await request.complete(.success(response))
        await waitForSections(model, id: "fresh")
        XCTAssertFalse(model.isLoading)
    }

    func testDelayedCacheIsDisplayedThenReplacedByFreshContent() async throws {
        let cacheStarted = expectation(description: "Cache started")
        let cache = ResponseGate<ApiMarketAssetsResponse?>(started: cacheStarted)
        let requestStarted = expectation(description: "Refresh started")
        let request = ResponseGate<ApiMarketAssetsResponse>(started: requestStarted)
        let model = MarketScreenModel(fetchAssets: { _ in try await request.load() }, loadCachedAssets: { _ in
            try? await cache.load()
        })
        let unexpectedContent = expectation(description: "No content before cache")
        unexpectedContent.isInverted = true
        let observation = model.$sections.dropFirst().filter { !$0.isEmpty }.sink { _ in unexpectedContent.fulfill() }
        model.start()
        await fulfillment(of: [cacheStarted, requestStarted], timeout: 2)
        model.reloadTokens()
        await fulfillment(of: [unexpectedContent], timeout: 0.2)
        observation.cancel()

        await cache.complete(.success(try makeResponse(id: "cached")))
        await waitForSections(model, id: "cached")
        await request.complete(.success(try makeResponse(id: "fresh")))
        await waitForSections(model, id: "fresh")
    }

    func testFailedRefreshPreservesCachedContent() async throws {
        let cached = try makeResponse(id: "cached")
        let requestStarted = expectation(description: "Refresh started")
        let request = ResponseGate<ApiMarketAssetsResponse>(started: requestStarted)
        let model = MarketScreenModel(fetchAssets: { _ in try await request.load() }, loadCachedAssets: { _ in cached })
        model.start()
        await waitForSections(model, id: "cached")
        await fulfillment(of: [requestStarted], timeout: 2)
        let failed = expectation(description: "Refresh failed")
        let observation = model.$hasLoadFailed.filter { $0 }.sink { _ in failed.fulfill() }
        await request.complete(.failure(Failure.offline))
        await fulfillment(of: [failed], timeout: 2)
        withExtendedLifetime(observation) {}
        XCTAssertEqual(model.sections.map(\.id), ["cached"])
        XCTAssertFalse(model.isLoading)
    }

    func testFreshResponseWinsOverDelayedCache() async throws {
        let cacheStarted = expectation(description: "Cache started")
        let cacheReturned = expectation(description: "Cache returned")
        let cache = ResponseGate<ApiMarketAssetsResponse?>(started: cacheStarted)
        let fresh = try makeResponse(id: "fresh")
        let model = MarketScreenModel(fetchAssets: { _ in fresh }, loadCachedAssets: { _ in
            let response = try? await cache.load()
            cacheReturned.fulfill()
            return response
        })
        model.start()
        await waitForSections(model, id: "fresh")
        await fulfillment(of: [cacheStarted], timeout: 2)
        let rollback = expectation(description: "No cache rollback")
        rollback.isInverted = true
        let observation = model.$sections.filter { $0.first?.id == "cached" }.sink { _ in rollback.fulfill() }
        await cache.complete(.success(try makeResponse(id: "cached")))
        await fulfillment(of: [cacheReturned], timeout: 2)
        await fulfillment(of: [rollback], timeout: 0.2)
        withExtendedLifetime(observation) {}
        XCTAssertEqual(model.sections.map(\.id), ["fresh"])
    }

    func testFailureWithoutCacheCanRetryAndEmptySuccessStopsLoading() async throws {
        let requestStarted = expectation(description: "Refresh started")
        let request = ResponseGate<ApiMarketAssetsResponse>(started: requestStarted)
        let model = MarketScreenModel(fetchAssets: { _ in try await request.load() }, loadCachedAssets: { _ in nil })
        let failed = expectation(description: "Refresh failed")
        let failureObservation = model.$hasLoadFailed.filter { $0 }.prefix(1).sink { _ in failed.fulfill() }
        model.start()
        await fulfillment(of: [requestStarted], timeout: 2)
        await request.complete(.failure(Failure.offline))
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertTrue(model.sections.isEmpty)
        XCTAssertFalse(model.isLoading)
        await request.complete(.success(try JSONDecoder().decode(ApiMarketAssetsResponse.self, from: Data(#"{"sections":[]}"#.utf8))))
        let loaded = expectation(description: "Empty response loaded")
        let loadingObservation = model.$isLoading.dropFirst().filter { !$0 }.prefix(1).sink { _ in loaded.fulfill() }
        model.refreshIfNeeded()
        await fulfillment(of: [loaded], timeout: 2)
        withExtendedLifetime((failureObservation, loadingObservation)) {}
        XCTAssertFalse(model.hasLoadFailed)
        XCTAssertTrue(model.sections.isEmpty)
    }

    private func waitForSections(_ model: MarketScreenModel, id: String) async {
        let loaded = expectation(description: "Loaded \(id)")
        let observation = model.$sections.filter { $0.first?.id == id }.prefix(1).sink { _ in loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 2)
        withExtendedLifetime(observation) {}
    }

    private func makeResponse(id: String) throws -> ApiMarketAssetsResponse {
        let data = Data("""
        {"sections":[{"id":"\(id)","title":"Market","layout":"grid","hasMore":false,"assets":[
        {"newBackendId":"ton:native","slug":"toncoin","name":"Toncoin","symbol":"TON","chain":"ton","image":"","price":1,"percentChange24h":0}
        ]}]}
        """.utf8)
        return try JSONDecoder().decode(ApiMarketAssetsResponse.self, from: data)
    }

    private actor ResponseGate<Value: Sendable> {
        let started: XCTestExpectation
        private var result: Result<Value, Error>?
        private var continuation: CheckedContinuation<Value, Error>?
        private var hasStarted = false

        init(started: XCTestExpectation) { self.started = started }

        func load() async throws -> Value {
            if !hasStarted {
                hasStarted = true
                started.fulfill()
            }
            if let result { return try result.get() }
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }

        func complete(_ result: Result<Value, Error>) {
            self.result = result
            continuation?.resume(with: result)
            continuation = nil
        }
    }

    private enum Failure: Error { case offline }
}
