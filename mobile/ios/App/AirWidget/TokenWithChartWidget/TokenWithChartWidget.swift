//
//  AirWidget.swift
//  AirWidget
//
//  Created by nikstar on 23.09.2025.
//

import SwiftUI
import WalletCore
import WalletContext
import UIComponents
import WidgetKit
import UIKit
import Charts

public struct TokenWithChartWidget: Widget {
    public let kind: String = "TokenWithChartWidget"
    
    public init() {}

    public var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TokenWithChartWidgetConfiguration.self, provider: TokenWithChartWidgetTimelineProvider()) { entry in
            TokenWithChartWidgetView(entry: entry)
        }
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .containerBackgroundRemovable()
        .configurationDisplayName(Text(LocalizedStringResource("Rate with Chart", bundle: LocalizationSupport.shared.bundle)))
        .description(Text(LocalizedStringResource("$rate_with_chart_description", bundle: LocalizationSupport.shared.bundle)))
    }
}

struct TokenWithChartWidgetView: View {
    var entry: TokenWithChartWidgetTimelineEntry

    @Environment(\.widgetFamily) private var family
    
    var isVivid: Bool { entry.chartStyle == .vivid }
    var isSmall: Bool { family == .systemSmall }
    var isMedium: Bool { family == .systemMedium }
    var isRectangularAccessory: Bool { family == .accessoryRectangular }
    
    var body: some View {
        ZStack {
            ChartView(token: entry.token, chartData: entry.chartData, chartStyle: entry.chartStyle)
            
            if isSmall {
                topSmall
            } else if isMedium {
                topMedium
            }
            
            if isSmall {
                bottomSmall
            } else if isMedium {
                bottomMedium
            }
            
            if isRectangularAccessory {
                accessoryTopLine
            }
        }
        .containerBackground(for: .widget) {
            background
        }
        .widgetURL(entry.token.internalDeeplinkUrl)
    }
    
    @ViewBuilder
    var topSmall: some View {
        HStack(spacing: 0) {
            TokenImage(image: entry.image, size: 28)
            Spacer()
            Text(entry.token.symbol)
                .font(.system(size: 17, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.trailing, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    @ViewBuilder
    var topMedium: some View {
        HStack(spacing: 6) {
            TokenImage(image: entry.image, size: 24)
            Text(entry.token.symbol)
                .font(.system(size: 17, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.white)
            change
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    @ViewBuilder
    var bottomSmall: some View {
        VStack(alignment: .leading, spacing: 0) {
            RateLarge(rate: entry.currencyRate)
            change
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    @ViewBuilder
    var bottomMedium: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                if let firstDate = entry.firstDate, let firstValue = entry.firstValue {
                    Text(firstValue.formatted(.baseCurrencyPrice))
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Text(firstDateString(date: firstDate))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(entry.currencyRate.formatted(.baseCurrencyPrice))
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                if let lastDate = entry.lastDate {
                    Text(lastDateString(date: lastDate))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    func firstDateString(date: Date) -> String {
        if entry.period == .year || entry.period == .all {
            date.formatted(.dateTime.year().month(.abbreviated).day())
        } else {
            date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
    
    func lastDateString(date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour(.defaultDigits(amPM: .narrow)).minute())
    }
    
    var tintColor: Color {
        colorForSlug(entry.token.slug, tokenColor: entry.token.color)
    }
    
    @ViewBuilder
    var change: some View {
        ChangeView(changePercent: entry.changePercent, changeInCurrency: entry.changeInCurrency, useColors: false)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(isVivid ? .white.opacity(0.75) : tintColor)
    }
    
    @ViewBuilder
    private var background: some View {
        if isVivid {
            CardBackground(tokenSlug: entry.token.slug, tokenColor: entry.token.color)
        } else {
            LinearGradient(
                colors: [
                    Color(UIColor(hex: "#252525")),
                    Color(UIColor(hex: "#1A1A1A")),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    @ViewBuilder
    var accessoryTopLine: some View {
        HStack(spacing: 2) {
            changeArrow
            Text(entry.token.symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.currencyRate.formatted(.baseCurrencyPrice))
                .fontWeight(.medium)
        }
        .imageScale(.small)
        .font(.system(size: 15, weight: .bold))
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    @ViewBuilder
    var changeArrow: some View {
        if let change = entry.changePercent {
            Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
        }
    }
}

#if DEBUG
extension TokenWithChartWidgetTimelineEntry {
    static var sample: TokenWithChartWidgetTimelineEntry {
        var sample = TokenWithChartWidgetTimelineEntry.placeholder
        sample.chartData = [(0, 10), (0.25,10.75), (0.5,10.75), (0.75,9.6), (1,10)]
        return sample
    }
}

#Preview(as: .systemMedium) {
    TokenWithChartWidget()
} timeline: {
    TokenWithChartWidgetTimelineEntry.sample
}
#Preview(as: .systemSmall) {
    TokenWithChartWidget()
} timeline: {
    TokenWithChartWidgetTimelineEntry.sample
}
#Preview(as: .accessoryRectangular) {
    TokenWithChartWidget()
} timeline: {
    TokenWithChartWidgetTimelineEntry.sample
}
#endif
