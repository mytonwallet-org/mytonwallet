import WalletContext
import WalletCoreTypes

extension ApiUpdate {
    public struct WalletConnectPayLoading: Equatable, Hashable, Codable, Sendable {
        public var type = "walletConnectPayLoading"
        public var accountId: String
    }

    public struct WalletConnectPayCloseLoading: Equatable, Hashable, Codable, Sendable {
        public var type = "walletConnectPayCloseLoading"
    }

    public struct WalletConnectPaySignTransaction: Equatable, Hashable, Decodable, Sendable {
        public var type = "walletConnectPaySignTransaction"
        public var promiseId: String
        public var accountId: String
        public var merchant: WcPayMerchant
        public var operationChain: ApiChain
        public var transactions: [ApiDappTransfer]
        public var emulation: Emulation?
        public var paymentInfo: WcPayPaymentInfo?
        public var paymentOption: WcPayPaymentOption?
        public var isSignOnly: Bool
        public var isLegacyOutput: Bool?
        public var shouldHideTransfers: Bool?
        public var validUntil: Int?

        enum CodingKeys: CodingKey {
            case promiseId
            case accountId
            case merchant
            case operationChain
            case transactions
            case emulation
            case paymentInfo
            case paymentOption
            case isSignOnly
            case isLegacyOutput
            case shouldHideTransfers
            case validUntil
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.promiseId = try container.decode(String.self, forKey: .promiseId)
            self.accountId = try container.decode(String.self, forKey: .accountId)
            self.merchant = try container.decode(WcPayMerchant.self, forKey: .merchant)
            self.operationChain = (try? container.decodeIfPresent(ApiChain.self, forKey: .operationChain)) ?? FALLBACK_CHAIN
            self.transactions = try container.decode([ApiDappTransfer].self, forKey: .transactions)
            self.emulation = try container.decodeIfPresent(Emulation.self, forKey: .emulation)
            self.paymentInfo = try? container.decodeIfPresent(WcPayPaymentInfo.self, forKey: .paymentInfo)
            self.paymentOption = try? container.decodeIfPresent(WcPayPaymentOption.self, forKey: .paymentOption)
            self.isSignOnly = try container.decode(Bool.self, forKey: .isSignOnly)
            self.isLegacyOutput = try? container.decodeIfPresent(Bool.self, forKey: .isLegacyOutput)
            self.shouldHideTransfers = try? container.decodeIfPresent(Bool.self, forKey: .shouldHideTransfers)
            self.validUntil = try? container.decodeIfPresent(Int.self, forKey: .validUntil)
        }
    }

    public struct WalletConnectPaySignTransactionComplete: Equatable, Hashable, Codable, Sendable {
        public var type = "walletConnectPaySignTransactionComplete"
        public var accountId: String
    }

    public struct WalletConnectPaySignData: Equatable, Hashable, Decodable, Sendable {
        public var type = "walletConnectPaySignData"
        public let promiseId: String
        public let accountId: String
        public let merchant: WcPayMerchant
        public let operationChain: ApiChain
        public let payloadToSign: SignDataPayload
        public let paymentInfo: WcPayPaymentInfo?
        public let paymentOption: WcPayPaymentOption?

        enum CodingKeys: CodingKey {
            case promiseId
            case accountId
            case merchant
            case operationChain
            case payloadToSign
            case paymentInfo
            case paymentOption
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.promiseId = try container.decode(String.self, forKey: .promiseId)
            self.accountId = try container.decode(String.self, forKey: .accountId)
            self.merchant = try container.decode(WcPayMerchant.self, forKey: .merchant)
            self.operationChain = (try? container.decodeIfPresent(ApiChain.self, forKey: .operationChain)) ?? FALLBACK_CHAIN
            self.payloadToSign = try container.decode(SignDataPayload.self, forKey: .payloadToSign)
            self.paymentInfo = try? container.decodeIfPresent(WcPayPaymentInfo.self, forKey: .paymentInfo)
            self.paymentOption = try? container.decodeIfPresent(WcPayPaymentOption.self, forKey: .paymentOption)
        }
    }

    public struct WalletConnectPaySignDataComplete: Equatable, Hashable, Codable, Sendable {
        public var type = "walletConnectPaySignDataComplete"
        public var accountId: String
    }

    public struct WalletConnectPayDataCollection: Equatable, Hashable, Codable, Sendable {
        public var type = "walletConnectPayDataCollection"
        public var promiseId: String
        public var url: String
    }

    public struct WalletConnectPayDataCollectionComplete: Equatable, Hashable, Codable, Sendable {
        public var type = "walletConnectPayDataCollectionComplete"
    }

    public struct WalletConnectPayOptionSelection: Equatable, Hashable, Codable, Sendable {
        public var type = "walletConnectPayOptionSelection"
        public var promiseId: String
        public var paymentLink: String
        public var accountId: String
        public var merchant: WcPayMerchant
        public var paymentInfo: WcPayPaymentInfo?
        public var options: [WcPayPaymentOption]
        public var isLoading: Bool?
        public var shouldSwitchWallet: Bool?
    }

    public struct WalletConnectPayOptionSelectionComplete: Equatable, Hashable, Codable, Sendable {
        public var type = "walletConnectPayOptionSelectionComplete"
    }

    public struct WalletConnectPayProcessing: Equatable, Hashable, Codable, Sendable {
        public var type = "walletConnectPayProcessing"
        public var accountId: String
        public var merchant: WcPayMerchant
        public var operationChain: ApiChain
    }

    public struct WalletConnectPayPaymentComplete: Equatable, Hashable, Codable, Sendable {
        public var type = "walletConnectPayPaymentComplete"
        public var accountId: String
        public var merchant: WcPayMerchant
        public var operationChain: ApiChain
        public var txId: String?
        public var paymentAmount: WcPayPaymentAmount?
    }
}
