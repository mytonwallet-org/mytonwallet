import Dependencies
import Foundation
import WalletCore
import XCTest
@testable import AirAsFramework

@MainActor
final class PerpsOnboardingPrefetchTests: XCTestCase {
    override func invokeTest() {
        withDependencies {
            $0.context = .live
        } operation: {
            super.invokeTest()
        }
    }

    func testIncompletePrefetchRetriesTheSameCatalogue() async {
        var attempts = 0
        let coordinator = PerpsCoordinator(accountId: "wallet", prefetchStories: { _ in
            attempts += 1
            return attempts > 1
        })
        let onboarding = makeOnboarding("intro")

        await coordinator.prefetchOnboarding(onboarding)?.value
        await coordinator.prefetchOnboarding(onboarding)?.value
        XCTAssertEqual(attempts, 2)

        await coordinator.prefetchOnboarding(onboarding)?.value
        XCTAssertEqual(attempts, 2)
    }

    func testRepeatedUpdatesShareThePendingPrefetch() async {
        var attempts = 0
        var response: CheckedContinuation<Bool, Never>?
        let started = expectation(description: "Prefetch started")
        let coordinator = PerpsCoordinator(accountId: "wallet", prefetchStories: { _ in
            attempts += 1
            guard attempts == 1 else { return true }
            return await withCheckedContinuation {
                response = $0
                started.fulfill()
            }
        })
        let onboarding = makeOnboarding("intro")
        let pending = coordinator.prefetchOnboarding(onboarding)
        await fulfillment(of: [started], timeout: 2)

        await coordinator.prefetchOnboarding(onboarding)?.value
        XCTAssertEqual(attempts, 1)
        response?.resume(returning: true)
        await pending?.value

        await coordinator.prefetchOnboarding(onboarding)?.value
        XCTAssertEqual(attempts, 1)
    }

    func testSupersededFailureDoesNotClearANewerSuccessForTheSameCatalogue() async {
        var attempts = 0
        var response: CheckedContinuation<Bool, Never>?
        let started = expectation(description: "First prefetch started")
        let coordinator = PerpsCoordinator(accountId: "wallet", prefetchStories: { _ in
            attempts += 1
            guard attempts == 1 else { return true }
            return await withCheckedContinuation {
                response = $0
                started.fulfill()
            }
        })
        let onboarding = makeOnboarding("intro")
        let pending = coordinator.prefetchOnboarding(onboarding)
        await fulfillment(of: [started], timeout: 2)

        await coordinator.prefetchOnboarding(makeOnboarding("long"))?.value
        await coordinator.prefetchOnboarding(onboarding)?.value
        response?.resume(returning: false)
        await pending?.value

        await coordinator.prefetchOnboarding(onboarding)?.value
        XCTAssertEqual(attempts, 3)
    }

    private func makeOnboarding(_ id: String) -> ApiPerpsOnboarding {
        let base = URL(string: "https://s3.mywallet.io/public/perps/stories/h/")!
        return .init(stories: [.init(id: id, url: base.appending(path: "\(id).mp4"),
                                     preview: base.appending(path: "\(id).webp"), duration: 7, bytes: 1)])
    }
}
