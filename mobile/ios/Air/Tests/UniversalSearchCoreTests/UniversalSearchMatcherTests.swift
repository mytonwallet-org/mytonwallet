import Testing
import UniversalSearchCore

@Suite("Universal Search matching")
struct UniversalSearchMatcherTests {
    private let matcher = UniversalSearchMatcher()

    @Test(arguments: [SearchFieldKind.keyword, .description])
    func `exact metadata phrases do not hide name matches`(metadataKind: SearchFieldKind) throws {
        let document = makeDocument(id: "token:eth", kind: .token, fields: [
            .init("Staked Ethereum", kind: .title),
            .init("Ethereum", kind: metadataKind),
        ])

        let match = try #require(matcher.match(document, query: .init("ethereum")))

        #expect(match.kind == .exactWord)
        #expect(match.fieldKind == .title)
    }

    @Test
    func `name prefixes beat exact metadata while selecting a phrase`() throws {
        let document = makeDocument(id: "token:eth", kind: .token, fields: [
            .init("Ethereum Classic", kind: .title),
            .init("eth", kind: .keyword),
        ])

        let match = try #require(matcher.match(document, query: .init("eth")))

        #expect(match.kind == .phrasePrefix)
        #expect(match.fieldKind == .title)
    }

    @Test(arguments: [
        "September update is live!", "World is Flat", "Genesis Supporter Badge",
        "Discord", "Chat",
    ])
    func `question words do not retrieve unrelated names`(title: String) {
        let document = makeDocument(id: "unrelated", kind: .application, fields: [
            .init(title, kind: .title),
            .init("This is an app. Find what you need here.", kind: .description),
        ])

        #expect(matcher.match(document, query: .init("what is staking")) == nil)
    }

    @Test
    func `question retains topic matches and original query coverage`() throws {
        let document = makeDocument(id: "token:staking", kind: .token, fields: [
            .init("Liquid Staking Token", kind: .title),
        ])

        let match = try #require(matcher.match(document, query: .init("what is staking")))

        #expect(match.kind == .exactWord)
        #expect(match.matchedTermCount == 1)
        #expect(match.totalTermCount == 3)
    }

    @Test
    func `complete names and single word queries retain common words`() {
        let document = makeDocument(id: "token:wif", kind: .token, fields: [
            .init("World is Flat", kind: .title),
        ])

        #expect(matcher.match(document, query: .init("world is flat"))?.kind == .exactPhrase)
        #expect(matcher.match(document, query: .init("world is"))?.kind == .phrasePrefix)
        #expect(matcher.match(document, query: .init("is"))?.kind == .exactWord)
        #expect(matcher.match(document, query: .init("flat is world"))?.matchedTermCount == 3)
    }

    @Test
    func `Russian question ignores common words and retains transliterated topic`() {
        let topic = makeDocument(id: "token:gram", kind: .token, fields: [
            .init("Gram", kind: .title),
        ])
        let unrelated = makeDocument(id: "app:unrelated", kind: .application, fields: [
            .init("Что нового", kind: .title),
            .init("Это приложение", kind: .description),
        ])

        #expect(matcher.match(topic, query: .init("что такое грам"))?.kind == .exactWord)
        #expect(matcher.match(unrelated, query: .init("что такое грам")) == nil)
    }

    @Test
    func `matches when at least one query term is present`() throws {
        let document = makeDocument(
            id: "token:gram",
            kind: .token,
            fields: [.init("Gram", kind: .title)]
        )

        let match = try #require(matcher.match(document, query: .init("курс грам")))

        #expect(match.kind == .exactWord)
        #expect(match.matchedTermCount == 1)
        #expect(match.totalTermCount == 2)
    }

    @Test
    func `matches across transliteration without weakening match quality`() throws {
        let document = makeDocument(
            id: "token:gram",
            kind: .token,
            fields: [.init("Gram", kind: .title)]
        )

        let match = try #require(matcher.match(document, query: .init("Грам")))

        #expect(match.kind == .exactPhrase)
        #expect(match.usedTransliteration)
    }

    @Test
    func `exact-only documents reject partial identifiers`() {
        let document = makeDocument(
            id: "wallet:external:alice.ton",
            kind: .wallet,
            fields: [.init("alice.ton", kind: .domain, matchPolicy: .exact)],
            matchRequirement: .exactIdentifier
        )

        #expect(matcher.match(document, query: .init("alice")) == nil)
        #expect(matcher.match(document, query: .init("ALICE.TON"))?.kind == .exactIdentifier)
    }

    @Test
    func `uses bounded fuzzy matching only for longer terms`() {
        let document = makeDocument(
            id: "app:wallet",
            kind: .application,
            fields: [.init("Wallet", kind: .title)]
        )

        #expect(matcher.match(document, query: .init("walet"))?.kind == .fuzzy)
        #expect(matcher.match(document, query: .init("wlt")) == nil)
    }

    @Test
    func `long identifier input only matches an exact identifier field`() {
        let address = "0:f4e4a090dbf4b4e9de7a8c8aaedef1ac89ed6f1e3d4cebd5c05a6af799c5c8c4"
        let unrelated = makeDocument(
            id: "token:unrelated",
            kind: .token,
            fields: [.init("0 Token", kind: .title)]
        )
        let exact = makeDocument(
            id: "token:exact",
            kind: .token,
            fields: [.init(address, kind: .address, matchPolicy: .exact)]
        )

        #expect(matcher.match(unrelated, query: .init(address)) == nil)
        #expect(matcher.match(exact, query: .init(address))?.kind == .exactIdentifier)
    }
}

private func makeDocument(
    id: String,
    kind: SearchEntityKind,
    fields: [SearchField],
    matchRequirement: SearchDocumentMatchRequirement = .anyTerm,
    signals: SearchSignals = .init()
) -> SearchDocument {
    SearchDocument(
        id: SearchEntityID(id),
        kind: kind,
        fields: fields,
        matchRequirement: matchRequirement,
        signals: signals
    )
}
