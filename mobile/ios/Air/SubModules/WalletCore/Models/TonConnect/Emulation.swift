//
//  Emulation.swift
//  MyTonWalletAir
//
//  Created by nikstar on 20.08.2025.
//

import WalletContext

public struct Emulation: Equatable, Hashable, Codable, Sendable {
    public var activities: [ApiActivity]
    public var realFee: BigInt
    
    public init(activities: [ApiActivity], realFee: BigInt) {
        self.activities = activities
        self.realFee = realFee
    }
}
