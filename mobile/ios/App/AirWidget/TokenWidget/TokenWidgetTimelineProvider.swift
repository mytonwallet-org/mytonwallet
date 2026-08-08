import WidgetKit
import UIKit
import WalletCoreTypes

struct TokenWidgetTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TokenWidgetTimelineEntry {
        TokenWidgetTimelineEntry.placeholder
    }

    func snapshot(for configuration: TokenWidgetConfiguration, in context: Context) async -> TokenWidgetTimelineEntry {
        await loadEntry(for: configuration, date: .now)
    }

    func timeline(for configuration: TokenWidgetConfiguration, in context: Context) async -> Timeline<TokenWidgetTimelineEntry> {
        let entry = await loadEntry(for: configuration, date: .now)
        return Timeline(entries: [entry], policy: .after(Date(timeIntervalSinceNow: 900)))
    }

    private func loadEntry(for configuration: TokenWidgetConfiguration, date: Date) async -> TokenWidgetTimelineEntry {
        let store = SharedStore()
        _ = await store.reloadCache()
        
        let displayCurrency = await store.displayCurrency()
        let tokens = await store.tokensDictionary()
        let cachedRates = await store.ratesDictionary()
        
        let selectedSlug = configuration.token.tokenSlug
        let requestToken = tokens[selectedSlug] ?? configuration.token.apiTokenFallback

        async let latestPrice = loadPrice(for: requestToken)
        async let latestRates = loadCurrencyRates()

        var token = requestToken
        if let price = await latestPrice {
            token.priceUsd = price.priceUsd
            token.percentChange24h = price.percentChange24h
        }
        let rates = await latestRates ?? cachedRates
        
        let currencyRate = BaseCurrencyAmount.fromDouble(
            (token.priceUsd ?? 0) * (rates[displayCurrency.rawValue]?.value ?? displayCurrency.fallbackExchangeRate),
            displayCurrency
        )
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

    private func loadPrice(for token: ApiToken) async -> WidgetAPI.TokenPrice? {
        do {
            return try await WidgetAPI.fetchPrice(for: token)
        } catch {
            print("loadEntry price: \(error)")
            return nil
        }
    }

    private func loadCurrencyRates() async -> [String: MDouble]? {
        do {
            return try await WidgetAPI.fetchCurrencyRates()
        } catch {
            print("loadEntry currencyRates: \(error)")
            return nil
        }
    }
}
