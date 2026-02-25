import UIKit
import SwiftUI
import WalletContext
import WalletCore
import Dependencies

private let baseHomeCardWidth = designScreenWidth - 2 * compactInsetSectionHorizontalPadding

public func homeCardFontScalingFactor(cardWidth: CGFloat) -> CGFloat {
    homeCardFontScalingFactor(cardWidth: cardWidth, minimumScale: 1)
}

public func homeCardFontScalingFactor(cardWidth: CGFloat, minimumScale: CGFloat) -> CGFloat {
    guard baseHomeCardWidth > 0 else { return 1 }
    return max(minimumScale, cardWidth / baseHomeCardWidth)
}

public func homeCardFontSize(for cardWidth: CGFloat) -> CGFloat {
    homeCardFontSize(for: cardWidth, minimumScale: 1)
}

public func homeCardFontSize(for cardWidth: CGFloat, minimumScale: CGFloat) -> CGFloat {
    56 * homeCardFontScalingFactor(cardWidth: cardWidth, minimumScale: minimumScale)
}

public let fontScalingFactor = homeCardFontScalingFactor(cardWidth: homeCardWidth)
public let homeCardFontSize: CGFloat = homeCardFontSize(for: homeCardWidth)
public let homeCollapsedFontSize: CGFloat = 40

// MARK: - MtwCardBalanceView

public struct MtwCardBalanceView: View, Equatable {
    // MARK: Lifecycle

    public init(
        balance: BaseCurrencyAmount?,
        isNumericTranstionEnabled: Bool = true,
        style: Style,
        secondaryOpacity: CGFloat = 1
    ) {
        self.balance = balance
        self.isNumericTranstionEnabled = isNumericTranstionEnabled
        self.style = style
        self.secondaryOpacity = secondaryOpacity
    }

    // MARK: Public

    public struct Style: Equatable, Identifiable {
        public static let grid = Style(
            id: "grid",
            integerFont: .compactRounded(ofSize: 19 * fontScalingFactor, weight: .bold),
            fractionFont: .compactRounded(ofSize: 13 * fontScalingFactor, weight: .bold),
            symbolFont: .compactRounded(ofSize: 16 * fontScalingFactor, weight: .bold),
            integerColor: nil,
            fractionColor: nil,
            symbolColor: nil,
            showChevron: false,
            sensitiveDataCellSize: 6,
            sensitiveDataTheme: .adaptive,
        )

        public static let homeCard = Style(
            id: "homeCard",
            integerFont: .compactRounded(ofSize: homeCardFontSize, weight: .bold),
            fractionFont: .compactRounded(ofSize: 40 * fontScalingFactor, weight: .bold),
            symbolFont: .compactRounded(ofSize: 48 * fontScalingFactor, weight: .bold),
            integerColor: nil,
            fractionColor: nil,
            symbolColor: nil,
            showChevron: true,
            sensitiveDataCellSize: 16,
            sensitiveDataTheme: .light,
        )
        
        public static func homeCard(cardWidth: CGFloat, minimumScale: CGFloat = 1) -> Style {
            let scale = homeCardFontScalingFactor(cardWidth: cardWidth, minimumScale: minimumScale)
            let minimumScaleId = Int((minimumScale * 1000).rounded())
            return Style(
                id: "homeCard_\(Int(cardWidth.rounded()))_\(minimumScaleId)",
                integerFont: .compactRounded(ofSize: homeCardFontSize(for: cardWidth, minimumScale: minimumScale), weight: .bold),
                fractionFont: .compactRounded(ofSize: 40 * scale, weight: .bold),
                symbolFont: .compactRounded(ofSize: 48 * scale, weight: .bold),
                integerColor: nil,
                fractionColor: nil,
                symbolColor: nil,
                showChevron: true,
                sensitiveDataCellSize: 16,
                sensitiveDataTheme: .light,
            )
        }

        public static let homeCollaped = Style(
            id: "homeCollaped",
            integerFont: .compactRounded(ofSize: homeCollapsedFontSize, weight: .bold),
            fractionFont: .compactRounded(ofSize: 28.5, weight: .bold),
            symbolFont: .compactRounded(ofSize: 34, weight: .bold),
            integerColor: WTheme.primaryLabel,
            fractionColor: WTheme.secondaryLabel,
            symbolColor: WTheme.secondaryLabel,
            showChevron: false,
            sensitiveDataCellSize: 14,
            sensitiveDataTheme: .adaptive,
        )

