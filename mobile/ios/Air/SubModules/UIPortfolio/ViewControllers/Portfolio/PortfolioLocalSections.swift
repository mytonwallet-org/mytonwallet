import Perception
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

enum PortfolioInsightLegendDisplayMode: Equatable {
    case amounts
    case percentages

    var next: Self {
        switch self {
        case .amounts:
            return .percentages
        case .percentages:
            return .amounts
        }
    }
}

enum PortfolioInsightCardChrome: Equatable {
    case plain
    case plainSecondaryBorder
    case smart
}

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
    struct Action: Equatable {
        enum Kind: Equatable {
            case fund
            case swap
            case earn
        }

        let kind: Kind
        let title: String
    }

    let id: PortfolioInsightCardID
    let title: String
    let segments: [PortfolioInsightSegment]
    let emptyText: String?
    let action: Action?
    let chrome: PortfolioInsightCardChrome
}

struct PortfolioBalanceSummaryView: View {
    let accountContext: AccountContext

    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 16) {
                PortfolioCardMiniatureView(accountContext: accountContext)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lang("Total Balance"))
                        .font(.compactDisplay(size: 13, weight: .medium))
                        .foregroundStyle(Color.air.secondaryLabel)

                    MtwCardBalanceView(
                        balance: accountContext.balance,
                        isNumericTranstionEnabled: accountContext.isCurrent,
                        style: .homeCollaped
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }
    }
}

struct PortfolioInsightCardView: View {
    let card: PortfolioInsightCardModel
    let legendDisplayMode: PortfolioInsightLegendDisplayMode
    let onTap: @MainActor @Sendable () -> Void
    let onAction: @MainActor @Sendable () -> Void
    @State private var isPressed = false

    private var isInteractive: Bool {
        !card.segments.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
                Text(card.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.air.primaryLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                PortfolioInsightBarView(
                    segments: card.segments,
                    emptyText: card.emptyText
                )

                PortfolioInsightLegendView(
                    segments: card.segments,
                    emptyText: card.emptyText,
                    displayMode: legendDisplayMode,
                    maxRows: 3
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 190, alignment: .topLeading)
            .background {
                PortfolioInsightCardBackground(chrome: card.chrome)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .highlightScale(isPressed, scale: 0.98, isEnabled: isInteractive)
            .if(isInteractive) {
                $0.onTap(isPressedBinding: $isPressed, action: onTap)
            }

            if let action = card.action {
                PortfolioInsightActionButton(
                    title: action.title,
                    onTap: onAction
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 230, maxHeight: 230, alignment: .topLeading)
    }
}

private struct PortfolioCardMiniatureView: View {
    let accountContext: AccountContext

    private let size = CGSize(width: 108, height: 68)

    var body: some View {
        WithPerceptionTracking {
            MtwCardBackground(nft: accountContext.nft, borderWidthMultiplier: 0.8)
                .overlay(alignment: .bottom) {
                    MtwCardMiniPlaceholders()
                        .sourceAtop {
                            MtwCardInverseCenteredGradient(nft: accountContext.nft)
                        }
                        .padding(.bottom, 15)
                        .scaleEffect(size.width / 34)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(.containerRelative)
                .containerShape(.rect(cornerRadius: 16))
        }
    }
}

private struct PortfolioInsightBarView: View {
    let segments: [PortfolioInsightSegment]
    let emptyText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let visibleSegments = segments.filter { $0.value > 0 }
                let totalValue = visibleSegments.reduce(0) { $0 + $1.value }
                let spacing = CGFloat(max(visibleSegments.count - 1, 0)) * 3
                let availableWidth = max(geometry.size.width - spacing, 0)

                if !visibleSegments.isEmpty && totalValue > 0 {
                    HStack(spacing: 3) {
                        ForEach(visibleSegments) { segment in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(UIColor(hex: segment.colorHex)))
                                .frame(width: availableWidth * (segment.value / totalValue))
                        }
                    }
                }
            }
            .frame(height: 56)

            if segments.isEmpty,
               let emptyText
            {
                Text(emptyText)
                    .font(.compactDisplay(size: 13, weight: .medium))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
            }
        }
    }
}

private struct PortfolioInsightLegendView: View {
    let segments: [PortfolioInsightSegment]
    let emptyText: String?
    let displayMode: PortfolioInsightLegendDisplayMode
    let maxRows: Int

    private var displayedSegments: [PortfolioInsightSegment] {
        Array(segments.prefix(maxRows))
    }

    private var totalValue: Double {
        segments.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if displayedSegments.isEmpty {
                Text(emptyText ?? lang("No data"))
                    .font(.compactDisplay(size: 13, weight: .medium))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(displayedSegments) { segment in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(UIColor(hex: segment.colorHex)))
                            .frame(width: 8, height: 8)

                        Text(segment.title)
                            .font(.compactDisplay(size: 13, weight: .medium))
                            .foregroundStyle(Color.air.primaryLabel)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(valueText(for: segment))
                            .font(.compactDisplay(size: 13, weight: .medium))
                            .foregroundStyle(Color.air.secondaryLabel)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func valueText(for segment: PortfolioInsightSegment) -> String {
        switch displayMode {
        case .amounts:
            return segment.valueText
        case .percentages:
            guard totalValue > 0 else {
                return "0%"
            }
            return portfolioInsightPercentageText(segment.value / totalValue)
        }
    }
}

private struct PortfolioInsightActionButton: View {
    let title: String
    let onTap: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
        }
        .buttonStyle(PortfolioInsightActionButtonStyle())
    }
}

