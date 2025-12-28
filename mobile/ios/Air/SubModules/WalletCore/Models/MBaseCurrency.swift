//
//  MBaseCurrency.swift
//  WalletCore
//
//  Created by Sina on 3/26/24.
//

import Foundation
import WalletContext

public let DEFAULT_PRICE_CURRENCY = MBaseCurrency.USD

public enum MBaseCurrency: String, Equatable, Hashable, Codable, Sendable, Identifiable, CaseIterable {
    case USD = "USD"
    case EUR = "EUR"
    case RUB = "RUB"
    case CNY = "CNY"
    case BTC = "BTC"
    case TON = "TON"
    
    public var sign: String {
        switch self {
        case .USD: "$"
        case .EUR: "€"
        case .RUB: "₽"
        case .CNY: "¥"
        case .BTC: "BTC"
        case .TON: "TON"
        }
    }
    
    public var decimalsCount: Int {
        switch self {
        case .USD: 6
        case .EUR: 6
        case .RUB: 6
        case .CNY: 6
        case .BTC: 8
        case .TON: 9
        }
    }
    
    public var symbol: String {
        return rawValue
    }

    public var name: String {
        switch self {
        case .USD: lang("US Dollar")
        case .EUR: lang("Euro")
        case .RUB: lang("Russian Ruble")
        case .CNY: lang("Chinese Yuan")
        case .BTC: lang("Bitcoin")
        case .TON: lang("Toncoin")
        }
    }
    
    public var id: Self { self }
    
    public var fallbackExchangeRate: Double {
        switch self {
        case .USD: 1.0
        case .EUR: 1.0 / 1.1
        case .RUB: 80.0
        case .CNY: 7.2
        case .BTC: 1.0 / 100_000.0
        case .TON: 1.0 / 3.0
        }
    }
    
    public var preferredDecimals: Int? {
        switch self {
        case .USD: 2
        case .EUR: 2
        case .RUB: 2
        case .CNY: 2
        case .BTC: nil
        case .TON: nil
        }
    }
}
