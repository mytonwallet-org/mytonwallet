import SwiftUI
import UIKit
import UIComponents
import WalletContext

/// One metric of the Info card, shared by token and futures pages.
struct AssetInfoField: Equatable, Identifiable {
    let id: String
    let title: String
    var info: String?
    let value: String
}

/// Info card content for an asset without token details, such as a futures market.
struct AssetInfoSummary: Equatable {
    var description: String?
    var fields: [AssetInfoField]
    var isStale = false
}

struct AssetInfoMetricRow: View {
    let title: String
    var info: String? = nil
    let value: String
    var valueColor: Color = .air.primaryLabel
    var previousValue: String? = nil
    var isStale = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(verbatim: title)
                    .textStyle(.body)
                    .foregroundStyle(Color.air.secondaryLabel)
                if let info {
                    AssetInfoHelpButton(title: title, message: info)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .layoutPriority(previousValue == nil ? 0 : 1)
            Spacer(minLength: 4)
            valueText
                .textStyle(.body, content: .technical)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .mask { LoadingShineMask(isActive: isStale) }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }

    /// A change too wide for one line puts the new value on a second line instead of truncating it.
    @ViewBuilder private var valueText: some View {
        if let previousValue {
            let previous = Text(verbatim: previousValue).foregroundColor(.air.secondaryLabel)
            ViewThatFits(in: .horizontal) {
                previous + Text(" → ").foregroundColor(valueColor) + Text(verbatim: value)
                VStack(alignment: .trailing, spacing: 2) {
                    previous + Text(" →").foregroundColor(valueColor)
                    Text(verbatim: value)
                }
                .padding(.vertical, 10)
            }
        } else {
            Text(verbatim: value)
        }
    }
}

struct AssetInfoHelpButton: View {
    let title: String
    let message: String

    var body: some View {
        Button {
            topViewController()?.showTip(title: title, message: message)
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .textStyle(.supporting, content: .technical)
                .foregroundStyle(Color.air.secondaryLabel.opacity(0.4))
                .frame(width: 16, height: 22)
                // A 44-point touch target that does not move the row's layout.
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(.rect)
        }
        .padding(.horizontal, -14)
        .padding(.vertical, -11)
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(lang("Shows more information"))
    }
}

struct AssetInfoSplitBar: View {
    let positiveValue: Double
    let negativeValue: Double
    let positiveLabel: String
    let negativeLabel: String
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { proxy in
            let layout = AssetInfoSplitBarLayout.resolve(
                buy: positiveValue, sell: negativeValue, width: proxy.size.width,
                buyLabelWidth: labelWidth(positiveLabel), sellLabelWidth: labelWidth(negativeLabel)
            )
            HStack(spacing: layout.spacing) {
                if let width = layout.buyWidth {
                    segment(positiveLabel, color: .air.positiveAmount, width: width,
                            isLeading: true, isStandalone: layout.sellWidth == nil)
                }
                if let width = layout.sellWidth {
                    segment(negativeLabel, color: .air.negativeAmount, width: width,
                            isLeading: false, isStandalone: layout.buyWidth == nil)
                }
            }
        }
        .frame(height: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(positiveLabel), \(negativeLabel)")
    }

    private func labelWidth(_ value: String) -> CGFloat {
        ceil((value as NSString).size(withAttributes: [
            .font: WTypography.uiFont(.footnoteEmphasized, content: .technical),
        ]).width)
    }

    private func segment(_ value: String, color: Color, width: CGFloat,
                         isLeading: Bool, isStandalone: Bool) -> some View {
        ZStack(alignment: isLeading ? .leading : .trailing) {
            color
            LinearGradient(colors: [.white.opacity(0.15), .white.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
            Text(verbatim: value)
                .textStyle(.footnoteEmphasized, content: .technical)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, AssetInfoSplitBarLayout.labelHorizontalPadding)
        }
        .frame(width: width, height: 26)
        .clipShape(AssetInfoSplitBarSegmentShape(isLeading: isLeading, isStandalone: isStandalone,
                                               layoutDirection: layoutDirection))
    }
}

struct AssetInfoSplitBarLayout: Equatable {
    static let segmentSpacing = CGFloat(4)
    static let labelHorizontalPadding = CGFloat(8)

