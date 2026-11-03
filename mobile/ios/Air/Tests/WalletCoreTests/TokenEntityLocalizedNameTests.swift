import Foundation
import Testing
import WalletCoreTypes

@Suite("TokenEntity Search")
struct TokenEntityLocalizedNameTests {
    @Test
    func indexedAttributesIncludeAPresentationTitle() {
        guard #available(iOS 18.4, *) else { return }
        let entity = TokenEntity(token: ApiChain.solana.nativeToken)
        let attributes = entity.attributeSet
        #expect(attributes.title == "Solana")
        #expect(attributes.contentDescription == "SOL")
        #expect(attributes.keywords?.contains("SOL") == true)
    }

    @Test(arguments: [
        ("Solana", "SOL", "Solana", "SOL"),
        ("Tether USD", "USDT", "Ethereum", "USDT · Ethereum"),
        ("Toncoin", "TON", "TON", "TON"),
        ("Tron", "TRX", "TRON", "TRX"),
        ("USDT", "USDT", "Ethereum", "Ethereum"),
        ("TON", "TON", "TON", ""),
    ])
    func subtitlesAvoidRepeatingTheTitleAndNetwork(name: String, symbol: String, network: String, expected: String) {
        guard #available(iOS 18.4, *) else { return }
        let entity = TokenEntity(tokenSlug: "example", name: name, symbol: symbol, chainRawValue: "eth",
                                 chainTitle: network, tokenAddress: nil, decimals: 6, searchableKeywords: [])
        #expect(entity.attributeSet.contentDescription == expected)
    }

    @Test
    func savedCatalogUsesCurrentPresentationAndKeepsSearchKeywords() throws {
        guard #available(iOS 18.4, *) else { return }
        let original = TokenEntity(token: ApiChain.solana.nativeToken)
        var saved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        saved["contentDescription"] = "Solana SOL Solana"
        let restored = try JSONDecoder().decode(TokenEntity.self, from: JSONSerialization.data(withJSONObject: saved))
        #expect(restored.contentDescription == "SOL")
        #expect(restored.attributeSet.contentDescription == "SOL")
        #expect(restored.searchableKeywords == original.searchableKeywords)
        #expect(restored.matchesSearch("solana"))
    }

    @Test
    func tokenQueriesSupportNamesSymbolsMultiwordAndTyposWithoutAPrice() {
        let solana = ApiChain.solana.nativeToken
        let ethereumUSDT = ApiToken(slug: "eth-usdt", name: "Tether USD", symbol: "USDT", decimals: 6, chain: .ethereum)
        let tonUSDT = ApiToken(slug: "ton-usdt", name: "Tether USD", symbol: "USDT", decimals: 6, chain: .ton)
        let tokens = [solana, ethereumUSDT, tonUSDT]
        for query in ["solana", "SOL", "solna"] {
            #expect(TokenSearchMetadata.matchingTokens(query, tokens: tokens).first?.slug == solana.slug)
        }
        #expect(TokenSearchMetadata.matchingTokens("eth usdt", tokens: tokens).first?.slug == ethereumUSDT.slug)
    }

    @Test
    func `localized name is searchable without changing canonical presentation`() {
        guard #available(iOS 18.4, *) else { return }

        let token = ApiToken(
            slug: "usdt",
            name: "Tether USD",
            localizedName: "تتر",
            symbol: "USDT",
            decimals: 6,
            chain: .ton
        )

        let entity = TokenEntity(token: token)
        #expect(entity.name == "Tether USD")
        #expect(entity.apiTokenFallback.name == "Tether USD")
        #expect(entity.apiTokenFallback.localizedName == "تتر")
        #expect(entity.searchableKeywords.contains("تتر"))
        #expect(entity.matchesSearch("تت"))
    }

    @Test
    func coldMetadataPreservesAliasesAndExactContractMatching() throws {
        guard #available(iOS 18.4, *) else { return }
        let token = ApiToken(slug: "ethereum-example", name: "Example", localizedName: "مثال", symbol: "EX", decimals: 6,
                             chain: .ethereum, tokenAddress: "0x123456789abcdef", keywords: ["alias"])
        let entity = try JSONDecoder().decode(TokenEntity.self, from: JSONEncoder().encode(TokenEntity(token: token)))
        for query in ["مثال", "alias", "EX ethereum", "0x123456789abcdef"] {
            #expect(entity.matchesSearch(query))
        }
        #expect(!entity.matchesSearch("123456789"))
    }
}
