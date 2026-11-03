import AppIntents
import AppIntentsTesting
import XCTest

/// Runs against the app process and the system index, not TokenEntityQuery directly.
@available(iOS 27.0, *)
@MainActor
final class TokenSpotlightTests: XCTestCase {
    private let definitions = IntentDefinitions(bundleIdentifier: "org.mytonwallet.app")

    func testSystemSearchIntentAcceptsAQuery() async throws {
        let intent = definitions.intents["SearchInWalletIntent"].makeIntent(
            criteria: StringSearchCriteria(term: "solana")
        )
        try await intent.run()
    }

    func testSolanaIsIndexedOnceAndResolvesAfterRelaunch() async throws {
        let app = XCUIApplication(bundleIdentifier: "org.mytonwallet.app")
        app.launch()
        let tokens = definitions.entities["TokenEntity"]
        let matching = try await tokens.entities(matching: "solana")
        let solana = try XCTUnwrap(try matching.first { entity in
            let symbol: String = try entity.symbol
            return symbol == "SOL"
        })
        for query in ["solana", "SOL"] {
            var found = false
            // Core Spotlight commits asynchronously after the app's donation completes.
            for _ in 0..<30 {
                let indexed = try await tokens.spotlightQuery(query)
                let matches = indexed.filter { $0.identifier == solana.identifier }
                if matches.count == 1 { found = true; break }
                XCTAssertLessThanOrEqual(matches.count, 1, "Duplicate token results")
                try await Task.sleep(for: .seconds(1))
            }
            XCTAssertTrue(found, "No native Solana result for \(query)")
        }
        app.terminate()
        app.launch()
        let resolved = try await tokens.entities(matching: "SOL")
        XCTAssertTrue(resolved.contains { $0.identifier == solana.identifier })
        let name: String = try solana.name
        XCTAssertEqual(name, "Solana")
    }
}