private struct PortfolioInsightActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.tint)
            .padding(.vertical, 7)
            .padding(.horizontal, 14)
            .background {
                Capsule()
                    .fill(Color(uiColor: UIColor.tintColor).opacity(configuration.isPressed ? 0.16 : 0.10))
            }
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.smooth(duration: 0.16), value: configuration.isPressed)
    }
}

private struct PortfolioInsightCardBackground: View {
    let chrome: PortfolioInsightCardChrome
    private static let cornerRadius: CGFloat = 16
    private static let borderWidth: CGFloat = 1.5

    var body: some View {
        let cardShape = RoundedRectangle(
            cornerRadius: Self.cornerRadius,
            style: .continuous
        )

        switch chrome {
        case .plain:
            cardShape
                .fill(PortfolioInsightCardBackgroundStyle.baseFill)
        case .plainSecondaryBorder:
            cardShape
                .fill(PortfolioInsightCardBackgroundStyle.baseFill)
                .overlay {
                    cardShape
                        .strokeBorder(
                            PortfolioInsightCardBackgroundStyle.secondaryBorder,
                            lineWidth: 1
                        )
                }
        case .smart:
            TimelineView(.animation) { context in
                let rotationDegrees = PortfolioInsightCardBackgroundStyle.rotationDegrees(at: context.date)

                cardShape
                    .fill(PortfolioInsightCardBackgroundStyle.baseFill)
                    .overlay {
                        cardShape
                            .fill(PortfolioInsightCardBackgroundStyle.backgroundGradient(rotatedBy: rotationDegrees))
                            .opacity(0.1)
                    }
                    .overlay {
                        cardShape
                            .strokeBorder(
                                PortfolioInsightCardBackgroundStyle.borderGradient(rotatedBy: rotationDegrees),
                                lineWidth: Self.borderWidth
                            )
                    }
            }
        }
    }
}

private enum PortfolioInsightCardBackgroundStyle {
    private static let gradientRotationDuration: TimeInterval = 12
    private static let backgroundBaseAngleDegrees = 27.194
    private static let backgroundEndpointRadius = 1.1

    static let baseFill = Color(
        uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                UIColor(
                    red: 35.0 / 255.0,
                    green: 39.0 / 255.0,
                    blue: 50.0 / 255.0,
                    alpha: 0.56
                )
            } else {
                UIColor(
                    red: 233.0 / 255.0,
                    green: 233.0 / 255.0,
                    blue: 234.0 / 255.0,
                    alpha: 0.16
                )
            }
        }
    )

    static let secondaryBorder = Color.air.secondaryLabel.opacity(0.2)

    static let backgroundGradientStops = Gradient(stops: [
        .init(color: Color(.sRGB, red: 0, green: 136.0 / 255.0, blue: 1, opacity: 0.5), location: 0),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.5), location: 0.13),
        .init(color: Color(.sRGB, red: 182.0 / 255.0, green: 86.0 / 255.0, blue: 1, opacity: 0.2), location: 0.25),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.2), location: 0.375),
        .init(color: Color(.sRGB, red: 0, green: 136.0 / 255.0, blue: 1, opacity: 0.2), location: 0.5),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.5), location: 0.63),
        .init(color: Color(.sRGB, red: 182.0 / 255.0, green: 86.0 / 255.0, blue: 1, opacity: 0.2), location: 0.75),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.5), location: 0.88),
    ])

    static let borderGradientStops = Gradient(stops: [
        .init(color: Color(.sRGB, red: 0, green: 136.0 / 255.0, blue: 1, opacity: 1), location: 0),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.5), location: 0.13),
        .init(color: Color(.sRGB, red: 182.0 / 255.0, green: 86.0 / 255.0, blue: 1, opacity: 0.1), location: 0.25),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.1), location: 0.375),
        .init(color: Color(.sRGB, red: 0, green: 136.0 / 255.0, blue: 1, opacity: 0.1), location: 0.5),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 0.5), location: 0.63),
        .init(color: Color(.sRGB, red: 182.0 / 255.0, green: 86.0 / 255.0, blue: 1, opacity: 1), location: 0.75),
        .init(color: Color(.sRGB, red: 0, green: 190.0 / 255.0, blue: 1, opacity: 1), location: 0.88),
        .init(color: Color(.sRGB, red: 0, green: 136.0 / 255.0, blue: 1, opacity: 1), location: 1),
    ])

    static func rotationDegrees(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: gradientRotationDuration)
        return elapsed / gradientRotationDuration * 360
    }

    static func backgroundGradient(rotatedBy degrees: Double) -> LinearGradient {
        let radians = (degrees + backgroundBaseAngleDegrees) * .pi / 180
        let dx = cos(radians) * backgroundEndpointRadius
        let dy = sin(radians) * backgroundEndpointRadius

        return LinearGradient(
            gradient: backgroundGradientStops,
            startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
            endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
        )
    }

    static func borderGradient(rotatedBy degrees: Double) -> AngularGradient {
        AngularGradient(
            gradient: borderGradientStops,
            center: .center,
            startAngle: .degrees(degrees),
            endAngle: .degrees(degrees + 360)
        )
    }
}

private func portfolioInsightPercentageText(_ value: Double) -> String {
    let percentage = value * 100
    let formatter = NumberFormatter()
    formatter.locale = Locale.current
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 1
    return "\(formatter.string(from: NSNumber(value: percentage)) ?? "0")%"
}
