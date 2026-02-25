//
//  Api+TC.swift
//  WalletCore
//
//  Created by Sina on 8/29/24.
//

import Foundation
import WalletContext

extension Api {

    public static func startSseConnection(params: ApiSseConnectionParams) async throws -> ReturnStrategy? {
        try await bridge.callApiOptional(
            "tonConnect_handleDeepLink",
            params.url,
            params.isFromInAppBrowser,
            params.identifier,
            decodingOptional: ReturnStrategy.self
        )
    }
    
    public static func signDappProof(dappChains: [ApiDappSessionChain], accountId: String, proof: ApiTonConnectProof, password: String?) async throws -> ApiSignDappProofResult {
        let response = try await bridge.callApi("signDappProof", dappChains, accountId, proof, password, decoding: ApiSignDappProofResponse.self)
        if let signatures = response.signatures {
            return ApiSignDappProofResult(signatures: signatures)
        }
        if let error = response.error?.stringValue {
            throw BridgeCallError.customMessage(error, response)
        }
        if let errorDict = response.error?.dictionaryValue, let message = errorDict["message"]?.stringValue {
            throw BridgeCallError.customMessage(message, errorDict)
        }
        throw BridgeCallError.unknown(baseError: response)
    }
    
    public static func signDappTransfers(dappChain: ApiDappSessionChain, accountId: String, messages: [ApiTransferToSign], options: ApiSignTransfersOptions?) async throws -> [ApiSignedTransfer] {
        try await bridge.callApi("signDappTransfers", dappChain, accountId, messages, options, decoding: [ApiSignedTransfer].self)
    }
    
    /**
     * See https://docs.tonconsole.com/academy/sign-data for more details
     */
    public static func signDappData(dappChain: ApiDappSessionChain, accountId: String, dappUrl: String, payloadToSign: SignDataPayload, password: String?) async throws -> ApiDappSignDataResult {
        try await bridge.callApi("signDappData", dappChain, accountId, dappUrl, payloadToSign, password, decoding: ApiDappSignDataResult.self)
    }
}


public struct ApiSignTransfersOptions: Encodable {
    public var password: String?
    public var vestingAddress: String?
    /** Unix seconds */
    public var validUntil: Int?
    public var isLegacyOutput: Bool?
    
    public init(password: String?, vestingAddress: String?, validUntil: Int?, isLegacyOutput: Bool?) {
        self.password = password
        self.vestingAddress = vestingAddress
        self.validUntil = validUntil
        self.isLegacyOutput = isLegacyOutput
    }
}

public struct ApiSseConnectionParams: Encodable {
    public var url: String
    public var isFromInAppBrowser: Bool?
    public var identifier: String?
    
    public init(url: String, isFromInAppBrowser: Bool?, identifier: String?) {
        self.url = url
        self.isFromInAppBrowser = isFromInAppBrowser
        self.identifier = identifier
    }
}

public enum ReturnStrategy: Equatable, Hashable, Codable {
    case none
    case back
    case empty
    case url(String)
    
    init(string ret: String) {
        switch ret {
        case "back":
            self = .back
        case "none":
            self = .none
        case "empty":
            self = .empty
        default:
            self = .url(ret.removingPercentEncoding ?? ret)
        }
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        self = ReturnStrategy(string: string)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .none:
            try container.encode("none")
        case .back:
            try container.encode("back")
        case .empty:
            try container.encode("empty")
        case .url(let url):
            try container.encode(url)
        }
    }
}
