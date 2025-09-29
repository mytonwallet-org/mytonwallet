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
        try await bridge.callApiOptional("startSseConnection", params, decodingOptional: ReturnStrategy.self)
    }
    
    public static func signTonProof(accountId: String, proof: ApiTonConnectProof, password: String?) async throws -> ApiSignTonProofResult {
        try await bridge.callApi("signTonProof", accountId, proof, password, decoding: ApiSignTonProofResult.self)
    }
    
    public static func signTransfers(accountId: String, messages: [ApiTransferToSign], options: ApiSignTransfersOptions?) async throws -> [ApiSignedTransfer] {
        try await bridge.callApi("signTransfers", accountId, messages, options, decoding: [ApiSignedTransfer].self)
    }
    
    /**
     * See https://docs.tonconsole.com/academy/sign-data for more details
     */
    public static func signData(accountId: String, dappUrl: String, payloadToSign: SignDataPayload, password: String?) async throws -> Any? {
        try await bridge.callApiRaw("signData", accountId, dappUrl, payloadToSign, password)
    }
}

// MARK: - Support types

public struct ApiSignTonProofResult: Decodable {
    public var signature: String
}

public struct ApiSignTransfersOptions: Encodable {
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

public struct DeviceInfo: Encodable {
    public let platform: String
    public let appName: String
    public let appVersion: String
    public let maxProtocolVersion: Int
    public let features: [AnyEncodable]
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

func makeDeviceInfo() -> DeviceInfo {
    let sendTransactionFeature: [String: AnyEncodable] = [
        "name": AnyEncodable("SendTransaction"),
        "maxMessages": AnyEncodable(4)
    ]
    return DeviceInfo(
        platform: devicePlatform,
        appName: appName,
        appVersion: appVersion,
        maxProtocolVersion: supportedTonConnectVersion,
        features: [
            AnyEncodable("SendTransaction"),
            AnyEncodable(sendTransactionFeature)
        ]
    )
}
