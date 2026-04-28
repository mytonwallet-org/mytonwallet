import SwiftUI
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
        .configurationDisplayName(Text(localized("Actions")))
        .description(Text(localized("$actions_description")))
    }
}

struct ActionsWidgetView: View {
    var entry: ActionsWidgetTimelineEntry

    var body: some View {
        ViewThatFits {
            content(usesUnevenCorners: false)
                .padding(16)
            content(usesUnevenCorners: true)
                .padding(8)
        }
        .containerBackground(for: .widget) {
            switch entry.style {
            case .neutral:
                Color(UIColor(hex: "#F5F5F5"))
            case .vivid:
                CardBackground(tokenSlug: TONCOIN_SLUG, tokenColor: nil)
            }
        }
    }

    func content(usesUnevenCorners: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ActionButton(
                    label: localized("add"),
                    image: "AddIcon",
                    link: "\(SELF_PROTOCOL)receive",
                    style: entry.style,
                    usesUnevenCorners: usesUnevenCorners,
                    rotationIndex: 0,
                )
                ActionButton(
                    label: localized("send"),
                    image: "SendIcon",
                    link: "\(SELF_PROTOCOL)transfer",
                    style: entry.style,
                    usesUnevenCorners: usesUnevenCorners,
                    rotationIndex: 1,
                )
            }
            HStack(spacing: 8) {
                ActionButton(
                    label: localized("swap"),
                    image: "SwapIcon",
                    link: "\(SELF_PROTOCOL)swap",
                    style: entry.style,
                    usesUnevenCorners: usesUnevenCorners,
                    rotationIndex: 3,
                )
                ActionButton(
                    label: localized("earn"),
                    image: "EarnIcon",
                    link: "\(SELF_PROTOCOL)stake",
                    style: entry.style,
                    usesUnevenCorners: usesUnevenCorners,
                    rotationIndex: 2,
                )
            }
        }
    }
}

struct ActionButton: View {
    var label: LocalizedStringResource
    var image: String
    var link: String
    var style: ActionsStyle
    var usesUnevenCorners: Bool
    var rotationIndex: Int

    var body: some View {
        Link(destination: URL(string: link)!) {
            Image(image)
                .renderingMode(.template)
            Text(label)
                .fixedSize()
                .padding(.horizontal, 3)
        }
        .buttonStyle(ActionButtonStyle(style: style, usesUnevenCorners: usesUnevenCorners, rotationIndex: rotationIndex))
    }
}

struct ActionButtonStyle: ButtonStyle {
    var style: ActionsStyle
    var usesUnevenCorners: Bool
    var rotationIndex: Int

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground

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
        if usesUnevenCorners {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 12,
                bottomTrailingRadius: 12,
                topTrailingRadius: 12,
            )
            .rotation(.degrees(90.0 * Double(rotationIndex)))
            return AnyShape(shape)
        }

        if #available(iOS 26.0, *) {
            if showsWidgetContainerBackground {
                return AnyShape(ConcentricRectangle(corners: .concentric(minimum: 12)))
            }
        }

        return AnyShape(RoundedRectangle(cornerRadius: 16))
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
