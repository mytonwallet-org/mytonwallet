//
//  ApiDappRequest.swift
//  MyTonWalletAir
//
//  Created by nikstar on 27.08.2025.
//

public struct ApiDappRequest: Hashable, Sendable {
    var url: String?
    var urlTrustStatus: ApiDappUrlTrustStatus?
    var accountId: String?
    var identifier: String?
    var sseOptions: ApiSseOptions?
    
    public init(
        url: String?,
        urlTrustStatus: ApiDappUrlTrustStatus?,
        accountId: String?,
        identifier: String?,
        sseOptions: ApiSseOptions?
    ) {
        self.url = url
        self.urlTrustStatus = urlTrustStatus
        self.accountId = accountId
        self.identifier = identifier
        self.sseOptions = sseOptions
    }
}

extension ApiDappRequest: Codable {
    enum CodingKeys: String, CodingKey {
        case url
        case urlTrustStatus
        case isUrlEnsured
        case accountId
        case identifier
        case sseOptions
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        accountId = try c.decodeIfPresent(String.self, forKey: .accountId)
        identifier = try c.decodeIfPresent(String.self, forKey: .identifier)
        sseOptions = try c.decodeIfPresent(ApiSseOptions.self, forKey: .sseOptions)
        if let trust = try c.decodeIfPresent(String.self, forKey: .urlTrustStatus) {
            urlTrustStatus = ApiDappUrlTrustStatus(rawValue: trust) ?? .unknown
        } else if let legacy = try c.decodeIfPresent(Bool.self, forKey: .isUrlEnsured) {
            urlTrustStatus = legacy ? .verified : .unknown
        } else {
            urlTrustStatus = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(urlTrustStatus, forKey: .urlTrustStatus)
        try c.encodeIfPresent(accountId, forKey: .accountId)
        try c.encodeIfPresent(identifier, forKey: .identifier)
        try c.encodeIfPresent(sseOptions, forKey: .sseOptions)
    }
}
