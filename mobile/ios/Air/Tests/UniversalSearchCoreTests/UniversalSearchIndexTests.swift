import Foundation
import Testing
import UniversalSearchCore

@Suite("Universal Search index")
struct UniversalSearchIndexTests {
    @Test
    func `precomputed index matches direct search and preserves routing attributes`() throws {
        let attributeKey = SearchAttributeKey("test.route")
        let document = SearchDocument(
            id: SearchEntityID("token:gram"),
            kind: .token,
            fields: [SearchField("Gram Token", kind: .title)],
            attributes: [SearchAttribute(key: attributeKey, value: "gram")]
        )
        let engine = UniversalSearchEngine()
        let index = UniversalSearchIndex(documents: [document])

        let direct = engine.search("gram", in: [document])
        let indexed = engine.search("gram", in: index)
        let hit = try #require(indexed.first)

        #expect(indexed == direct)
        #expect(hit.document.attributeValue(for: attributeKey) == "gram")
    }

    @Test
    func `rebuilding with reuse carries updated signals for unchanged fields`() throws {
        let document = SearchDocument(
            id: SearchEntityID("token:gram"),
            kind: .token,
            fields: [SearchField("Gram Token", kind: .title)],
            signals: SearchSignals(baseCurrencyValue: 1)
        )
        let previous = UniversalSearchIndex(documents: [document])

        var updated = document
        updated.signals = SearchSignals(traits: [.held], baseCurrencyValue: 42)
        let rebuilt = UniversalSearchIndex(documents: [updated], reusing: previous)

        let hit = try #require(UniversalSearchEngine().search("gram", in: rebuilt).first)
        #expect(hit.document.signals.baseCurrencyValue == 42)
        #expect(hit.document.signals.traits.contains(.held))
    }

    @Test
    func `rebuilding with reuse re-normalizes changed fields`() {
        let document = SearchDocument(
            id: SearchEntityID("token:gram"),
            kind: .token,
            fields: [SearchField("Gram Token", kind: .title)]
        )
        let previous = UniversalSearchIndex(documents: [document])

        let renamed = SearchDocument(
            id: document.id,
            kind: document.kind,
            fields: [SearchField("Toncoin", kind: .title)]
        )
        let rebuilt = UniversalSearchIndex(documents: [renamed], reusing: previous)

        let engine = UniversalSearchEngine()
        #expect(engine.search("toncoin", in: rebuilt).first?.id == document.id)
        #expect(engine.search("gram", in: rebuilt).isEmpty)
    }

    @Test
    func `rebuilding after documents move or change identity finds each one`() {
        let alpha = SearchDocument(id: SearchEntityID("token:alpha"), kind: .token, fields: [SearchField("Alpha", kind: .title)])
        let beta = SearchDocument(id: SearchEntityID("token:beta"), kind: .token, fields: [SearchField("Beta", kind: .title)])
        let gamma = SearchDocument(id: SearchEntityID("token:gamma"), kind: .token, fields: [SearchField("Gamma", kind: .title)])
        let engine = UniversalSearchEngine()

        let shifted = UniversalSearchIndex(documents: [alpha, beta], reusing: UniversalSearchIndex(documents: [beta]))
        #expect(engine.search("alpha", in: shifted).map(\.id) == [alpha.id])
        #expect(engine.search("beta", in: shifted).map(\.id) == [beta.id])

        let replaced = UniversalSearchIndex(documents: [alpha, gamma], reusing: shifted)
        #expect(engine.search("gamma", in: replaced).map(\.id) == [gamma.id])
        #expect(engine.search("beta", in: replaced).isEmpty)
    }

    @Test
    func `candidate index falls back when typo changes leading gram`() {
        let document = SearchDocument(
            id: SearchEntityID("app:wallet"),
            kind: .application,
            fields: [SearchField("Wallet", kind: .title)]
        )
        let index = UniversalSearchIndex(documents: [document])

        let results = UniversalSearchEngine().search("xallet", in: index)

        #expect(results.first?.id == document.id)
        #expect(results.first?.match.kind == .fuzzy)
    }

    @Test
    func `long identifier lookup uses exact fields without incidental text matches`() {
        let address = "0:f4e4a090dbf4b4e9de7a8c8aaedef1ac89ed6f1e3d4cebd5c05a6af799c5c8c4"
        let documents = [
            SearchDocument(
                id: SearchEntityID("token:unrelated"),
                kind: .token,
                fields: [SearchField("0 Token", kind: .title)]
            ),
            SearchDocument(
                id: SearchEntityID("token:exact"),
                kind: .token,
                fields: [SearchField(address, kind: .address, matchPolicy: .exact)]
            ),
        ]
        let index = UniversalSearchIndex(documents: documents)

        let results = UniversalSearchEngine().search(address, in: index)

        #expect(results.map(\.id) == [SearchEntityID("token:exact")])
    }
}
