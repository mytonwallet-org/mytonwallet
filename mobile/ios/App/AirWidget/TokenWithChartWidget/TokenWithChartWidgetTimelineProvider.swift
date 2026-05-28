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

struct TokenWithChartWidgetTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TokenWithChartWidgetTimelineEntry {
        TokenWithChartWidgetTimelineEntry.placeholder
    }

    func snapshot(for configuration: TokenWithChartWidgetConfiguration, in context: Context) async -> TokenWithChartWidgetTimelineEntry {
        return await loadEntry(for: configuration, date: .now)
    }

    func timeline(for configuration: TokenWithChartWidgetConfiguration, in context: Context) async -> Timeline<TokenWithChartWidgetTimelineEntry> {
        let entry = await loadEntry(for: configuration, date: .now)
        return Timeline(entries: [entry], policy: .after(Date(timeIntervalSinceNow: 900)))
    }

    private func loadEntry(for configuration: TokenWithChartWidgetConfiguration, date: Date) async -> TokenWithChartWidgetTimelineEntry {
        let store = SharedStore()
        _ = await store.reloadCache()
        
        async let displayCurrency = store.displayCurrency()
        async let tokens = store.tokensDictionary(tryRemote: true)
        async let rates = store.ratesDictionary()
        
        let selectedSlug = configuration.token.slug
        let token = await tokens[selectedSlug] ?? configuration.token
        
        let currencyRate = await BaseCurrencyAmount.fromDouble((token.priceUsd ?? 0) * (rates[displayCurrency.rawValue]?.value ?? 1), displayCurrency)
        
        var image: UIImage?
        do {
            if let s = token.image, let url = URL(string: s) {
                let (data, _) = try await URLSession.shared.data(from: url)
                image = await Task { UIImage(data: data) }.value
            }
        } catch {
            print("loadEntry image: \(error)")
        }
        
        var chartData: [(Double, Double)] = []
        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.mytonwallet.org/prices/chart/\(token.symbol)?base=\(displayCurrency.rawValue)&period=\(configuration.period.rawValue)")!)
            let decoded = try JSONDecoder().decode(ApiHistoryList.self, from: data)
            chartData = decoded.map { ($0[0], $0[1]) }
        } catch {
            print("loadEntry chartData: \(error)")
        }
        
        return TokenWithChartWidgetTimelineEntry(
            date: date,
            token: token,
            image: image,
            currencyRate: currencyRate,
            period: configuration.period,
            chartData: chartData,
            chartStyle: .vivid // configuration.style,
        )
    }
}
