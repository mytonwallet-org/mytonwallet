import Foundation
import Testing
@testable import WalletCore

@Suite("JS bridge argument encoding")
struct JSBridgeArgumentEncodingTests {
    enum Route: CaseIterable, Sendable {
        case typed, optional, raw, void
    }

    private enum EncodingProbeError: Error {
        case observed(isMainThread: Bool)
    }

    private struct ThreadProbe: Encodable, Sendable {
        func encode(to encoder: Encoder) throws {
            throw EncodingProbeError.observed(isMainThread: Thread.isMainThread)
        }
    }

    @Test(arguments: Route.allCases) @MainActor
    func concurrentAPICallerKeepsEncodingOffMainThread(route: Route) async {
        let bridge = JSWebViewBridge()
        do {
            try await Self.callFromConcurrentAPI(bridge, route: route)
            Issue.record("Expected encoding probe")
        } catch EncodingProbeError.observed(let isMainThread) {
            #expect(!isMainThread)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(arguments: Route.allCases) @MainActor
    func mainActorCallerKeepsEncodingOnMainThread(route: Route) async {
        let bridge = JSWebViewBridge()
        do {
            try await Self.callBridge(bridge, route: route)
            Issue.record("Expected encoding probe")
        } catch EncodingProbeError.observed(let isMainThread) {
            #expect(isMainThread)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @concurrent private static func callFromConcurrentAPI(_ bridge: JSWebViewBridge, route: Route) async throws {
        try await callBridge(bridge, route: route)
    }

    private nonisolated(nonsending) static func callBridge(_ bridge: JSWebViewBridge, route: Route) async throws {
        switch route {
        case .typed:
            _ = try await bridge.callApi("encodingProbe", ThreadProbe(), decoding: Bool.self)
        case .optional:
            _ = try await bridge.callApiOptional("encodingProbe", ThreadProbe(), decodingOptional: Bool.self)
        case .raw:
            _ = try await bridge.callApiRaw("encodingProbe", ThreadProbe())
        case .void:
            try await bridge.callApiVoid("encodingProbe", ThreadProbe())
        }
    }
}
