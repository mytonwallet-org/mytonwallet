//
//  MSwapTransferData.swift
//  WalletCore
//
//  Created by Sina on 5/11/24.
//

import Foundation
import WalletContext

public struct MSwapTransferData: Codable {
    
    public struct Transfer: Codable {
        public let toAddress: String
        public let amount: MDouble
        public let payload: String?
    }
    
    public let id: String
    public var transfers: [Transfer]
    public let fee: BigInt?
}
