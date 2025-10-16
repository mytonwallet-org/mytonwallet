//
//  ApiDappConnectionType.swift
//  MyTonWalletAir
//
//  Created by nikstar on 13.10.2025.
//

public enum ApiDappConnectionType: String, Equatable, Hashable, Codable, Sendable {
    case connect
    case sendTransaction
    case signData
}
