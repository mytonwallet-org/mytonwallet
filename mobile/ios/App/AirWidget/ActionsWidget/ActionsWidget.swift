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

public struct ActionsWidget: Widget {
    public let kind: String = "ActionsWidget"
    
    public init() {}

    public var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ActionsWidgetConfiguration.self, provider: ActionsWidgetTimelineProvider()) { entry in
            ActionsWidgetView(entry: entry)
        }
        .contentMarginsDisabled()
        .supportedFamilies([.systemSmall])
        .containerBackgroundRemovable()
        .configurationDisplayName(Text("Actions"))
        .description(Text("Quickly access most common actions"))
    }
}

struct ActionsWidgetView: View {

    var entry: ActionsWidgetTimelineEntry

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ActionButton(label: "add",  image: "AddIcon",  link: "mtw://receive", style: entry.style)
                ActionButton(label: "send", image: "SendIcon", link: "mtw://transfer", style: entry.style)
            }
            HStack(spacing: 8) {
                ActionButton(label: "swap", image: "SwapIcon", link: "mtw://swap", style: entry.style)
                ActionButton(label: "earn", image: "EarnIcon", link: "mtw://stake", style: entry.style)
            }
        }
        .padding(16)
        .containerBackground(for: .widget) {
            switch entry.style {
            case .neutral:
                Color(UIColor(hex: "#F5F5F5"))
            case .vivid:
                CardBackground(tokenSlug: TONCOIN_SLUG, tokenColor: nil)
            }
        }
    }
}

struct ActionButton: View {
    
    var label: String
    var image: String
    var link: String
    var style: ActionsStyle

    var body: some View {
        Link(destination: URL(string: link)!) {
            Image.airBundle(image)
                .renderingMode(.template)
            Text(label)
        }
        .buttonStyle(ActionButtonStyle(style: style))
    }
}

struct ActionButtonStyle: ButtonStyle {
    
    var style: ActionsStyle
    
    @Environment(\.widgetRenderingMode) private var renderingMode
    
    var isFullColor: Bool { renderingMode == .fullColor }

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.label
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(foregroundColor)
        .overlay {
            shape
                .stroke(.white.opacity(0.1), lineWidth: 2)
        }
        .clipShape(shape)
    }
    
    var foregroundColor: Color {
        switch style {
        case .neutral:
            .blue
        case .vivid:
            .white
        }
    }
    
    var backgroundColor: Color {
        switch style {
        case .neutral:
            isFullColor ? .white : .white.opacity(0.1)
        case .vivid:
            .white.opacity(0.15)
        }
    }
    
    var shape: AnyShape {
        if #available(iOS 26.0, *) {
            let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(16)))
            return AnyShape(shape)
        } else {
            let shape = RoundedRectangle(cornerRadius: 16)
            return AnyShape(shape)
        }
    }
}

#if DEBUG
extension ActionsWidgetTimelineEntry {
    static var sample: ActionsWidgetTimelineEntry { .placeholder }
}

#Preview(as: .systemSmall) {
    ActionsWidget()
} timeline: {
    ActionsWidgetTimelineEntry.sample
}
#endif
