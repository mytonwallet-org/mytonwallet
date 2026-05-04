//
//  ApiNftMarketplace.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.08.2025.
//

public enum ApiNftMarketplace: String, Equatable, Hashable, Codable, Sendable {
    case fragment = "fragment"
    case getgems = "getgems"
    case opensea = "opensea"

    public var displayName: String {
        switch self {
        case .fragment:
            "Fragment"
        case .getgems:
            "Getgems"
        case .opensea:
            "OpenSea"
        }
    }
}
