//
//  Api+Other.swift
//  WalletCore
//
//  Created by Sina on 11/6/24.
//

import Foundation
import WalletContext

extension Api {

    public static func setIsAppFocused(_ isFocused: Bool) {
        shared?.webViewBridge.callApi(methodName: "setIsAppFocused", args: [AnyEncodable(isFocused)]) { res in
        }
        if isFocused{
            WalletCoreData.notify(event: .applicationWillEnterForeground)
        } else {
            WalletCoreData.notify(event: .applicationDidEnterBackground)
        }
    }
    
    public static func ping() async throws -> Bool {
        try await bridge.callApi("ping", decoding: Bool.self)
    }

    public struct MoonpayOnrampResult: Decodable {
        public var url: String
    }
    
    public static func getMoonpayOnrampUrl(chain: ApiChain, address: String, activeTheme: NightMode) async throws -> MoonpayOnrampResult {
        try await bridge.callApi("getMoonpayOnrampUrl", chain, address, activeTheme, decoding: MoonpayOnrampResult.self)
    }
}
