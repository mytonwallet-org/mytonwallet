//
//  MAccount.swift
//  WalletCore
//
//  Created by Sina on 3/20/24.
//

import UIKit
import WalletContext


extension MAccount {
    public struct Ledger: Equatable, Hashable, Codable, Sendable {
        public var index: Int
        public var driver: ApiLedgerDriver
        public var deviceId: String?
        public var deviceName: String?
        
        init(index: Int, driver: ApiLedgerDriver, deviceId: String?, deviceName: String?) {
            self.index = index
            self.driver = driver
            self.deviceId = deviceId
            self.deviceName = deviceName
        }
        
        public init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer<MAccount.Ledger.CodingKeys> = try decoder.container(keyedBy: MAccount.Ledger.CodingKeys.self)
            self.index = try container.decode(Int.self, forKey: .index)
            self.driver = container.decodeWithDefault(ApiLedgerDriver.self, forKey: .driver, default: .hid)
            self.deviceId = container.decodeOptional(String.self, forKey: .deviceId)
            self.deviceName = container.decodeOptional(String.self, forKey: .deviceName)
        }
    }
}
