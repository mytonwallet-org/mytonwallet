import WidgetKit
import UIKit
import WalletCoreTypes

struct TokenWithChartWidgetTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TokenWithChartWidgetTimelineEntry {
        TokenWithChartWidgetTimelineEntry.placeholder
    }

    func snapshot(for configuration: TokenWithChartWidgetConfiguration, in context: Context) async -> TokenWithChartWidgetTimelineEntry {
        await loadEntry(for: configuration, date: .now)
    }

    func timeline(for configuration: TokenWithChartWidgetConfiguration, in context: Context) async -> Timeline<TokenWithChartWidgetTimelineEntry> {
        let entry = await loadEntry(for: configuration, date: .now)
        return Timeline(entries: [entry], policy: .after(Date(timeIntervalSinceNow: 900)))
    }

    private func loadEntry(for configuration: TokenWithChartWidgetConfiguration, date: Date) async -> TokenWithChartWidgetTimelineEntry {
        let store = SharedStore()
        _ = await store.reloadCache()

        async let displayCurrency = store.displayCurrency()
        async let tokens = store.tokensDictionary()
        async let rates = store.ratesDictionary()

        let selectedSlug = configuration.token.tokenSlug
        let loadedDisplayCurrency = await displayCurrency
        let loadedTokens = await tokens
        let loadedRates = await rates
        let token = loadedTokens[selectedSlug] ?? configuration.token.apiTokenFallback

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
        var chartCurrency = chartBaseCurrency(for: loadedDisplayCurrency)
        do {
            let loadedChart = try await loadChartData(
                token: token,
                baseCurrency: chartCurrency,
                period: configuration.period
            )
            chartData = loadedChart.data
            chartCurrency = loadedChart.currency
        } catch {
            print("loadEntry chartData: \(error)")
        }

        let currentPrice = chartData.last?.1
            ?? (token.priceUsd ?? 0) * (loadedRates[chartCurrency.rawValue]?.value ?? chartCurrency.fallbackExchangeRate)
        let currencyRate = BaseCurrencyAmount.fromDouble(currentPrice, chartCurrency)

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

    private func loadChartData(token: ApiToken, baseCurrency: MBaseCurrency, period: PricePeriod) async throws -> (data: [(Double, Double)], currency: MBaseCurrency) {
        do {
            return (try await WidgetAPI.fetchChart(for: token, baseCurrency: baseCurrency, period: period), baseCurrency)
        } catch {
            guard baseCurrency != .USD else { throw error }
            return (try await WidgetAPI.fetchChart(for: token, baseCurrency: .USD, period: period), .USD)
        }
    }

    private func chartBaseCurrency(for baseCurrency: MBaseCurrency) -> MBaseCurrency {
        switch baseCurrency {
        case .TON:
            return .USD
        case .USD, .EUR, .RUB, .CNY:
            return baseCurrency
        case .BTC:
            return baseCurrency
        }
    }
}
