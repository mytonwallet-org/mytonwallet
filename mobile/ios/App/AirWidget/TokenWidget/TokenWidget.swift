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
        .configurationDisplayName(Text("Rate"))
        .description(Text("View current rate of any selected token."))
    }
}

struct TokenWidgetView: View {

    var entry: TokenWidgetTimelineEntry
    
    var body: some View {
        ZStack {
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
            
            bottomView
        }
        .containerBackground(for: .widget) {
            CardBackground(tokenSlug: entry.token.slug, tokenColor: entry.token.color)
        }
    }
    
    @ViewBuilder
    public var change: some View {
        ChangeView(changePercent: entry.token.percentChange24h, changeInCurrency: entry.changeInCurrency, useColors: false)
            .font(.system(size: 14, weight: .regular))
    }
    
    @ViewBuilder
    public var bottomView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.currencyRate.formatted(maxDecimals: entry.currencyRate.adaptiveDecimals()))
                .font(.compactRoundedSemibold(size: 32))
                .lineLimit(1)
                .foregroundStyle(.white)
            change
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