        public static let customizeWalletCard = Style(
            id: "customizeWalletCard",
            integerFont: .compactRounded(ofSize: 46, weight: .bold),
            fractionFont: .compactRounded(ofSize: 32, weight: .bold),
            symbolFont: .compactRounded(ofSize: 38, weight: .bold),
            integerColor: nil,
            fractionColor: nil,
            symbolColor: nil,
            showChevron: false,
            sensitiveDataCellSize: 18,
            sensitiveDataTheme: .light,
        )

        public let id: String

        public let integerFont: UIFont
        public let fractionFont: UIFont
        public let symbolFont: UIFont

        public let integerColor: UIColor?
        public let fractionColor: UIColor?
        public let symbolColor: UIColor?

        public let showChevron: Bool

        public let sensitiveDataCellSize: CGFloat
        public let sensitiveDataTheme: ShyMask.Theme

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }
    }

    public var body: some View {
        ZStack {
            if let balance {
                mainView(balance)
                    .animation(.default, value: balance)
            } else {
                placeholderView()
                    .animation(.smooth(duration: 0.21), value: isPlaceholder)
            }
        }
        .backportGeometryGroup()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isPlaceholder == rhs.isPlaceholder &&
            lhs.balance == rhs.balance &&
            lhs.isNumericTranstionEnabled == rhs.isNumericTranstionEnabled &&
            lhs.style == rhs.style &&
            lhs.secondaryOpacity == rhs.secondaryOpacity
    }

    // MARK: Internal

    var balance: BaseCurrencyAmount?
    var isNumericTranstionEnabled: Bool
    var style: Style
    var secondaryOpacity: CGFloat

    // MARK: Private

    private var isPlaceholder: Bool { balance == nil }

    private func mainView(_ balance: BaseCurrencyAmount) -> some View {
        HStack(spacing: 6) {
            Text(
                balance.formatAttributed(
                    format: .init(preset: .baseCurrencyEquivalent, roundUp: true),
                    integerFont: style.integerFont,
                    fractionFont: style.fractionFont,
                    symbolFont: style.symbolFont,
                    integerColor: style.integerColor ?? UIColor.label,
                    fractionColor: (style.fractionColor ?? UIColor.label)
                        .withAlphaComponent(secondaryOpacity),
                    symbolColor: (style.symbolColor ?? UIColor.label)
                        .withAlphaComponent(secondaryOpacity),
                )
            )
            .contentTransition(isNumericTranstionEnabled ? .numericText() : .identity)
            .lineLimit(1)

            if style.showChevron {
                Image.airBundle("ArrowUpDown")
                    .opacity(secondaryOpacity == 1 ? 0.75 : 0.5)
                    .offset(y: -1)
                    .padding(.vertical, -8)
            }
        }
        .backportGeometryGroup()
        .minimumScaleFactor(0.1)
        .sensitiveData(
            alignment: .center,
            cols: 14,
            rows: 3,
            cellSize: style.sensitiveDataCellSize,
            theme: style.sensitiveDataTheme,
            cornerRadius: 12
        )
    }

    private func placeholderView() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.white.opacity(0.12))
            .frame(idealWidth: 120, maxWidth: 120, minHeight: 60, maxHeight: 60)
    }
}

// MARK: - MtwCardBalanceView_Previews

struct MtwCardBalanceView_Previews: PreviewProvider {
    // MARK: Internal

    static var previews: some View {
        withRegisteredCustomFontsForPreviewsIfNeeded {
            Group {
                MtwCardBalanceViewPreview(balances: [
                    nil,
                    .init(120000000000, .USD),
                    .init(32000, .EUR),
                    .init(0, .USD),
                ])
                .previewDisplayName("MtwCardBalanceView")
            }
            .previewLayout(.device)
        }
    }

    // MARK: Private

    private struct MtwCardBalanceViewPreview: View {
        // MARK: Public

        public var body: some View {
            ZStack {
                MtwCardBalanceView(
                    balance: balances[index],
                    isNumericTranstionEnabled: true,
                    style: .homeCard,
                    secondaryOpacity: 0.75
                )
            }
            .backportGeometryGroup()
            .frame(width: 340, height: 214)
            .background(RoundedRectangle(cornerRadius: 20).fill(.blue))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .onTapGesture {
                index = (index + 1) % balances.count
            }
        }

        // MARK: Internal

        var balances: [BaseCurrencyAmount?]

        // MARK: Private

        @State
        private var index: Int = 0
    }
}
