
import Foundation
import WalletContext

/**
 Describes the chain features that distinguish it from other chains in the multichain-polymorphic parts of the code.
 Mirrors `ChainConfig` from `src/util/chain.ts`.
 */
public struct ChainConfig {

    public struct ExplorerLink {
        public var url: String
        public var param: String?
        
        public init(url: String, param: String? = nil) {
            self.url = url
            self.param = param
        }
    }
    
    public struct BuySwap {
        public var tokenInSlug: String
        /// Amount as perceived by the user
        public var amountIn: String
    }
    
    public struct Explorer {
        public var name: String
        public var baseUrl: [ApiNetwork: ExplorerLink]
        /// Use `{base}` as the base URL placeholder and `{address}` as the wallet address placeholder
        public var address: String
        /// Use `{base}` as the base URL placeholder and `{address}` as the token address placeholder
        public var token: String
        /// Use `{base}` as the base URL placeholder and `{hash}` as the transaction hash placeholder
        public var transaction: String
        public var doConvertHashFromBase64: Bool
    }
    
    public struct RegexPattern {
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
    /// Whether the chain supports domain names that resolve to regular addresses
    public var isDnsSupported: Bool
    /// Whether MyTonWallet supports purchasing crypto in that blockchain with a bank card in Russia
    public var canBuyWithCardInRussia: Bool
    /// Whether the chain supports sending asset transfers with a comment
    public var isTransferPayloadSupported: Bool
    /// Whether the chain supports comment encrypting
    public var isEncryptedCommentSupported: Bool
    /// Whether the chain supports sending the full balance of the native token (the fee is taken from the sent amount)
    public var canTransferFullNativeBalance: Bool
    /// Whether Ledger support is implemented for this chain
    public var isLedgerSupported: Bool
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
    /// Configuration of the explorer of the chain.
    public var explorer: Explorer
    /// Whether the chain supports net worth details
    public var isNetWorthSupported: Bool
    /// Builds a link to transfer assets in this chain. If not set, the chain won't have the Deposit Link modal.
    public var formatTransferUrl: ((String, BigInt?, String?, String?) -> String)?
}

// MARK: - Built-in chain configs (mirrors `src/util/chain.ts`)

private let TON_USDT_TESTNET_SLUG = "ton-kqd0gkbm8z"
private let TON_USDT_TESTNET_ADDRESS = "kQD0GKBM8ZbryVk2aESmzfU6b9b_8era_IkvBSELujFZPsyy"

private let TRON_USDT_TESTNET_SLUG = "tron-tg3xxyexbk"
private let TRON_USDT_TESTNET_ADDRESS = "TG3XXyExBkPp9nzdajDZsozEu4BkaSJozs"

private let SOLANA_USDT_MAINNET_ADDRESS = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"

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
            image: nil
        )
    }
    
    static var tronUsdtMainnet: ApiToken {
        ApiToken(
            slug: TRON_USDT_SLUG,
            name: "Tether USD",
            symbol: "USDT",
            decimals: 6,
            chain: .tron,
            tokenAddress: TRON_USDT_MAINNET_ADDRESS
        )
    }
    
    static var tronUsdtTestnet: ApiToken {
        ApiToken(
            slug: TRON_USDT_TESTNET_SLUG,
            name: "Tether USD",
            symbol: "USDT",
            decimals: 6,
            chain: .tron,
            tokenAddress: TRON_USDT_TESTNET_ADDRESS
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
            image: TON_USDT_MAINNET_IMAGE
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

private let CHAIN_CONFIG: [ApiChain: ChainConfig] = [
    .ton: ChainConfig(
        title: "TON",
        isDnsSupported: true,
        canBuyWithCardInRussia: true,
        isTransferPayloadSupported: true,
        isEncryptedCommentSupported: true,
        canTransferFullNativeBalance: true,
        isLedgerSupported: true,
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
            .mainnet: [TONCOIN_SLUG, TON_USDT_SLUG],
            .testnet: [TONCOIN_SLUG, TON_USDT_TESTNET_SLUG],
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
        explorer: .init(
            name: "Tonscan",
            baseUrl: [
                .mainnet: .init(url: "https://tonscan.org/"),
                .testnet: .init(url: "https://testnet.tonscan.org/"),
            ],
            address: "{base}address/{address}",
            token: "{base}jetton/{address}",
            transaction: "{base}tx/{hash}",
            doConvertHashFromBase64: true
        ),
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
            .mainnet: [TRX_SLUG, TRON_USDT_SLUG],
            .testnet: [TRX_SLUG, TRON_USDT_TESTNET_SLUG],
        ],
        crosschainSwapSlugs: [TRX_SLUG, TRON_USDT_SLUG],
        tokenInfo: [
            .TRX,
            .tronUsdtMainnet,
            .tronUsdtTestnet,
        ],
        explorer: .init(
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
            .mainnet: [SOLANA_SLUG, SOLANA_USDT_MAINNET_SLUG],
            .testnet: [SOLANA_SLUG],
        ],
        crosschainSwapSlugs: [SOLANA_SLUG, SOLANA_USDT_MAINNET_SLUG],
        tokenInfo: [
            .solana,
            .solanaUsdtMainnet,
        ],
        explorer: .init(
            name: "Solscan",
            baseUrl: [
                .mainnet: .init(url: "https://solscan.io/"),
                .testnet: .init(url: "https://solscan.io/", param: "?cluster=devnet"),
            ],
            address: "{base}account/{address}",
            token: "{base}token/{address}",
            transaction: "{base}tx/{hash}",
            doConvertHashFromBase64: false
        ),
        isNetWorthSupported: false
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
