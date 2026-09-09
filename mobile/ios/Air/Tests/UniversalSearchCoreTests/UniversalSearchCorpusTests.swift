import Foundation
import Testing
import UniversalSearchCore

@Suite("Universal Search source snapshots")
struct UniversalSearchCorpusTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test
    func `recommendation source enriches trusted local document`() throws {
        let entityID = SearchEntityID("token:ton:gram")
        let localDocument = SearchDocument(
            id: entityID,
            kind: .token,
            fields: [.init("Gram", kind: .title)],
            signals: .init(traits: [.held], baseCurrencyValue: 100)
        )
        let backendReplacement = SearchDocument(
            id: entityID,
            kind: .token,
            fields: [.init("Untrusted replacement", kind: .title)]
        )
        let recommendation = SearchRankedSignal(
            source: SearchSourceID("backend:trending"),
            rank: 2
        )
        let corpus = UniversalSearchCorpus(snapshots: [
            snapshot(
                id: "wallet-core",
                authority: 100,
                documents: [localDocument]
            ),
            snapshot(
                id: "backend:trending",
                authority: 10,
                documents: [backendReplacement],
                contributions: [
                    .init(
                        entityID: entityID,
                        signals: .init(
                            traits: [.trending],
                            recommendation: recommendation
                        )
                    ),
                ]
            ),
        ])

        let document = try #require(corpus.documents(at: now).first)

        #expect(document.fields.first?.value == "Gram")
        #expect(document.signals.traits.contains([.held, .trending]))
        #expect(document.signals.baseCurrencyValue == 100)
        #expect(document.signals.recommendation == recommendation)
    }

    @Test
    func `replacing or removing snapshot cannot leave stale signals behind`() throws {
        let entityID = SearchEntityID("app:wallet")
        let document = SearchDocument(
            id: entityID,
            kind: .application,
            fields: [.init("Wallet", kind: .title)]
        )
        let local = snapshot(id: "local", authority: 100, documents: [document])
        let recommendation = snapshot(
            id: "backend",
            authority: 10,
            contributions: [
                .init(
                    entityID: entityID,
                    signals: .init(recommendation: .init(
                        source: SearchSourceID("backend"),
                        score: 1
                    ))
                ),
            ]
        )
        var corpus = UniversalSearchCorpus(snapshots: [local, recommendation])

        #expect(corpus.documents(at: now).first?.signals.recommendation != nil)

        corpus.replace(snapshot(id: "backend", authority: 10))
        #expect(corpus.documents(at: now).first?.signals.recommendation == nil)

        corpus.replace(recommendation)
        corpus.remove(sourceID: SearchSourceID("backend"))
        #expect(corpus.documents(at: now).first?.signals.recommendation == nil)
    }

    @Test
    func `expired snapshots disappear while stale snapshots remain usable`() {
        let expiredDocument = SearchDocument(
            id: SearchEntityID("token:expired"),
            kind: .token,
            fields: [.init("Expired", kind: .title)]
        )
        let staleDocument = SearchDocument(
            id: SearchEntityID("token:stale"),
            kind: .token,
            fields: [.init("Stale", kind: .title)]
        )
        let corpus = UniversalSearchCorpus(snapshots: [
            snapshot(
                id: "expired",
                authority: 10,
                expiresAt: now.addingTimeInterval(-1),
                documents: [expiredDocument]
            ),
            snapshot(
                id: "stale",
                authority: 10,
                expiresAt: now.addingTimeInterval(-1),
                staleUntil: now.addingTimeInterval(10),
                documents: [staleDocument]
            ),
        ])

        #expect(corpus.documents(at: now).map(\.id) == [staleDocument.id])
        #expect(corpus.nextUsabilityBoundary(after: now) == now.addingTimeInterval(10))
        #expect(corpus.nextUsabilityBoundary(after: now.addingTimeInterval(11)) == nil)
    }

    @Test(arguments: [true, false])
    func `connection and selection signals preserve latest usage without adding counts`(
        connectionIsNewer: Bool
    ) throws {
        let entityID = SearchEntityID("application:app.1inch.io")
        let earlier = now.addingTimeInterval(-60)
        let connection = snapshot(
            id: "wallet-core:connected-apps", authority: 100,
            documents: [SearchDocument(
                id: entityID, kind: .application,
                fields: [.init("1inch", kind: .title)],
                signals: .init(traits: [.connected], interaction: .init(
                    lastSelectedAt: connectionIsNewer ? now : earlier, selectionCount: 1
                ))
            )]
        )
        let selections = snapshot(
            id: "wallet-core:interactions", authority: 100,
            contributions: [.init(entityID: entityID, signals: .init(interaction: .init(
                lastSelectedAt: connectionIsNewer ? earlier : now, selectionCount: 4
            )))]
        )
        var corpus = UniversalSearchCorpus(snapshots: [connection, selections])
        corpus.replace(connection)
        let document = try #require(corpus.documents(at: now).first)
        #expect(document.signals.interaction?.lastSelectedAt == now)
        #expect(document.signals.interaction?.selectionCount == 4)

        corpus.remove(sourceID: connection.sourceID)
        #expect(corpus.documents(at: now).isEmpty)
    }

    private func snapshot(
        id: String,
        authority: Int,
        expiresAt: Date? = nil,
        staleUntil: Date? = nil,
        documents: [SearchDocument] = [],
        contributions: [SearchSignalContribution] = []
    ) -> UniversalSearchSourceSnapshot {
        UniversalSearchSourceSnapshot(
            sourceID: SearchSourceID(id),
            authority: authority,
            generatedAt: now,
            expiresAt: expiresAt,
            staleUntil: staleUntil,
            documents: documents,
            signalContributions: contributions
        )
    }
}
