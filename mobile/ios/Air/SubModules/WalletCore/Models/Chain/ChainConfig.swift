
import Foundation
import WalletContext

/**
 Describes the chain features that distinguish it from other chains in the multichain-polymorphic parts of the code.
 Mirrors `ChainConfig` from `src/util/chain.ts`.
 */
public struct ChainConfig: Sendable {
    public enum MultiWalletSupport: Sendable {
        case version
        case path
    }

    public struct ExplorerLink: Sendable {
        public var url: String
        public var param: String?
        
        public init(url: String, param: String? = nil) {
            self.url = url
            self.param = param
        }
    }
    
    public struct BuySwap: Sendable {
        public var tokenInSlug: String
        /// Amount as perceived by the user
        public var amountIn: String
    }
    
    public struct Explorer: Sendable {
        public var id: String? = nil
        public var name: String
        public var baseUrl: [ApiNetwork: ExplorerLink]
        /// Use `{base}` as the base URL placeholder and `{address}` as the wallet address placeholder
        public var address: String
        /// Use `{base}` as the base URL placeholder and `{address}` as the token address placeholder
        public var token: String
        /// Use `{base}` as the base URL placeholder and `{hash}` as the transaction hash placeholder
        public var transaction: String
        /// Use `{base}` as the base URL placeholder and `{address}` as the NFT address placeholder
        public var nft: String? = nil
        /// Use `{base}` as the base URL placeholder and `{address}` as the NFT collection address placeholder
        public var nftCollection: String? = nil
        public var doConvertHashFromBase64: Bool
    }

    public struct Marketplace: Sendable {
        public var id: String
        public var name: String
        public var baseUrl: [ApiNetwork: ExplorerLink]
        public var nft: String
        public var nftCollection: String? = nil
    }
    
    public struct RegexPattern: Sendable {
        public var pattern: String
        public var isCaseInsensitive: Bool = false
        
        public func matches(_ value: String) -> Bool {
            let options: NSRegularExpression.Options = isCaseInsensitive ? [.caseInsensitive] : []
            let re = try! NSRegularExpression(pattern: pattern, options: options)
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return re.firstMatch(in: value, options: [], range: range) != nil
        }
    }
    
    /// The blockchain title to show in the UI
    public var title: String
    /// The standard of the chain, e.g. `ethereum` for EVM chains
    public var chainStandard: ApiChain? = nil
    /// Whether the chain supports domain names that resolve to regular addresses
    public var isDnsSupported: Bool
    /// Whether MyTonWallet supports purchasing crypto in that blockchain with a bank card in Russia
    public var canBuyWithCardInRussia: Bool
    /// Whether on-ramp providers support this chain
    public var isOnRampSupported: Bool = true
    /// Whether off-ramp providers support this chain
    public var isOffRampSupported: Bool = true
    /// Whether the chain supports sending asset transfers with a comment
    public var isTransferPayloadSupported: Bool
    /// Whether the chain supports comment encrypting
    public var isEncryptedCommentSupported: Bool
    /// Whether the chain supports sending the full balance of the native token (the fee is taken from the sent amount)
    public var canTransferFullNativeBalance: Bool
    /// Whether Ledger support is implemented for this chain
    public var isLedgerSupported: Bool
    /// Whether the chain supports multi-wallet navigation in settings
    public var multiWalletSupport: MultiWalletSupport?
    /// The default derivation path for creating wallets in this chain
    public var defaultDerivationPath: String? = nil
    /// Regular expression for wallet and contract addresses in the chain
    public var addressRegex: RegexPattern
    /// The same regular expression but matching any prefix of a valid address
    public var addressPrefixRegex: RegexPattern
    /// The native token of the chain, i.e. the token that pays the fees
    public var nativeToken: ApiToken
    /// Whether our own backend socket supports this chain
    public var doesBackendSocketSupport: Bool
    /// Whether the SDK allows to import tokens by address
    public var canImportTokens: Bool
    /// If `true`, the Send form UI will show a scam warning if the wallet has tokens but not enough gas to sent them
    public var shouldShowScamWarningIfNotEnoughGas: Bool
    /** Whether our own backend supports push notifications for addresses in this chain */
    public var doesSupportPushNotifications: Bool
    /// A random but valid address for checking transfer fees
    public var feeCheckAddress: String
    /// A swap configuration used to buy the native token in this chain
    public var buySwap: BuySwap
    /// The slug of the USDT token in this chain, if it has USDT
    public var usdtSlug: [ApiNetwork: String]
    /// The token slugs of this chain added to new accounts by default.
    public var defaultEnabledSlugs: [ApiNetwork: [String]]
    /// The token slugs of this chain supported by the crosschain (CEX) swap mechanism.
    public var crosschainSwapSlugs: [String]
    /**
     The tokens to fill the token cache until it's loaded from the backend.
     Should include the tokens from the above lists, and the staking tokens.
     */
    public var tokenInfo: [ApiToken]
    /// WalletConnect/EIP-155 chain ids for EVM dapp injection.
    public var walletConnectChainIds: [ApiNetwork: Int] = [:]
    /// Configuration of available explorers for the chain.
    public var explorers: [Explorer]? = nil
    /// Configuration of available NFT marketplaces for the chain.
    public var marketplaces: [Marketplace] = []
    /// Configuration of the explorer of the chain.
    public var explorer: Explorer
    /// Whether the chain supports NFTs
    public var isNftSupported: Bool = false
    /// Whether the chain supports native NFT burn operations
    public var isNftBurnSupported: Bool = false
    /// Max number of NFTs to request per pagination batch
    public var nftBatchLimit: Int? = nil
    /// Pause in ms between NFT pagination batches
    public var nftBatchPauseMs: Int? = nil
    /// Whether the chain supports net worth details
    public var isNetWorthSupported: Bool
    /// Builds a link to transfer assets in this chain. If not set, the chain won't have the Deposit Link modal.
    public var formatTransferUrl: (@Sendable (String, BigInt?, String?, String?) -> String)?
}

