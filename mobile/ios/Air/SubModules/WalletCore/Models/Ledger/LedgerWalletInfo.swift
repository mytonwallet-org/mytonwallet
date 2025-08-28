//
//  MWalletVersionsData.swift
//  WalletCore
//
//  Created by Sina on 7/14/24.
//

import Foundation
import BigIntLib


public struct LedgerWalletInfo: Equatable, Hashable, Codable, Sendable {
    public var index: Int
    public var address: String
    public var publicKey: String
    public var balance: BigInt
    public var version: ApiTonWalletVersion
    
    public var driver: ApiLedgerDriver
    public var deviceId: String?
    public var deviceName: String?
    
    public init(index: Int, address: String, publicKey: String, balance: BigInt, version: ApiTonWalletVersion, driver: ApiLedgerDriver, deviceId: String?, deviceName: String?) {
        self.index = index
        self.address = address
        self.publicKey = publicKey
        self.balance = balance
        self.version = version
        self.driver = driver
        self.deviceId = deviceId
        self.deviceName = deviceName
    }
}
