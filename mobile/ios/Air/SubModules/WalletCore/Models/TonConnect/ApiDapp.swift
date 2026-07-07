//
//  MDapp.swift
//  WalletCore
//
//  Created by Sina on 8/14/24.
//

import Foundation

public enum ApiDappUrlTrustStatus: String, Codable, Equatable, Hashable, Sendable {
    case verified
    case unknown
    case invalid
    case dangerous
}

public struct ApiDapp: Equatable, Hashable, Sendable {
    
    public let protocolType: ApiDappProtocolType?
    public let url: String
    public let name: String
    public let iconUrl: String
    public let manifestUrl: String?
    
    public let connectedAt: Int?
    public let urlTrustStatus: ApiDappUrlTrustStatus?
    public let sse: ApiSseOptions?
    public let wcTopic: String?
    public let wcPairingTopic: String?
    public let chains: [ApiDappSessionChain]?
    
    public init(
        protocolType: ApiDappProtocolType? = nil,
        url: String,
        name: String,
        iconUrl: String,
        manifestUrl: String? = nil,
        connectedAt: Int?,
        urlTrustStatus: ApiDappUrlTrustStatus?,
        sse: ApiSseOptions?,
        wcTopic: String? = nil,
        wcPairingTopic: String? = nil,
        chains: [ApiDappSessionChain]? = nil
    ) {
        self.protocolType = protocolType
        self.url = url
        self.name = name
        self.iconUrl = iconUrl
        self.manifestUrl = manifestUrl
        self.connectedAt = connectedAt
        self.urlTrustStatus = urlTrustStatus
        self.sse = sse
        self.wcTopic = wcTopic
        self.wcPairingTopic = wcPairingTopic
        self.chains = chains
    }
}

extension ApiDapp: Codable {
    enum CodingKeys: String, CodingKey {
        case protocolType
        case url
        case name
        case iconUrl
        case manifestUrl
        case connectedAt
        case urlTrustStatus
        case isUrlEnsured
        case sse
        case wcTopic
        case wcPairingTopic
        case chains
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        protocolType = try c.decodeIfPresent(ApiDappProtocolType.self, forKey: .protocolType)
        url = try c.decode(String.self, forKey: .url)
        name = try c.decode(String.self, forKey: .name)
        iconUrl = try c.decode(String.self, forKey: .iconUrl)
        manifestUrl = try c.decodeIfPresent(String.self, forKey: .manifestUrl)
        connectedAt = try c.decodeIfPresent(Int.self, forKey: .connectedAt)
        sse = try c.decodeIfPresent(ApiSseOptions.self, forKey: .sse)
        wcTopic = try c.decodeIfPresent(String.self, forKey: .wcTopic)
        wcPairingTopic = try c.decodeIfPresent(String.self, forKey: .wcPairingTopic)
        chains = try c.decodeIfPresent([ApiDappSessionChain].self, forKey: .chains)
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
        try c.encodeIfPresent(protocolType, forKey: .protocolType)
        try c.encode(url, forKey: .url)
        try c.encode(name, forKey: .name)
        try c.encode(iconUrl, forKey: .iconUrl)
        try c.encodeIfPresent(manifestUrl, forKey: .manifestUrl)
        try c.encodeIfPresent(connectedAt, forKey: .connectedAt)
        try c.encodeIfPresent(urlTrustStatus, forKey: .urlTrustStatus)
        try c.encodeIfPresent(sse, forKey: .sse)
        try c.encodeIfPresent(wcTopic, forKey: .wcTopic)
        try c.encodeIfPresent(wcPairingTopic, forKey: .wcPairingTopic)
        try c.encodeIfPresent(chains, forKey: .chains)
    }
}

public struct ApiSseOptions: Equatable, Hashable, Codable, Sendable {
    public let clientId: String
    public let appClientId: String
    public let secretKey: String
    public let lastOutputId: Int
}

