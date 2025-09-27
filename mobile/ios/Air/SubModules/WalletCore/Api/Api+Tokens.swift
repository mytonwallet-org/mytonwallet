//
//  Api+Tokens.swift
//  WalletCore
//
//  Created by Sina on 3/28/24.
//

import Foundation
import WalletContext

extension Api {
    public static func fetchToken(network: ApiNetwork, address: String) async throws -> ApiToken {
        try await bridge.callApi("fetchToken", network, address, decoding: ApiToken.self)
    }
}