    let buyWidth: CGFloat?
    let sellWidth: CGFloat?
    let spacing: CGFloat

    static func resolve(
        buy: Double,
        sell: Double,
        width: CGFloat,
        buyLabelWidth: CGFloat,
        sellLabelWidth: CGFloat
    ) -> Self {
        let buy = max(0, buy)
        let sell = max(0, sell)
        let width = max(0, width)

        if buy == 0, sell > 0 {
            return Self(buyWidth: nil, sellWidth: width, spacing: 0)
        }
        if sell == 0, buy > 0 {
            return Self(buyWidth: width, sellWidth: nil, spacing: 0)
        }

        let availableWidth = max(0, width - segmentSpacing)
        if buy == 0, sell == 0 {
            return Self(
                buyWidth: availableWidth / 2,
                sellWidth: availableWidth / 2,
                spacing: segmentSpacing
            )
        }

        let rawBuyWidth = availableWidth * buy / (buy + sell)
        let buyMinimumWidth = buyLabelWidth + 2 * labelHorizontalPadding
        let sellMinimumWidth = sellLabelWidth + 2 * labelHorizontalPadding
        let buyWidth: CGFloat
        if buyMinimumWidth + sellMinimumWidth <= availableWidth {
            buyWidth = min(
                max(rawBuyWidth, buyMinimumWidth),
                availableWidth - sellMinimumWidth
            )
        } else {
            buyWidth = availableWidth * buyMinimumWidth / (buyMinimumWidth + sellMinimumWidth)
        }

        return Self(
            buyWidth: buyWidth,
            sellWidth: availableWidth - buyWidth,
            spacing: segmentSpacing
        )
    }
}

private struct AssetInfoSplitBarSegmentShape: Shape {
    let isLeading: Bool
    let isStandalone: Bool
    let layoutDirection: LayoutDirection

    func path(in rect: CGRect) -> Path {
        let outerRadius = rect.height / 2
        let innerRadius = min(CGFloat(3), outerRadius)
        let isOuterOnLeft = isLeading == (layoutDirection == .leftToRight)
        let leftRadius = isStandalone || isOuterOnLeft ? outerRadius : innerRadius
        let rightRadius = isStandalone || !isOuterOnLeft ? outerRadius : innerRadius

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + leftRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rightRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rightRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rightRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rightRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + leftRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - leftRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + leftRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + leftRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

struct AssetInfoDescriptionText: View {
    let text: String
    let color: Color
    let lineLimit: Int?

    var body: some View {
        let extraLineHeight = max(0, 22 - WTypography.uiFont(.callout).lineHeight)
        Text(verbatim: text)
            .textStyle(.callout)
            .tracking(-0.12)
            .lineSpacing(extraLineHeight)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
            .padding(.vertical, extraLineHeight / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AssetInfoDescriptionView: View {
    let text: String
    let color: Color
    let canToggle: Bool
    let showsFullDescription: Bool
    var accessibilityIdentifier = "Token.Info.ShowMore"
    let onToggle: () -> Void

    @State private var previewHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AssetInfoDescriptionText(text: text, color: color, lineLimit: showsFullDescription ? nil : 3)
                .background(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        AssetInfoDescriptionText(text: text, color: color, lineLimit: 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { previewHeight = $0 }
                        AssetInfoDescriptionText(text: text, color: color, lineLimit: nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { fullHeight = $0 }
                    }
                    .hidden()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            if canToggle, fullHeight > previewHeight + 0.5 {
                Button(action: onToggle) {
                    Text(lang(showsFullDescription ? "Show Less" : "Show More"))
                        .textStyle(.callout)
                        .tracking(-0.12)
                        .frame(height: 22, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityIdentifier(accessibilityIdentifier)
            }
        }
    }
}

