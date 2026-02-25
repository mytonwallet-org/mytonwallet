//
//  MDapp.swift
//  WalletCore
//
//  Created by Sina on 8/14/24.
//

import Foundation

public struct ApiDapp: Equatable, Hashable, Codable, Sendable {
    
    public let url: String
    public let name: String
    public let iconUrl: String
    public let manifestUrl: String?
    
    public let connectedAt: Int?
    public let isUrlEnsured: Bool?
    public let sse: ApiSseOptions?
    
    public init(url: String, name: String, iconUrl: String, manifestUrl: String? = nil, connectedAt: Int?, isUrlEnsured: Bool?, sse: ApiSseOptions?) {
        self.url = url
        self.name = name
        self.iconUrl = iconUrl
        self.manifestUrl = manifestUrl
        self.connectedAt = connectedAt
        self.isUrlEnsured = isUrlEnsured
        self.sse = sse
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
            isUrlEnsured: nil,
            sse: nil,
        )
    
        public static let sampleList: [ApiDapp] = [
            ApiDapp(url: "https://static.mytonwallet.org",
                    name: "Sample name",
                    iconUrl: "https://static.mytonwallet.org/explore-icons/mtwcards.webp",
                    manifestUrl: "https://fragment.com/tonconnect-manifest.json",
                    connectedAt: nil,
                    isUrlEnsured: nil,
                    sse: nil),
            
            ApiDapp(url: "https://app.storm.tg",
                    name: "Storm Trade",
                    iconUrl: "https://static.mytonwallet.org/explore-icons/storm.jpg",
                    manifestUrl: "https://fragment.com/tonconnect-manifest.json",
                    connectedAt: nil,
                    isUrlEnsured: nil,
                    sse: nil),
            
            ApiDapp(url: "https://app.upscale.trade",
                    name: "Upscale",
                    iconUrl: "https://static.mytonwallet.org/explore-icons/upscale.png",
                    manifestUrl: "https://fragment.com/tonconnect-manifest.json",
                    connectedAt: nil,
                    isUrlEnsured: nil,
                    sse: nil),
            
            ApiDapp(url: "https://app.bidask.finance",
                    name: "Bidask",
                    iconUrl: "https://static.mytonwallet.org/explore-icons/bidask.png",
                    manifestUrl: "https://fragment.com/tonconnect-manifest.json",
                    connectedAt: nil,
                    isUrlEnsured: nil,
                    sse: nil),
            
            ApiDapp(url: "https://app.hipo.finance",
                    name: "Hipo",
                    iconUrl: "https://static.mytonwallet.org/explore-icons/hipo_dark.png",
                    manifestUrl: "https://fragment.com/tonconnect-manifest.json",
                    connectedAt: nil,
                    isUrlEnsured: nil,
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
