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
    
    public static func getMoonpayOnrampUrl(chain: ApiChain, address: String, activeTheme: ResolvedTheme, selectedCurrency: MBaseCurrency) async throws -> MoonpayOnrampResult {
        try await bridge.callApi("getMoonpayOnrampUrl", chain, address, activeTheme, selectedCurrency, decoding: MoonpayOnrampResult.self)
    }

    public static func waitForLedgerApp(chain: ApiChain, options: WaitForLedgerAppOptions?) async throws -> Bool {
            try await bridge.callApi("waitForLedgerApp", chain, options, decoding: Bool.self)
    }
}

// MARK: - Types

public struct MoonpayOnrampResult: Decodable {
    public var url: String
}

public struct WaitForLedgerAppOptions: Encodable {
    public var timeout: Int?
    public var attemptPause: Int?
}
