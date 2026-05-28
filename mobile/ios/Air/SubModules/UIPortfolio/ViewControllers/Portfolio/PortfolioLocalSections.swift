import Perception
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

enum PortfolioInsightCardID: String, Hashable {
    case chainSplit
    case assetClasses
    case staked
}

struct PortfolioInsightSegment: Equatable, Identifiable {
    let id: String
    let title: String
    let value: Double
    let valueText: String
    let colorHex: String
}

struct PortfolioInsightCardModel: Equatable, Identifiable {
    let id: PortfolioInsightCardID
    let title: String
    let segments: [PortfolioInsightSegment]
    let emptyText: String?
}

struct PortfolioOverviewSectionView: View {
    let accountContext: AccountContext
    let overview: PortfolioOverviewModel

    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    Text(lang("Overview"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.air.secondaryLabel)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let dateRangeText = overview.dateRangeText {
                        Text(dateRangeText)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color(uiColor: .air.secondaryLabel))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 9)
                .frame(maxWidth: .infinity, minHeight: 39, maxHeight: 39, alignment: .bottom)

                HStack(alignment: .center, spacing: 16) {
                    overviewColumn(
                        value: accountContext.balance?.formatted(.baseCurrencyEquivalent, roundHalfUp: true),
                        title: lang("Total Balance")
                    )

                    overviewColumn(
                        value: overview.netChangeText,
                        title: lang("Net Change"),
                        trailingText: overview.netChangePercentText,
                        trailingColor: overview.isNetChangePositive ? .air.positiveAmount : .air.negativeAmount
                    )
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66)
                .background(Color.air.groupedItem)
                .clipShape(.rect(cornerRadius: 26, style: .continuous))
            }
        }
    }

    private func overviewColumn(
        value: String?,
        title: String,
        trailingText: String? = nil,
        valueColor: UIColor = .label,
        trailingColor: UIColor = .air.secondaryLabel
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(uiColor: valueColor))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(accountContext.isCurrent ? .numericText() : .identity)

                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(uiColor: trailingColor))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sensitiveData(
                alignment: .leading,
                cols: 8,
                rows: 2,
                cellSize: 6,
                theme: .adaptive,
                cornerRadius: 6
            )

            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.air.secondaryLabel)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PortfolioInsightCardView: View {
    let card: PortfolioInsightCardModel

    private var displayedSegments: [PortfolioInsightSegment] {
        card.segments
            .filter { $0.value > 0 }
            .sorted { $0.value < $1.value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.air.secondaryLabel)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.bottom, 9)
                .frame(maxWidth: .infinity, minHeight: 39, maxHeight: 39, alignment: .bottomLeading)

            HStack(spacing: 24) {
                if displayedSegments.isEmpty {
                    Text(card.emptyText ?? lang("No data"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.air.secondaryLabel)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    PortfolioInsightBarrelView(segments: displayedSegments)
                        .frame(width: 80, height: 160)

                    PortfolioInsightLegendView(
                        segments: displayedSegments,
                        totalValue: displayedSegments.reduce(0) { $0 + $1.value }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 192, maxHeight: 192, alignment: .leading)
            .background(Color.air.groupedItem)
            .clipShape(.rect(cornerRadius: 26, style: .continuous))
        }
        .frame(maxWidth: .infinity, minHeight: 231, maxHeight: 231, alignment: .topLeading)
    }
}

private struct PortfolioInsightBarrelView: View {
    let segments: [PortfolioInsightSegment]

    private let preferredWidth = CGFloat(80)
    private let preferredOvalHeight = CGFloat(40)
    private let gapHeight = CGFloat(2)

    var body: some View {
        Canvas { context, size in
            let totalValue = segments.reduce(0) { $0 + $1.value }
            guard totalValue > 0, !segments.isEmpty else {
                return
            }

            let width = min(size.width, preferredWidth)
            let x = (size.width - width) / 2
            let ovalHeight = min(preferredOvalHeight, width / 2, size.height)
            let bodyHeight = max(size.height - ovalHeight, 0)
            let totalGapHeight = gapHeight * CGFloat(max(segments.count - 1, 0))
            let valuesHeight = max(bodyHeight - totalGapHeight, 0)
            var segmentSlices: [(segment: PortfolioInsightSegment, topY: CGFloat, bottomY: CGFloat)] = []
            var gapSlices: [(topY: CGFloat, bottomY: CGFloat)] = []
            var currentY = CGFloat(0)

            for index in segments.indices {
                let isLast = index == segments.index(before: segments.endIndex)
                let segment = segments[index]
                let sliceHeight = isLast
                    ? max(bodyHeight - currentY, 0)
                    : valuesHeight * CGFloat(segment.value / totalValue)
                let bottomY = min(currentY + sliceHeight, bodyHeight)
                segmentSlices.append((segment, currentY, bottomY))
                currentY = bottomY

                if !isLast {
                    let gapBottomY = min(currentY + gapHeight, bodyHeight)
                    gapSlices.append((currentY, gapBottomY))
                    currentY = gapBottomY
                }
            }

            for slice in segmentSlices.reversed() {
                let path = Self.sidePath(
                    x: x,
                    width: width,
                    topY: slice.topY,
                    bottomY: slice.bottomY,
                    ovalHeight: ovalHeight
                )
                context.fill(path, with: .color(Color(UIColor(hex: slice.segment.colorHex))))

                // Classic-matching glossy highlight: vertical white gradient from 24% at
                // 16.8% of body height to 0% at 94.5%
                let halfOvalHeight = ovalHeight / 2
                let bodyTop = slice.topY + halfOvalHeight
                let bodyBottom = slice.bottomY + ovalHeight
                let bodyExtent = bodyBottom - bodyTop
                context.fill(
                    path,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: .white.opacity(0.24), location: 0),
                            .init(color: .white.opacity(0), location: 1),
                        ]),
                        startPoint: CGPoint(x: 0, y: bodyTop + 0.168 * bodyExtent),
                        endPoint: CGPoint(x: 0, y: bodyTop + 0.945 * bodyExtent)
                    )
                )
            }

            for slice in gapSlices {
                let path = Self.sidePath(
                    x: x,
                    width: width,
                    topY: slice.topY,
                    bottomY: slice.bottomY,
                    ovalHeight: ovalHeight
                )
                context.fill(path, with: .color(Color.air.groupedItem))
            }

            if let topSegment = segments.first {
                let topEllipse = Path(ellipseIn: CGRect(x: x, y: 0, width: width, height: ovalHeight))
                context.fill(topEllipse, with: .color(Color(UIColor(hex: topSegment.colorHex))))
                context.fill(topEllipse, with: .color(.white.opacity(0.4)))
            }
        }
    }

    private static func sidePath(
        x: CGFloat,
        width: CGFloat,
        topY: CGFloat,
        bottomY: CGFloat,
        ovalHeight: CGFloat
    ) -> Path {
        let halfOvalHeight = ovalHeight / 2
        var path = Path()
        path.move(to: CGPoint(x: x, y: topY + halfOvalHeight))
        addBottomHalfOval(to: &path, x: x, y: topY, width: width, height: ovalHeight, leftToRight: true)
        path.addLine(to: CGPoint(x: x + width, y: bottomY + halfOvalHeight))
        addBottomHalfOval(to: &path, x: x, y: bottomY, width: width, height: ovalHeight, leftToRight: false)
        path.closeSubpath()
        return path
    }

    private static func addBottomHalfOval(
        to path: inout Path,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        leftToRight: Bool
    ) {
        let kappa = CGFloat(0.5522847498)
        let radiusX = width / 2
        let radiusY = height / 2
        let centerX = x + radiusX
        let centerY = y + radiusY
        let left = CGPoint(x: x, y: centerY)
        let right = CGPoint(x: x + width, y: centerY)
        let bottom = CGPoint(x: centerX, y: y + height)

        if leftToRight {
            path.addCurve(
                to: bottom,
                control1: CGPoint(x: left.x, y: centerY + kappa * radiusY),
                control2: CGPoint(x: centerX - kappa * radiusX, y: bottom.y)
            )
            path.addCurve(
                to: right,
                control1: CGPoint(x: centerX + kappa * radiusX, y: bottom.y),
                control2: CGPoint(x: right.x, y: centerY + kappa * radiusY)
            )
        } else {
            path.addCurve(
                to: bottom,
                control1: CGPoint(x: right.x, y: centerY + kappa * radiusY),
                control2: CGPoint(x: centerX + kappa * radiusX, y: bottom.y)
            )
            path.addCurve(
                to: left,
                control1: CGPoint(x: centerX - kappa * radiusX, y: bottom.y),
                control2: CGPoint(x: left.x, y: centerY + kappa * radiusY)
            )
        }
    }
}

