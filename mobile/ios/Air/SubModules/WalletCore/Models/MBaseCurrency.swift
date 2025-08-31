//
//  MBaseCurrency.swift
//  WalletCore
//
//  Created by Sina on 3/26/24.
//

import Foundation
import WalletContext

public enum MBaseCurrency: String, Equatable, Hashable, Codable, Sendable, Identifiable, CaseIterable {
    case USD = "USD"
    case EUR = "EUR"
    case RUB = "RUB"
    case CNY = "CNY"
    case BTC = "BTC"
    case TON = "TON"
    
    public var sign: String {
        switch self {
        case .USD:
            return "$"
        case .EUR:
            return "€"
        case .RUB:
            return "₽"
        case .CNY:
            return "¥"
        case .BTC:
            return "BTC"
        case .TON:
            return "TON"
        }
    }
    
    public var decimalsCount: Int {
        switch self {
        case .BTC:
            6
        default:
            2
        }
    }
    
    public var symbol: String {
        switch self {
        case .USD:
            return lang("USD")
        case .EUR:
            return lang("EUR")
        case .RUB:
            return lang("RUB")
        case .CNY:
            return lang("CNY")
        case .BTC:
            return lang("BTC")
        case .TON:
            return lang("TON")
        }
    }

    public var name: String {
        switch self {
        case .USD:
            return lang("United States Dollar")
        case .EUR:
            return lang("Euro")
        case .RUB:
            return lang("Russian Ruble")
        case .CNY:
            return lang("Chinese Yuan")
        case .BTC:
            return lang("Bitcoin")
        case .TON:
            return lang("Toncoin")
        }
    }
    
    public var id: Self { self }
    
    var fallbackExchangeRate: Double {
        switch self {
        case .USD:
            1.0
        case .EUR:
            1.0 / 1.1
        case .RUB:
            80.0
        case .CNY:
            7.2
        case .BTC:
            1.0 / 100_000.0
        case .TON:
            1.0 / 3.0
        }
    }
}


