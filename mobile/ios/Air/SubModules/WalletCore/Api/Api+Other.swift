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
    
    public static func getMoonpayOfframpUrl(params: MoonpayOfframpParams) async throws -> MoonpayOfframpResult {
        try await bridge.callApi("getMoonpayOfframpUrl", params, decoding: MoonpayOfframpResult.self)
    }

    public static func waitForLedgerApp(chain: ApiChain, options: WaitForLedgerAppOptions?) async throws -> Bool {
            try await bridge.callApi("waitForLedgerApp", chain, options, decoding: Bool.self)
    }
}

// MARK: - Types

public struct MoonpayOnrampResult: Decodable {
    public var url: String
}

public struct MoonpayOfframpResult: Decodable {
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

public struct MoonpayOfframpParams: Encodable {
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

public struct WaitForLedgerAppOptions: Encodable {
    public var timeout: Int?
    public var attemptPause: Int?
}