extension ApiDapp {
    public var displayUrl: String {
        url.replacing(/^https:\/\//, with: "")
    }
    
    public var resolvedUrlTrustStatus: ApiDappUrlTrustStatus {
        urlTrustStatus ?? .unknown
    }

    public var shouldShowUrlTrustStatusWarning: Bool {
        resolvedUrlTrustStatus != .verified
    }
    
    public static let loadingStub = ApiDapp(
        url: "https://example.com",
        name: "Some App",
        iconUrl: "",
        connectedAt: nil,
        urlTrustStatus: nil,
        sse: nil
    )
}

// MARK: Sample data

#if DEBUG
    extension ApiDapp {
        public static let sample = ApiDapp(
            url: "https://static.mytonwallet.org",
            name: "Sample name",
            iconUrl: "https://static.mytonwallet.org/explore-icons/mtwcards.webp",
            manifestUrl: "https://static.mytonwallet.org/explore-icons/mtwcards.webp",
            connectedAt: nil,
            urlTrustStatus: nil,
            sse: nil,
        )
    
        public static let sampleList: [ApiDapp] = [
            ApiDapp(url: "https://static.mytonwallet.org",
                    name: "Sample name",
                    iconUrl: "https://static.mytonwallet.org/explore-icons/mtwcards.webp",
                    manifestUrl: "https://fragment.com/tonconnect-manifest.json",
                    connectedAt: nil,
                    urlTrustStatus: nil,
                    sse: nil),
            
            ApiDapp(url: "https://app.storm.tg",
                    name: "Storm Trade",
                    iconUrl: "https://static.mytonwallet.org/explore-icons/storm.jpg",
                    manifestUrl: "https://fragment.com/tonconnect-manifest.json",
                    connectedAt: nil,
                    urlTrustStatus: nil,
                    sse: nil),
            
            ApiDapp(url: "https://app.upscale.trade",
                    name: "Upscale",
                    iconUrl: "https://static.mytonwallet.org/explore-icons/upscale.png",
                    manifestUrl: "https://fragment.com/tonconnect-manifest.json",
                    connectedAt: nil,
                    urlTrustStatus: nil,
                    sse: nil),
            
            ApiDapp(url: "https://app.bidask.finance",
                    name: "Bidask",
                    iconUrl: "https://static.mytonwallet.org/explore-icons/bidask.png",
                    manifestUrl: "https://fragment.com/tonconnect-manifest.json",
                    connectedAt: nil,
                    urlTrustStatus: nil,
                    sse: nil),
            
            ApiDapp(url: "https://app.hipo.finance",
                    name: "Hipo",
                    iconUrl: "https://static.mytonwallet.org/explore-icons/hipo_dark.png",
                    manifestUrl: "https://fragment.com/tonconnect-manifest.json",
                    connectedAt: nil,
                    urlTrustStatus: nil,
                    sse: nil),
        ]
    
//    static let sampleList: [ApiDapp] = [
//        ApiDapp(dictionary: [
//            "url": "https://static.mytonwallet.org/explore-icons/mtwcards.webp#0",
//            "iconUrl": "https://static.mytonwallet.org/explore-icons/mtwcards.webp#0",
//            "name": "Sample 1",
//        ]),
//        ApiDapp(dictionary: [
//            "url": "https://static.mytonwallet.org/explore-icons/mtwcards.webp#1",
//            "iconUrl": "https://static.mytonwallet.org/explore-icons/mtwcards.webp#1",
//             "name": "Sample 2",
//        ]),
//        ApiDapp(dictionary: [
//            "url": "https://static.mytonwallet.org/explore-icons/mtwcards.webp#2",
//            "iconUrl": "https://static.mytonwallet.org/explore-icons/mtwcards.webp#2",
//            "name": "Sample 3",
//        ]),
//        ApiDapp(dictionary: [
//            "url": "https://static.mytonwallet.org/explore-icons/mtwcards.webp#3",
//            "iconUrl": "https://static.mytonwallet.org/explore-icons/mtwcards.webp#3",
//            "name": "Sample 4",
//        ]),
//        ApiDapp(dictionary: [
//            "url": "https://static.mytonwallet.org/explore-icons/mtwcards.webp#4",
//            "iconUrl": "https://static.mytonwallet.org/explore-icons/mtwcards.webp#4",
//            "name": "Sample 5",
//        ]),
//        ApiDapp(dictionary: [
//            "url": "https://static.mytonwallet.org/explore-icons/mtwcards.webp#5",
//            "iconUrl": "https://static.mytonwallet.org/explore-icons/mtwcards.webp#5",
//            "name": "Sample 6",
//        ]),
//    ]
    }
#endif
