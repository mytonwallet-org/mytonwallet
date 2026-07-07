//
//  Api+TC.swift
//  WalletCore
//
//  Created by Sina on 8/29/24.
//

import Foundation
import WalletContext

// Reports a TON Connect UI event to the analytics worker method; the worker enriches it from the flow context.
public struct TonConnectAnalyticsEvent: Encodable, Sendable {
    public var event_name: String
    public var promiseId: String
}

extension Api {

    // Best-effort fire-and-forget; analytics must never affect the dapp flow.
    public static func recordTonConnectEvent(eventName: String, promiseId: String) {
        Task {
            try? await bridge.callApiVoid("recordTonConnectEvent", TonConnectAnalyticsEvent(event_name: eventName, promiseId: promiseId))
        }
    }

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
            throw SdkError.apiReturnedError(error: error, context: response)
        }
        if let errorDict = response.error?.dictionaryValue, let message = errorDict["message"]?.stringValue {
            throw SdkError.apiReturnedError(error: message, context: errorDict)
        }
        throw SdkError.unexpected(message: "Invalid signDappProof response", context: response)
    }
    
    public static func signDappTransfers(dappChain: ApiDappSessionChain, accountId: String, messages: [ApiTransferToSign], options: ApiSignTransfersOptions?) async throws -> [ApiSignedTransfer] {
        let result = try await signDappTransfersProtected(
            dappChain: dappChain,
            accountId: accountId,
            messages: messages,
            options: options
        )
        if let mfaRequestHash = result.mfaRequestHash {
            throw SdkError.unexpected(message: "Telegram confirmation is required: \(mfaRequestHash)", context: result)
        }
        if let error = result.error {
            throw SdkError.apiReturnedError(error: error, context: result)
        }
        return try result.signedTransfers.orThrow()
    }

    public static func signDappTransfersProtected(dappChain: ApiDappSessionChain, accountId: String, messages: [ApiTransferToSign], options: ApiSignTransfersOptions?) async throws -> ApiSignDappTransfersResult {
        try await bridge.callApi("signDappTransfers", dappChain, accountId, messages, options, decoding: ApiSignDappTransfersResult.self)
    }
    
    /**
     * See https://docs.tonconsole.com/academy/sign-data for more details
     */
    public static func signDappData(dappChain: ApiDappSessionChain, accountId: String, dappUrl: String, payloadToSign: SignDataPayload, password: String?) async throws -> ApiDappSignDataResult {
        try await bridge.callApi("signDappData", dappChain, accountId, dappUrl, payloadToSign, password, decoding: ApiDappSignDataResult.self)
    }
}


public struct ApiSignTransfersOptions: Encodable, Sendable {
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

public struct ApiSignDappTransfersResult: Decodable, Sendable {
    public let signedTransfers: [ApiSignedTransfer]?
    public let mfaRequestHash: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case mfaRequestHash
        case error
    }

    public init(from decoder: Decoder) throws {
        if let signedTransfers = try? [ApiSignedTransfer](from: decoder) {
            self.signedTransfers = signedTransfers
            self.mfaRequestHash = nil
            self.error = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.signedTransfers = nil
        self.mfaRequestHash = try container.decodeIfPresent(String.self, forKey: .mfaRequestHash)
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
        guard self.mfaRequestHash != nil || self.error != nil else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected signed transfers, MFA request hash, or error"
                )
            )
        }
    }
}

extension ApiSignDappTransfersResult: MfaProtectedActionResult {
    public var protectedActionError: String? { error }
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

public enum ReturnStrategy: Equatable, Hashable, Codable, Sendable {
    case none
    case back
    case url(String)
    
    init(string ret: String) {
        switch ret {
        case "back":
            self = .back
        case "none":
            self = .none
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
        case .url(let url):
            try container.encode(url)
        }
    }
}
