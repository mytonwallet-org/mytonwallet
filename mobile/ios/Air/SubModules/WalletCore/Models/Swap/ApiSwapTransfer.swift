//
//  ApiSwapTransfer.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//


public struct ApiSwapTransfer: Codable {
    public let toAddress: String
    public let amount: String
    public let payload: String?
}