private struct PortfolioInsightLegendView: View {
    let segments: [PortfolioInsightSegment]
    let totalValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(segments) { segment in
                HStack(spacing: 8) {
                    Text(segment.title)
                        .font(titleFont)
                        .foregroundStyle(Color(UIColor(hex: segment.colorHex)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(valueText(for: segment))
                        .font(valueFont)
                        .foregroundStyle(Color.air.secondaryLabel)
                        .lineLimit(1)
                }
                .frame(height: rowHeight)
            }
        }
    }

    private var rowHeight: CGFloat {
        segments.count > 4 ? 17 : 20
    }

    private var rowSpacing: CGFloat {
        segments.count > 4 ? 3 : 8
    }

    private var titleFont: Font {
        .system(size: segments.count > 4 ? 13 : 14, weight: .semibold)
    }

    private var valueFont: Font {
        .system(size: segments.count > 4 ? 13 : 14, weight: .regular)
    }

    private func valueText(for segment: PortfolioInsightSegment) -> String {
        guard totalValue > 0 else {
            return "0%"
        }
        return portfolioInsightPercentageText(segment.value / totalValue)
    }
}

private func portfolioInsightPercentageText(_ value: Double) -> String {
    formatPercent(value, decimals: 0, showPlus: false, showMinus: false)
}
