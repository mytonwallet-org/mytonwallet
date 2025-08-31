//
//  MRecentAddress.swift
//  WalletCore
//
//  Created by Sina on 4/19/24.
//

import Foundation

public struct MRecentAddress: Codable {
    public let chain: String
    public let address: String
    public let addressAlias: String?
    public let timstamp: Double

    public init(chain: String, address: String, addressAlias: String?, timstamp: Double) {
        self.chain = chain
        self.address = address
        self.addressAlias = addressAlias
        self.timstamp = timstamp
    }
}
