//
//  Api+Other.swift
//  WalletCore
//
//  Created by Sina on 11/6/24.
//

import Foundation
import WalletContext

extension Api {

    public static func setIsAppFocused(_ isFocused: Bool) async throws {
        try await bridge.callApiVoid("setIsAppFocused", isFocused)
        if isFocused{
            WalletCoreData.notify(event: .applicationWillEnterForeground)
        } else {
            WalletCoreData.notify(event: .applicationDidEnterBackground)
        }
    }
    
    public static func getLogs() async throws -> Any? {
        try await bridge.callApiRaw("getLogs")
    }
    
    public static func ping() async throws -> Bool {
        try await bridge.callApi("ping", decoding: Bool.self)
    }
    
    public static func getMoonpayOnrampUrl(params: MoonpayOnrampParams) async throws -> MoonpayOnrampResult {
        try await bridge.callApi("getMoonpayOnrampUrl", params, decoding: MoonpayOnrampResult.self)
    }
    
    public static func getMoonpayOfframpUrl(params: Moonpay.Offramp.UrlRequestParams) async throws -> Moonpay.Offramp.UrlRequestResult {
        try await bridge.callApi("getMoonpayOfframpUrl", params, decoding:  Moonpay.Offramp.UrlRequestResult.self)
    }

    public static func waitForLedgerApp(chain: ApiChain, options: WaitForLedgerAppOptions?) async throws -> Bool {
            try await bridge.callApi("waitForLedgerApp", chain, options, decoding: Bool.self)
    }
}

// MARK: - Types

public struct Moonpay {
    
    public struct Offramp {
        
        /// https://support.moonpay.com/en/articles/362475-moonpay-s-supported-currencies
        /// Ordereded by priority
        public static let supportedCurrencies: [MBaseCurrency] = [.USD, .EUR]

        public static let limitsBySlug: [String: Double] = [
            TONCOIN_SLUG: 2000
        ]
        
        public struct UrlRequestParams: Encodable {
            public let chain: ApiChain
            public let address: String
            public let theme: ResolvedTheme
            public let currency: MBaseCurrency
            public let amount: String
            public let baseUrl: String
            
            public init(chain: ApiChain, address: String, theme: ResolvedTheme, currency: MBaseCurrency, amount: String, baseUrl: String) {
                self.chain = chain
                self.address = address
                self.theme = theme
                self.currency = currency
                self.amount = amount
                self.baseUrl = baseUrl
            }
        }

        public struct UrlRequestResult: Decodable {
            public var url: String
            
            /// Sandboxed version
            public var sandboxUrl: String {
                guard let parsed = URL(string: url), var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false)
                else { fatalError("Failed to parse URL: \(url)") }
                let queryItems = (components.queryItems ?? []).compactMap { item -> URLQueryItem? in
                    if item.name == "signature" { return nil }
                    if item.name == "apiKey" { return URLQueryItem(name: "apiKey", value: "pk_test_123") }
                    return item
                }
                assert(components.host == "sell.moonpay.com", "Unexpected host in URL: \(url)")
                components.host = "sell-sandbox.moonpay.com"
                components.queryItems = queryItems.isEmpty ? nil : queryItems
                return components.url?.absoluteString ?? url
            }
        }
    }
}

public struct MoonpayOnrampResult: Decodable {
    public var url: String
}

public struct MoonpayOnrampParams: Encodable {
    public let chain: ApiChain
    public let address: String
    public let theme: ResolvedTheme
    public let currency: MBaseCurrency
    
    public init(chain: ApiChain, address: String, theme: ResolvedTheme, currency: MBaseCurrency) {
        self.chain = chain
        self.address = address
        self.theme = theme
        self.currency = currency
    }
}

public struct WaitForLedgerAppOptions: Encodable {
    public var timeout: Int?
    public var attemptPause: Int?
}
