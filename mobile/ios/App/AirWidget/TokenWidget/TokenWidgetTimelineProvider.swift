//
//  TokenWidgetTimelineProvider.swift
//  App
//
//  Created by nikstar on 23.09.2025.
//

import SwiftUI
import WalletCore
import WidgetKit
import UIKit

struct TokenWidgetTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TokenWidgetTimelineEntry {
        return TokenWidgetTimelineEntry.placeholder
    }

    func snapshot(for configuration: TokenWidgetConfiguration, in context: Context) async -> TokenWidgetTimelineEntry {
        return await loadEntry(for: configuration, date: .now)
    }

    func timeline(for configuration: TokenWidgetConfiguration, in context: Context) async -> Timeline<TokenWidgetTimelineEntry> {
        let entry = await loadEntry(for: configuration, date: .now)
        return Timeline(entries: [entry], policy: .after(Date(timeIntervalSinceNow: 900)))
    }

    private func loadEntry(for configuration: TokenWidgetConfiguration, date: Date) async -> TokenWidgetTimelineEntry {
        let store = SharedStore()
        _ = await store.reloadCache()
        
        let displayCurrency = await store.displayCurrency()
        let tokens = await store.tokensDictionary(tryRemote: true)
        let rates = await store.ratesDictionary()
        
        let selectedSlug = configuration.token.slug
        let token = tokens[selectedSlug] ?? configuration.token
        
        let currencyRate = BaseCurrencyAmount.fromDouble((token.priceUsd ?? 0) * (rates[displayCurrency.rawValue]?.value ?? 1), displayCurrency)
        let changeInCurrency = BaseCurrencyAmount.fromDouble((token.percentChange24hRounded ?? 0) * 0.01 * currencyRate.doubleValue, displayCurrency)
        
        var image: UIImage?
        do {
            if let s = token.image, let url = URL(string: s) {
                let (data, _) = try await URLSession.shared.data(from: url)
                image = await Task { UIImage(data: data) }.value
            }
        } catch {
            print("loadEntry image: \(error)")
        }
        
        return TokenWidgetTimelineEntry(
            date: date,
            token: token,
            image: image,
            currencyRate: currencyRate,
            changeInCurrency: changeInCurrency,
        )
    }
}
