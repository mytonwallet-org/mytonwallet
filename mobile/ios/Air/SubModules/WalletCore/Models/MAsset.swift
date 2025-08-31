//
//  MPair.swift
//  WalletCore
//
//  Created by Sina on 5/10/24.
//

import Foundation

public struct MPair: Equatable, Hashable, Codable {

    public let symbol: String
    public let slug: String
    public let contract: String?
    public let isReverseProhibited: Bool?
}
