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

public struct TokenWidget: Widget {
    public let kind: String = "TokenWidget"
    
    public init() {}

    public var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TokenWidgetConfiguration.self, provider: TokenWidgetTimelineProvider()) { entry in
            TokenWidgetView(entry: entry)
        }
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline, .accessoryRectangular])
        .containerBackgroundRemovable()
        .configurationDisplayName(Text(LocalizedStringResource("Rate", bundle: LocalizationSupport.shared.bundle)))
        .description(Text(LocalizedStringResource("$rate_description", bundle: LocalizationSupport.shared.bundle)))
    }
}

struct TokenWidgetView: View {

    var entry: TokenWidgetTimelineEntry
    @Environment(\.widgetFamily) var widgetFamily
    
    var body: some View {
        ZStack {
            switch widgetFamily {
            case .accessoryRectangular:
                rectangularContent
            case .accessoryCircular:
                circularContent
            case .accessoryInline:
                inlineContent
            default:
                topView
                bottomView
            }
        }
        .containerBackground(for: .widget) {
            CardBackground(tokenSlug: entry.token.slug, tokenColor: entry.token.color)
        }
        .widgetURL(entry.token.internalDeeplinkUrl)
    }
    
    @ViewBuilder
    private var topView: some View {
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
    public var bottomView: some View {
        VStack(alignment: .leading, spacing: 0) {
            RateLarge(rate: entry.currencyRate)
            ChangeView(changePercent: entry.token.percentChange24h, changeInCurrency: entry.changeInCurrency, useColors: false)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    @ViewBuilder
    var rectangularContent: some View {
        VStack(spacing: -2) {
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    changeArrow
                    Text(entry.token.symbol)
                }
                Text(entry.changeInCurrency.formatted(.baseCurrencyEquivalent, showPlus: true))
            }
            Text(entry.currencyRate.formatted(.baseCurrencyPrice))
                .font(.system(size: 72))
                .padding(.top, -2)
                .padding(.bottom, -12)
                .minimumScaleFactor(0.1)
        }
        .imageScale(.small)
        .font(.system(size: 15, weight: .semibold))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    var circularContent: some View {
        Circle().fill(.regularMaterial)
        VStack(spacing: 0) {
            changeArrow
                .padding(.bottom, 1)
                .font(.system(size: 13, weight: .medium))
            Text(entry.token.symbol)
                .font(.system(size: 15, weight: .semibold))
            Text(entry.currencyRate.formatted(.baseCurrencyPrice))
                .font(.system(size: 11, weight: .medium))
                .minimumScaleFactor(0.1)
        }
        .imageScale(.small)
    }
    
    @ViewBuilder
    var inlineContent: some View {
        changeArrow
            .imageScale(.small)
        let symbol = entry.token.symbol
        let price = entry.currencyRate.formatted(.baseCurrencyPrice)
        Text("\(symbol) \(price)")
    }

    @ViewBuilder
    var changeArrow: some View {
        if let change = entry.token.percentChange24h {
            Image(systemName: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
        }
    }
}

#if DEBUG
extension TokenWidgetTimelineEntry {
    static var sample: TokenWidgetTimelineEntry { .placeholder }
}

#Preview(as: .systemSmall) {
    TokenWidget()
} timeline: {
    TokenWidgetTimelineEntry.sample
}
#Preview(as: .accessoryRectangular) {
    TokenWidget()
} timeline: {
    TokenWidgetTimelineEntry.sample
}
#Preview(as: .accessoryCircular) {
    TokenWidget()
} timeline: {
    TokenWidgetTimelineEntry.sample
}
#Preview(as: .accessoryInline) {
    TokenWidget()
} timeline: {
    TokenWidgetTimelineEntry.sample
}
#endif
