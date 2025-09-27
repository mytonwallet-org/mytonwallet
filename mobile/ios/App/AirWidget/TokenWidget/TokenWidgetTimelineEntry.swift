//
//  TokenWidgetTimelineEntry.swift
//  App
//
//  Created by nikstar on 23.09.2025.
//

import SwiftUI
import WalletCore
import WidgetKit

public struct TokenWidgetTimelineEntry: TimelineEntry {
    public var date: Date
    public var token: ApiToken
    public var image: UIImage?
    public var currencyRate: DisplayCurrencyAmount
    public var changeInCurrency: DisplayCurrencyAmount
}

public extension TokenWidgetTimelineEntry {
    static var placeholder: TokenWidgetTimelineEntry {
        var token = ApiToken.TONCOIN
        token.percentChange24h = 3.41
        return TokenWidgetTimelineEntry(
            date: .now,
            token: token,
            image: nil, 
            currencyRate: DisplayCurrencyAmount.fromDouble(4.2, .USD),
            changeInCurrency: DisplayCurrencyAmount.fromDouble(0.2, .USD)
        )
    }
}   
