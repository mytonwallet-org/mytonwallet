import Foundation
import WalletContext
import WalletCoreTypes

public struct WcPayMerchant: Equatable, Hashable, Codable, Sendable {
    public var name: String
    public var iconUrl: String?

    public init(name: String, iconUrl: String?) {
        self.name = name
        self.iconUrl = iconUrl
    }
}

public struct WcPayAmountDisplay: Equatable, Hashable, Codable, Sendable {
    public var assetSymbol: String
    public var assetName: String
    public var decimals: Int
    public var iconUrl: String?
    public var networkName: String?
}

public struct WcPayFiatAmount: Equatable, Hashable, Codable, Sendable {
    public var value: BigInt
    public var decimals: Int
    public var slug: String

    public var currency: MBaseCurrency? {
        MBaseCurrency(rawValue: slug)
    }
}

public struct WcPayPaymentInfo: Equatable, Hashable, Codable, Sendable {
    public struct Amount: Equatable, Hashable, Codable, Sendable {
        public var value: BigInt
        public var display: WcPayAmountDisplay
        public var fiatAmount: WcPayFiatAmount?
    }

    public var expiresAt: Int
    public var amount: Amount?
}

public struct WcPayPaymentOption: Equatable, Hashable, Codable, Sendable {
    public struct Display: Equatable, Hashable, Codable, Sendable {
        public var assetSymbol: String
        public var assetName: String
        public var decimals: Int
        public var iconUrl: String?
        public var networkName: String?
        public var networkIconUrl: String?
    }

    public var id: String
    public var account: String
    public var amountValue: BigInt
    public var slug: String?
    public var display: Display
    public var fiatAmount: WcPayFiatAmount?
    public var etaS: Int?
    public var expiresAt: Int?
}

public struct WcPayPaymentAmount: Equatable, Hashable, Codable, Sendable {
    public var value: BigInt
    public var display: WcPayAmountDisplay
    public var fiatAmount: WcPayFiatAmount?
}
