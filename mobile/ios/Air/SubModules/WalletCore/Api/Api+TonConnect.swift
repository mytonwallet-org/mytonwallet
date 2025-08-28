//
//  Api+TC.swift
//  WalletCore
//
//  Created by Sina on 8/29/24.
//

import Foundation
import WalletContext

extension Api {
    
    public static func signTonProof(accountId: String, proof: ApiTonConnectProof, password: String) async throws -> SignTonProofResult {
        try await bridge.callApi("signTonProof", accountId, proof, password, decoding: SignTonProofResult.self)
    }
    
    public static func signTransfers(accountId: String, messages: [ApiTransferToSign], options: SignTransfersOptions?) async throws -> [ApiSignedTransfer] {
        try await bridge.callApi("signTransfers", accountId, messages, options, decoding: [ApiSignedTransfer].self)
    }
    
    /**
     * See https://docs.tonconsole.com/academy/sign-data for more details
     */
    public static func signData(accountId: String, dappUrl: String, payloadToSign: SignDataPayload, password: String?) async throws -> Any? {
        try await bridge.callApiRaw("signData", accountId, dappUrl, payloadToSign, password)
    }

    // MARK: Support types
    
    public struct SignTonProofResult: Decodable {
        public var signature: String
    }
    
    public struct SignTransfersOptions: Encodable {
        public var password: String?
        public var vestingAddress: String?
        /** Unix seconds */
        public var validUntil: Int?
        
        public init(password: String?, vestingAddress: String?, validUntil: Int?) {
            self.password = password
            self.vestingAddress = vestingAddress
            self.validUntil = validUntil
        }
    }
    
    public typealias SignDataPayload = AnyEncodable
}

