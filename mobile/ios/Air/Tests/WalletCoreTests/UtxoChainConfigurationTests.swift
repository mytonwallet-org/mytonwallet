import Testing
import WalletContext
import WalletCoreTypes

@Suite("UTXO Chain Configuration")
struct UtxoChainConfigurationTests {
    @Test
    func `supported chain order includes utxo chains in display order`() {
        #expect(ApiChain.allCases == [
            .bitcoin,
            .ethereum,
            .solana,
            .hyperliquid,
            .ton,
            .tron,
            .bnb,
            .base,
            .robinhood,
            .arc,
            .monad,
            .arbitrum,
            .polygon,
            .avalanche,
            .dogecoin,
            .litecoin,
            .bitcoincash,
        ])
    }

    @Test
    func `utxo raw values round trip`() throws {
        let chains: [ApiChain] = [.bitcoin, .litecoin, .bitcoincash, .dogecoin]

        for chain in chains {
            #expect(ApiChain(rawValue: chain.rawValue) == chain)
        }
    }

    @Test
    func `utxo native tokens match backend metadata`() {
        #expect(ApiChain.bitcoin.nativeToken == .BITCOIN)
        #expect(ApiChain.litecoin.nativeToken == .LITECOIN)
        #expect(ApiChain.bitcoincash.nativeToken == .BITCOINCASH)
        #expect(ApiChain.dogecoin.nativeToken == .DOGECOIN)

        #expect(ApiChain.bitcoin.nativeToken.decimals == 8)
        #expect(ApiChain.litecoin.nativeToken.decimals == 8)
        #expect(ApiChain.bitcoincash.nativeToken.decimals == 8)
        #expect(ApiChain.dogecoin.nativeToken.decimals == 8)
    }

    @Test
    func `utxo address patterns accept fee check addresses and prefixes`() {
        let chains: [ApiChain] = [.bitcoin, .litecoin, .bitcoincash, .dogecoin]

        for chain in chains {
            #expect(chain.addressRegex.matches(chain.feeCheckAddress))
        }

        #expect(ApiChain.bitcoin.addressPrefixRegex.matches("bc1q"))
        #expect(ApiChain.litecoin.addressPrefixRegex.matches("ltc1q"))
        #expect(ApiChain.bitcoincash.addressPrefixRegex.matches("Q"))
        #expect(ApiChain.dogecoin.addressPrefixRegex.matches("DH"))
    }

    @Test
    func `utxo derivation paths and explorers match web configuration`() {
        #expect(ApiChain.bitcoin.defaultDerivationPath == "m/86'/0'/0'/0/{index}")
        #expect(ApiChain.litecoin.defaultDerivationPath == "m/84'/2'/0'/0/{index}")
        #expect(ApiChain.bitcoincash.defaultDerivationPath == "m/44'/145'/0'/0/{index}")
        #expect(ApiChain.dogecoin.defaultDerivationPath == "m/44'/3'/0'/0/{index}")

        #expect(ApiChain.bitcoin.explorer.baseUrl[.mainnet]?.url == "https://mempool.space/")
        #expect(ApiChain.bitcoin.explorer.transaction == "{base}tx/{hash}")
        #expect(ApiChain.litecoin.explorer.baseUrl[.mainnet]?.url == "https://blockchair.com/litecoin/")
        #expect(ApiChain.bitcoincash.explorer.baseUrl[.mainnet]?.url == "https://blockchair.com/bitcoin-cash/")
        #expect(ApiChain.dogecoin.explorer.baseUrl[.mainnet]?.url == "https://blockchair.com/dogecoin/")
    }
}
