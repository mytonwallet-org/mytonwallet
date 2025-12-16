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
        .supportedFamilies([.systemSmall])
        .containerBackgroundRemovable()
        .configurationDisplayName(Text(LocalizedStringResource("Rate", bundle: LocalizationSupport.shared.bundle)))
        .description(Text(LocalizedStringResource("$rate_description", bundle: LocalizationSupport.shared.bundle)))
    }
}

struct TokenWidgetView: View {

    var entry: TokenWidgetTimelineEntry
    
    var body: some View {
        ZStack {
            topView
            bottomView
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
#endif