// MARK: - Built-in chain configs (mirrors `src/util/chain.ts`)

private let DEFAULT_CHAIN_ORDER: [ApiChain] = [
    .ethereum,
    .solana,
    .ton,
    .tron,
    .bnb,
    .hyperliquid,
    .base,
    .arbitrum,
//    .monad,
//    .polygon,
//    .avalanche,
]
private let GRAM_CHAIN_ORDER: [ApiChain] = [
    .ton,
    .ethereum,
    .solana,
    .tron,
    .bnb,
    .hyperliquid,
    .base,
    .arbitrum,
//    .monad,
//    .polygon,
//    .avalanche,
]
private var CHAIN_ORDER: [ApiChain] {
    IS_GRAM_WALLET ? GRAM_CHAIN_ORDER : DEFAULT_CHAIN_ORDER
}
private let TON_DEFAULT_DERIVATION_PATH = "m/44'/607'/{index}'"
private let TRON_DEFAULT_DERIVATION_PATH = "m/44'/195'/0'/0/{index}"
private let SOLANA_DEFAULT_DERIVATION_PATH = "m/44'/501'/{index}'/0'"
private let EVM_DEFAULT_DERIVATION_PATH = "m/44'/60'/0'/0/{index}"
private let EVM_ADDRESS_REGEX = ChainConfig.RegexPattern(pattern: #"^0x[a-fA-F0-9]{40}$"#)
private let EVM_ADDRESS_PREFIX_REGEX = ChainConfig.RegexPattern(pattern: #"^0x[a-fA-F0-9]{0,40}$"#)
private let EVM_FEE_CHECK_ADDRESS = "0x0000000000000000000000000000000000000000"

public func getSupportedChains() -> [ApiChain] {
    CHAIN_ORDER
}

public func isSupportedChain(_ chain: ApiChain) -> Bool {
    CHAIN_ORDER.contains(chain) && CHAIN_CONFIG[chain] != nil
}

private let TON_USDT_TESTNET_SLUG = "ton-kqd0gkbm8z"
private let TON_USDT_TESTNET_ADDRESS = "kQD0GKBM8ZbryVk2aESmzfU6b9b_8era_IkvBSELujFZPsyy"

private let TRON_USDT_TESTNET_SLUG = "tron-tg3xxyexbk"
private let TRON_USDT_TESTNET_ADDRESS = "TG3XXyExBkPp9nzdajDZsozEu4BkaSJozs"

private let SOLANA_USDT_MAINNET_ADDRESS = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
private let SOLANA_USDC_MAINNET_ADDRESS = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

private let MYCOIN_MAINNET_ADDRESS = "EQCFVNlRb-NHHDQfv3Q9xvDXBLJlay855_xREsq5ZDX6KN-w"
private let MYCOIN_MAINNET_IMAGE = "https://imgproxy.mytonwallet.org/imgproxy/Qy038wCBKISofJ0hYMlj6COWma330cx3Ju1ZSPM2LRU/rs:fill:200:200:1/g:no/aHR0cHM6Ly9teXRvbndhbGxldC5pby9sb2dvLTI1Ni1ibHVlLnBuZw.webp"

private let MYCOIN_TESTNET_SLUG = "ton-kqawlxpebw"
private let MYCOIN_TESTNET_ADDRESS = "kQAWlxpEbwhCDFX9gp824ee2xVBhAh5VRSGWfbNFDddAbQoQ"

private let TON_USDT_MAINNET_IMAGE = "https://imgproxy.mytonwallet.org/imgproxy/T3PB4s7oprNVaJkwqbGg54nexKE0zzKhcrPv8jcWYzU/rs:fill:200:200:1/g:no/aHR0cHM6Ly90ZXRoZXIudG8vaW1hZ2VzL2xvZ29DaXJjbGUucG5n.webp"
private let TRON_USDT_MAINNET_ADDRESS = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"

private extension ApiToken {
    static var tonUsdtMainnet: ApiToken {
        ApiToken(
            slug: TON_USDT_SLUG,
            name: "Tether USD",
            symbol: "USD₮",
            decimals: 6,
            chain: .ton,
            tokenAddress: "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs",
            image: TON_USDT_MAINNET_IMAGE,
            label: "TON",
            isFromBackend: true,
            priceUsd: 1
        )
    }
    
    static var tonUsdtTestnet: ApiToken {
        ApiToken(
            slug: TON_USDT_TESTNET_SLUG,
            name: "Tether USD",
            symbol: "USD₮",
            decimals: 6,
            chain: .ton,
            tokenAddress: TON_USDT_TESTNET_ADDRESS,
            image: nil,
            label: "TON",
            priceUsd: 1
        )
    }
    
    static var tronUsdtMainnet: ApiToken {
        ApiToken(
            slug: TRON_USDT_SLUG,
            name: "Tether USD",
            symbol: "USDT",
            decimals: 6,
            chain: .tron,
            tokenAddress: TRON_USDT_MAINNET_ADDRESS,
            label: "TRC-20"
        )
    }
    
    static var tronUsdtTestnet: ApiToken {
        ApiToken(
            slug: TRON_USDT_TESTNET_SLUG,
            name: "Tether USD",
            symbol: "USDT",
            decimals: 6,
            chain: .tron,
            tokenAddress: TRON_USDT_TESTNET_ADDRESS,
            label: "TRC-20"
        )
    }

    static var solana: ApiToken {
        ApiToken(
            slug: SOLANA_SLUG,
            name: "Solana",
            symbol: "SOL",
            decimals: 9,
            chain: .solana,
            cmcSlug: "solana"
        )
    }

    static var solanaUsdtMainnet: ApiToken {
        ApiToken(
            slug: SOLANA_USDT_MAINNET_SLUG,
            name: "Tether USD",
            symbol: "USDT",
            decimals: 6,
            chain: .solana,
            tokenAddress: SOLANA_USDT_MAINNET_ADDRESS,
            image: TON_USDT_MAINNET_IMAGE,
            label: "SOL",
            isFromBackend: true,
            priceUsd: 1
        )
    }

    static var solanaUsdcMainnet: ApiToken {
        ApiToken(
            slug: SOLANA_USDC_MAINNET_SLUG,
            name: "USD Coin",
            symbol: "USDC",
            decimals: 6,
            chain: .solana,
            tokenAddress: SOLANA_USDC_MAINNET_ADDRESS,
            image: "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/logo.png",
            label: "SOL",
            isFromBackend: true,
            priceUsd: 1
        )
    }
    
    static var mycoinMainnet: ApiToken {
        ApiToken(
            slug: MYCOIN_SLUG,
            name: "MyTonWallet Coin",
            symbol: "MY",
            decimals: 9,
            chain: .ton,
            tokenAddress: MYCOIN_MAINNET_ADDRESS,
            image: MYCOIN_MAINNET_IMAGE
        )
    }
    
    static var mycoinTestnet: ApiToken {
        ApiToken(
            slug: MYCOIN_TESTNET_SLUG,
            name: "MyTonWallet Coin",
            symbol: "MY",
            decimals: 9,
            chain: .ton,
            tokenAddress: MYCOIN_TESTNET_ADDRESS,
            image: nil
        )
    }
}

private func makeOpenSeaMarketplace() -> ChainConfig.Marketplace {
    .init(
        id: "openSea",
        name: "OpenSea",
        baseUrl: [
            .mainnet: .init(url: "https://opensea.io/"),
            .testnet: .init(url: ""),
        ],
        nft: "{base}item/{chain}/{address}"
    )
}

private func makeEvmChainConfig(
    title: String,
    nativeToken: ApiToken,
    buySwapAmountIn: String,
    isOnRampSupported: Bool = true,
    isOffRampSupported: Bool = true,
    usdtSlug: String? = nil,
    defaultEnabledSlugs: [String],
    crosschainSwapSlugs: [String],
    tokenInfo: [ApiToken],
    explorerId: String,
    explorerName: String,
    explorerMainnetUrl: String,
    explorerTestnetUrl: String,
    isNftSupported: Bool,
    walletConnectChainIds: [ApiNetwork: Int]
) -> ChainConfig {
    let usdtSlug = usdtSlug ?? ""
    return ChainConfig(
        title: title,
        chainStandard: .ethereum,
        isDnsSupported: false,
        canBuyWithCardInRussia: false,
        isOnRampSupported: isOnRampSupported,
        isOffRampSupported: isOffRampSupported,
        isTransferPayloadSupported: false,
        isEncryptedCommentSupported: false,
        canTransferFullNativeBalance: false,
        isLedgerSupported: false,
        multiWalletSupport: .path,
        defaultDerivationPath: EVM_DEFAULT_DERIVATION_PATH,
        addressRegex: EVM_ADDRESS_REGEX,
        addressPrefixRegex: EVM_ADDRESS_PREFIX_REGEX,
        nativeToken: nativeToken,
        doesBackendSocketSupport: false,
        canImportTokens: false,
        shouldShowScamWarningIfNotEnoughGas: false,
        doesSupportPushNotifications: false,
        feeCheckAddress: EVM_FEE_CHECK_ADDRESS,
        buySwap: .init(tokenInSlug: nativeToken.slug, amountIn: buySwapAmountIn),
        usdtSlug: [
            .mainnet: usdtSlug,
            .testnet: usdtSlug,
        ],
        defaultEnabledSlugs: [
            .mainnet: defaultEnabledSlugs,
            .testnet: defaultEnabledSlugs,
        ],
        crosschainSwapSlugs: crosschainSwapSlugs,
        tokenInfo: tokenInfo,
        walletConnectChainIds: walletConnectChainIds,
        marketplaces: [makeOpenSeaMarketplace()],
        explorer: .init(
            id: explorerId,
            name: explorerName,
            baseUrl: [
                .mainnet: .init(url: explorerMainnetUrl),
                .testnet: .init(url: explorerTestnetUrl),
            ],
            address: "{base}address/{address}",
            token: "{base}token/{address}",
            transaction: "{base}tx/{hash}",
            nft: "{base}nft/{address}",
            nftCollection: "{base}nft/{address}",
            doConvertHashFromBase64: false
        ),
        isNftSupported: isNftSupported,
        isNetWorthSupported: false
    )
}

private let CHAIN_CONFIG: [ApiChain: ChainConfig] = [
    .ton: ChainConfig(
        title: "TON",
        isDnsSupported: true,
        canBuyWithCardInRussia: true,
        isTransferPayloadSupported: true,
        isEncryptedCommentSupported: true,
        canTransferFullNativeBalance: true,
        isLedgerSupported: true,
        multiWalletSupport: .version,
        defaultDerivationPath: TON_DEFAULT_DERIVATION_PATH,
        addressRegex: .init(pattern: #"^([-\w_]{48}|0:[\da-h]{64})$"#, isCaseInsensitive: true),
        addressPrefixRegex: .init(pattern: #"^([-\w_]{1,48}|0:[\da-h]{0,64})$"#, isCaseInsensitive: true),
        nativeToken: .TONCOIN,
        doesBackendSocketSupport: true,
        canImportTokens: true,
        shouldShowScamWarningIfNotEnoughGas: false,
        doesSupportPushNotifications: true,
        feeCheckAddress: "UQBE5NzPPnfb6KAy7Rba2yQiuUnihrfcFw96T-p5JtZjAl_c",
        buySwap: .init(tokenInSlug: TRON_USDT_SLUG, amountIn: "100"),
        usdtSlug: [
            .mainnet: TON_USDT_SLUG,
            .testnet: TON_USDT_TESTNET_SLUG,
        ],
        defaultEnabledSlugs: [
            .mainnet: [TONCOIN_SLUG],
            .testnet: [TONCOIN_SLUG],
        ],
        crosschainSwapSlugs: [TONCOIN_SLUG, TON_USDT_SLUG],
        tokenInfo: [
            .TONCOIN,
            .tonUsdtMainnet,
            .tonUsdtTestnet,
            .mycoinMainnet,
            .mycoinTestnet,
            .TON_USDE,
            .TON_TSUSDE,
        ],
        explorers: [
            .init(
                id: "tonscan",
                name: "Tonscan",
                baseUrl: [
                    .mainnet: .init(url: "https://tonscan.org/"),
                    .testnet: .init(url: "https://testnet.tonscan.org/"),
                ],
                address: "{base}address/{address}",
                token: "{base}jetton/{address}",
                transaction: "{base}tx/{hash}",
                nft: "{base}nft/{address}",
                nftCollection: "{base}collection/{address}",
                doConvertHashFromBase64: true
            ),
            .init(
                id: "tonviewer",
                name: "Tonviewer",
                baseUrl: [
                    .mainnet: .init(url: "https://tonviewer.com/"),
                    .testnet: .init(url: "https://testnet.tonviewer.com/"),
                ],
                address: "{base}{address}?address",
                token: "{base}{address}?jetton",
                transaction: "{base}transaction/{hash}",
                nft: "{base}{address}?nft",
                nftCollection: "{base}{address}?collection",
                doConvertHashFromBase64: true
            ),
        ],
        explorer: .init(
            id: "tonscan",
            name: "Tonscan",
            baseUrl: [
                .mainnet: .init(url: "https://tonscan.org/"),
                .testnet: .init(url: "https://testnet.tonscan.org/"),
            ],
            address: "{base}address/{address}",
            token: "{base}jetton/{address}",
            transaction: "{base}tx/{hash}",
            nft: "{base}nft/{address}",
            nftCollection: "{base}collection/{address}",
            doConvertHashFromBase64: true
        ),
        isNftSupported: true,
        isNftBurnSupported: true,
        nftBatchLimit: 500,
        nftBatchPauseMs: 1000,
        isNetWorthSupported: true,
        formatTransferUrl: { address, amount, text, jettonAddress in
            var components = URLComponents()
            components.scheme = "ton"
            components.host = "transfer"
            components.path = "/\(address)"

            var queryItems: [URLQueryItem] = []
            if let amount = amount?.nilIfZero {
                queryItems.append(URLQueryItem(name: "amount", value: "\(amount)"))
            }
            if let comment = text?.nilIfEmpty {
                queryItems.append(URLQueryItem(name: "text", value: comment))
            }
            if let jetton = jettonAddress?.nilIfEmpty {
                queryItems.append(URLQueryItem(name: "jetton", value: jetton))
            }
            if !queryItems.isEmpty {
                components.queryItems = queryItems
            }

            return components.url?.absoluteString ?? "ton://transfer/\(address)"
        }
    ),
    .tron: ChainConfig(
        title: "TRON",
        isDnsSupported: false,
        canBuyWithCardInRussia: false,
        isTransferPayloadSupported: false,
        isEncryptedCommentSupported: false,
        canTransferFullNativeBalance: false,
        isLedgerSupported: false,
        multiWalletSupport: .path,
        defaultDerivationPath: TRON_DEFAULT_DERIVATION_PATH,
        addressRegex: .init(pattern: #"^T[1-9A-HJ-NP-Za-km-z]{33}$"#),
        addressPrefixRegex: .init(pattern: #"^T[1-9A-HJ-NP-Za-km-z]{0,33}$"#),
        nativeToken: .TRX,
        doesBackendSocketSupport: true,
        canImportTokens: false,
        shouldShowScamWarningIfNotEnoughGas: true,
        doesSupportPushNotifications: false,
        feeCheckAddress: "TW2LXSebZ7Br1zHaiA2W1zRojDkDwjGmpw",
        buySwap: .init(tokenInSlug: TONCOIN_SLUG, amountIn: "10"),
        usdtSlug: [
            .mainnet: TRON_USDT_SLUG,
            .testnet: TRON_USDT_TESTNET_SLUG,
        ],
        defaultEnabledSlugs: [
            .mainnet: [TRX_SLUG],
            .testnet: [TRX_SLUG],
        ],
        crosschainSwapSlugs: [TRX_SLUG, TRON_USDT_SLUG],
        tokenInfo: [
            .TRX,
            .tronUsdtMainnet,
            .tronUsdtTestnet,
        ],
        explorer: .init(
            id: "tronscan",
            name: "Tronscan",
            baseUrl: [
                .mainnet: .init(url: "https://tronscan.org/#/"),
                .testnet: .init(url: "https://shasta.tronscan.org/#/"),
            ],
            address: "{base}address/{address}",
            token: "{base}token20/{address}",
            transaction: "{base}transaction/{hash}",
            doConvertHashFromBase64: false
        ),
        isNetWorthSupported: false
    ),
    .solana: ChainConfig(
        title: "Solana",
        isDnsSupported: false,
        canBuyWithCardInRussia: false,
        isTransferPayloadSupported: true,
        isEncryptedCommentSupported: false,
        canTransferFullNativeBalance: false,
        isLedgerSupported: false,
        multiWalletSupport: .path,
        defaultDerivationPath: SOLANA_DEFAULT_DERIVATION_PATH,
        addressRegex: .init(pattern: #"^[1-9A-HJ-NP-Za-km-z]{32,44}$"#),
        addressPrefixRegex: .init(pattern: #"^[1-9A-HJ-NP-Za-km-z]{0,44}$"#),
        nativeToken: .solana,
        doesBackendSocketSupport: false,
        canImportTokens: false,
        shouldShowScamWarningIfNotEnoughGas: false,
        doesSupportPushNotifications: false,
        feeCheckAddress: "35YT7tt9edJbroEKaC3T3XY4cLNWKtVzmyTEfW8LHPEA",
        buySwap: .init(tokenInSlug: SOLANA_USDT_MAINNET_SLUG, amountIn: "100"),
        usdtSlug: [
            .mainnet: SOLANA_USDT_MAINNET_SLUG,
        ],
        defaultEnabledSlugs: [
            .mainnet: [SOLANA_SLUG],
            .testnet: [SOLANA_SLUG],
        ],
        crosschainSwapSlugs: [SOLANA_SLUG, SOLANA_USDT_MAINNET_SLUG],
        tokenInfo: [
            .solana,
            .solanaUsdtMainnet,
            .solanaUsdcMainnet,
        ],
        explorer: .init(
            id: "solscan",
            name: "Solscan",
            baseUrl: [
                .mainnet: .init(url: "https://solscan.io/"),
                .testnet: .init(url: "https://solscan.io/", param: "?cluster=devnet"),
            ],
            address: "{base}account/{address}",
            token: "{base}token/{address}",
            transaction: "{base}tx/{hash}",
            nft: "{base}token/{address}",
            nftCollection: "{base}token/{address}",
            doConvertHashFromBase64: false
        ),
        isNftSupported: true,
        isNftBurnSupported: true,
        nftBatchLimit: 500,
        nftBatchPauseMs: 1000,
        isNetWorthSupported: false
    ),
    .ethereum: ChainConfig(
        title: "Ethereum",
        chainStandard: .ethereum,
        isDnsSupported: false,
        canBuyWithCardInRussia: false,
        isTransferPayloadSupported: false,
        isEncryptedCommentSupported: false,
        canTransferFullNativeBalance: false,
        isLedgerSupported: false,
        multiWalletSupport: .path,
        defaultDerivationPath: EVM_DEFAULT_DERIVATION_PATH,
        addressRegex: .init(pattern: #"^0x[a-fA-F0-9]{40}$"#),
        addressPrefixRegex: .init(pattern: #"^0x[a-fA-F0-9]{0,40}$"#),
        nativeToken: .ETH,
        doesBackendSocketSupport: false,
        canImportTokens: false,
        shouldShowScamWarningIfNotEnoughGas: false,
        doesSupportPushNotifications: false,
        feeCheckAddress: "0x0000000000000000000000000000000000000000",
        buySwap: .init(tokenInSlug: ETH_SLUG, amountIn: "0.001"),
        usdtSlug: [
            .mainnet: ETH_USDT_MAINNET_SLUG,
            .testnet: ETH_USDT_MAINNET_SLUG,
        ],
        defaultEnabledSlugs: [
            .mainnet: [ETH_SLUG],
            .testnet: [ETH_SLUG],
        ],
        crosschainSwapSlugs: [ETH_SLUG, ETH_USDT_MAINNET_SLUG],
        tokenInfo: [
            .ETH,
            .ETH_USDT_MAINNET,
            .ETH_USDC_MAINNET,
        ],
        walletConnectChainIds: [
            .mainnet: 1,
            .testnet: 5,
        ],
        marketplaces: [
            .init(
                id: "openSea",
                name: "OpenSea",
                baseUrl: [
                    .mainnet: .init(url: "https://opensea.io/"),
                ],
                nft: "{base}item/{chain}/{address}"
            ),
        ],
        explorer: .init(
            id: "etherscan",
            name: "Etherscan",
            baseUrl: [
                .mainnet: .init(url: "https://etherscan.io/"),
                .testnet: .init(url: "https://sepolia.etherscan.io/"),
            ],
            address: "{base}address/{address}",
            token: "{base}token/{address}",
            transaction: "{base}tx/{hash}",
            nft: "{base}nft/{address}",
            nftCollection: "{base}nft/{address}",
            doConvertHashFromBase64: false
        ),
        isNftSupported: true,
        isNetWorthSupported: false
    ),
    .base: ChainConfig(
        title: "Base",
        chainStandard: .ethereum,
        isDnsSupported: false,
        canBuyWithCardInRussia: false,
        isTransferPayloadSupported: false,
        isEncryptedCommentSupported: false,
        canTransferFullNativeBalance: false,
        isLedgerSupported: false,
        multiWalletSupport: .path,
        defaultDerivationPath: EVM_DEFAULT_DERIVATION_PATH,
        addressRegex: .init(pattern: #"^0x[a-fA-F0-9]{40}$"#),
        addressPrefixRegex: .init(pattern: #"^0x[a-fA-F0-9]{0,40}$"#),
        nativeToken: .BASE,
        doesBackendSocketSupport: false,
        canImportTokens: false,
        shouldShowScamWarningIfNotEnoughGas: false,
        doesSupportPushNotifications: false,
        feeCheckAddress: "0x0000000000000000000000000000000000000000",
        buySwap: .init(tokenInSlug: BASE_SLUG, amountIn: "0.001"),
        usdtSlug: [
            .mainnet: BASE_USDT_MAINNET_SLUG,
            .testnet: BASE_USDT_MAINNET_SLUG,
        ],
        defaultEnabledSlugs: [
            .mainnet: [],
            .testnet: [],
        ],
        crosschainSwapSlugs: [BASE_SLUG],
        tokenInfo: [
            .BASE,
            .BASE_USDT_MAINNET,
            .BASE_USDC_MAINNET,
        ],
        walletConnectChainIds: [
            .mainnet: 8453,
            .testnet: 84532,
        ],
        marketplaces: [
            .init(
                id: "openSea",
                name: "OpenSea",
                baseUrl: [
                    .mainnet: .init(url: "https://opensea.io/"),
                ],
                nft: "{base}item/{chain}/{address}"
            ),
        ],
        explorer: .init(
            id: "basescan",
            name: "BaseScan",
            baseUrl: [
                .mainnet: .init(url: "https://basescan.org/"),
                .testnet: .init(url: "https://sepolia.basescan.org/"),
            ],
            address: "{base}address/{address}",
            token: "{base}token/{address}",
            transaction: "{base}tx/{hash}",
            nft: "{base}nft/{address}",
            nftCollection: "{base}nft/{address}",
            doConvertHashFromBase64: false
        ),
        isNftSupported: true,
        isNetWorthSupported: false
    ),
    .bnb: makeEvmChainConfig(
        title: "BNB",
        nativeToken: .BNB,
        buySwapAmountIn: "1",
        isOnRampSupported: false,
        isOffRampSupported: false,
        usdtSlug: BSC_USDT_MAINNET_SLUG,
        defaultEnabledSlugs: [BNB_SLUG],
        crosschainSwapSlugs: [BNB_SLUG],
        tokenInfo: [
            .BNB,
            .BSC_USDT_MAINNET,
        ],
        explorerId: "bsctrace",
        explorerName: "BSCTrace",
        explorerMainnetUrl: "https://bscscan.com/",
        explorerTestnetUrl: "https://testnet.bscscan.com/",
        isNftSupported: true,
        walletConnectChainIds: [
            .mainnet: 56,
            .testnet: 97,
        ]
    ),
//    .polygon: makeEvmChainConfig(
//        title: "Polygon",
//        nativeToken: .POLYGON,
//        buySwapAmountIn: "100",
//        defaultEnabledSlugs: [],
//        crosschainSwapSlugs: [POLYGON_SLUG],
//        tokenInfo: [
//            .POLYGON,
//        ],
//        explorerId: "polygonscan",
//        explorerName: "Polygonscan",
//        explorerMainnetUrl: "https://polygonscan.com/",
//        explorerTestnetUrl: "https://testnet.polygonscan.com/",
//        isNftSupported: true,
//        walletConnectChainIds: [
//            .mainnet: 137,
//            .testnet: 80002,
//        ]
//    ),
    .arbitrum: makeEvmChainConfig(
        title: "Arbitrum",
        nativeToken: .ARBITRUM,
        buySwapAmountIn: "0.001",
        defaultEnabledSlugs: [],
        crosschainSwapSlugs: [ARBITRUM_SLUG],
        tokenInfo: [
            .ARBITRUM,
        ],
        explorerId: "arbiscan",
        explorerName: "Arbiscan",
        explorerMainnetUrl: "https://arbiscan.io/",
        explorerTestnetUrl: "https://sepolia.arbiscan.io/",
        isNftSupported: true,
        walletConnectChainIds: [
            .mainnet: 42161,
            .testnet: 421614,
        ]
    ),
//    .monad: makeEvmChainConfig(
//        title: "Monad",
//        nativeToken: .MONAD,
//        buySwapAmountIn: "10",
//        isOnRampSupported: false,
//        isOffRampSupported: false,
//        defaultEnabledSlugs: [],
//        crosschainSwapSlugs: [MONAD_SLUG],
//        tokenInfo: [
//            .MONAD,
//        ],
//        explorerId: "monadscan",
//        explorerName: "Monadscan",
//        explorerMainnetUrl: "https://monadscan.com/",
//        explorerTestnetUrl: "https://testnet.monadscan.com/",
//        isNftSupported: true,
//        walletConnectChainIds: [
//            .mainnet: 143,
//            .testnet: 10143,
//        ]
//    ),
//    .avalanche: makeEvmChainConfig(
//        title: "Avalanche",
//        nativeToken: .AVALANCHE,
//        buySwapAmountIn: "0.1",
//        usdtSlug: AVALANCHE_USDT_MAINNET_SLUG,
//        defaultEnabledSlugs: [],
//        crosschainSwapSlugs: [AVALANCHE_SLUG],
//        tokenInfo: [
//            .AVALANCHE,
//            .AVALANCHE_USDT_MAINNET,
//        ],
//        explorerId: "snowtrace",
//        explorerName: "Snowtrace",
//        explorerMainnetUrl: "https://snowtrace.io/",
//        explorerTestnetUrl: "https://testnet.snowtrace.io/",
//        isNftSupported: true,
//        walletConnectChainIds: [
//            .mainnet: 43114,
//            .testnet: 43113,
//        ]
//    ),
    .hyperliquid: makeEvmChainConfig(
        title: "Hyperliquid",
        nativeToken: .HYPERLIQUID,
        buySwapAmountIn: "0.1",
        isOnRampSupported: false,
        isOffRampSupported: false,
        usdtSlug: HYPERLIQUID_USDC_MAINNET_SLUG,
        defaultEnabledSlugs: [HYPERLIQUID_SLUG],
        crosschainSwapSlugs: [HYPERLIQUID_SLUG, HYPERLIQUID_USDC_MAINNET_SLUG],
        tokenInfo: [
            .HYPERLIQUID,
            .HYPERLIQUID_USDC_MAINNET,
        ],
        explorerId: "hyperevmscan",
        explorerName: "Hyperevmscan",
        explorerMainnetUrl: "https://hyperevmscan.io/",
        explorerTestnetUrl: "https://hyperevmscan.io/",
        isNftSupported: false,
        walletConnectChainIds: [
            .mainnet: 999,
            .testnet: 998,
        ]
    ),
]

private func makeOtherChainConfig(for chain: ApiChain) -> ChainConfig {
    let title = getChainName(chain)
    let nativeToken = ApiToken(
        slug: "\(chain.rawValue)-native",
        name: title,
        symbol: title,
        decimals: 9,
        chain: chain
    )
    return ChainConfig(
        title: title,
        isDnsSupported: false,
        canBuyWithCardInRussia: false,
        isTransferPayloadSupported: false,
        isEncryptedCommentSupported: false,
        canTransferFullNativeBalance: false,
        isLedgerSupported: false,
        multiWalletSupport: nil,
        addressRegex: .init(pattern: #"^$"#),
        addressPrefixRegex: .init(pattern: #"^$"#),
        nativeToken: nativeToken,
        doesBackendSocketSupport: false,
        canImportTokens: false,
        shouldShowScamWarningIfNotEnoughGas: false,
        doesSupportPushNotifications: false,
        feeCheckAddress: "",
        buySwap: .init(tokenInSlug: TONCOIN_SLUG, amountIn: "0"),
        usdtSlug: [:],
        defaultEnabledSlugs: [
            .mainnet: [],
            .testnet: [],
        ],
        crosschainSwapSlugs: [],
        tokenInfo: [],
        explorer: .init(
            name: "Explorer",
            baseUrl: [
                .mainnet: .init(url: "https://tonscan.org/"),
                .testnet: .init(url: "https://testnet.tonscan.org/"),
            ],
            address: "{base}address/{address}",
            token: "{base}token/{address}",
            transaction: "{base}tx/{hash}",
            doConvertHashFromBase64: false
        ),
        isNetWorthSupported: false
    )
}

public func getChainConfig(chain: ApiChain) -> ChainConfig {
    CHAIN_CONFIG[chain] ?? makeOtherChainConfig(for: chain)
}

public func getAvailableExplorers(chain: ApiChain) -> [ChainConfig.Explorer] {
    let config = getChainConfig(chain: chain)
    return config.explorers ?? [config.explorer]
}

public func getAvailableMarketplaces(chain: ApiChain) -> [ChainConfig.Marketplace] {
    getChainConfig(chain: chain).marketplaces
}
