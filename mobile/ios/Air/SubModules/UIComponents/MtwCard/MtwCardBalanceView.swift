//
//  BalanceView.swift
//  MyTonWalletAir
//
//  Created by nikstar on 18.11.2025.
//

import UIKit
import SwiftUI
import WalletContext
import WalletCore
import Dependencies

public let fontScalingFactor = max(1, UIScreen.main.bounds.width / 402.0)
public let homeCardFontSize: CGFloat = 56 * fontScalingFactor
public let homeCollapsedFontSize: CGFloat = 40

public struct MtwCardBalanceView: View, Equatable {
    
    public struct Style: Equatable, Identifiable {
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

        public static let grid = Style(
            id: "grid",
            integerFont: .rounded(ofSize: 19 * fontScalingFactor, weight: .bold),
            fractionFont: .rounded(ofSize: 13 * fontScalingFactor, weight: .bold),
            symbolFont: .rounded(ofSize: 16 * fontScalingFactor, weight: .bold),
            integerColor: nil,
            fractionColor: nil,
            symbolColor: nil,
            showChevron: false,
            sensitiveDataCellSize: 6,
            sensitiveDataTheme: .adaptive,
        )
        public static let homeCard = Style(
            id: "homeCard",
            integerFont: .rounded(ofSize: homeCardFontSize, weight: .bold),
            fractionFont: .rounded(ofSize: 40 * fontScalingFactor, weight: .bold),
            symbolFont: .rounded(ofSize: 48 * fontScalingFactor, weight: .bold),
            integerColor: nil,
            fractionColor: nil,
            symbolColor: nil,
            showChevron: true,
            sensitiveDataCellSize: 16,
            sensitiveDataTheme: .light,
        )
        public static let homeCollaped = Style(
            id: "homeCollaped",
            integerFont: .rounded(ofSize: homeCollapsedFontSize, weight: .bold),
            fractionFont: .rounded(ofSize: 28.5, weight: .bold),
            symbolFont: .rounded(ofSize: 34, weight: .bold),
            integerColor: WTheme.primaryLabel,
            fractionColor: WTheme.secondaryLabel,
            symbolColor: WTheme.secondaryLabel,
            showChevron: false,
            sensitiveDataCellSize: 14,
            sensitiveDataTheme: .adaptive,
        )
        public static let customizeWalletCard = Style(
            id: "customizeWalletCard",
            integerFont: .rounded(ofSize: 46, weight: .bold),
            fractionFont: .rounded(ofSize: 32, weight: .bold),
            symbolFont: .rounded(ofSize: 38, weight: .bold),
            integerColor: nil,
            fractionColor: nil,
            symbolColor: nil,
            showChevron: false,
            sensitiveDataCellSize: 18,
            sensitiveDataTheme: .light,
        )
        
        public static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    var balance: BaseCurrencyAmount?
    var isNumericTranstionEnabled: Bool
    var style: Style
    var secondaryOpacity: CGFloat
    
    public init(balance: BaseCurrencyAmount?, isNumericTranstionEnabled: Bool = true, style: Style, secondaryOpacity: CGFloat = 1) {
        self.balance = balance
        self.isNumericTranstionEnabled = isNumericTranstionEnabled
        self.style = style
        self.secondaryOpacity = secondaryOpacity
    }
    
    public var body: some View {
        if let balance {
            HStack(spacing: 6) {
                Text(
                    balance.formatAttributed(
                        format: .init(roundUp: true),
                        integerFont: style.integerFont,
                        fractionFont: style.fractionFont,
                        symbolFont: style.symbolFont,
                        integerColor: style.integerColor ?? UIColor.label,
                        fractionColor: (style.fractionColor ?? UIColor.label).withAlphaComponent(secondaryOpacity),
                        symbolColor: (style.symbolColor ?? UIColor.label).withAlphaComponent(secondaryOpacity),
                    )
                )
                .contentTransition(isNumericTranstionEnabled ? .numericText() : .identity)
                .lineLimit(1)
             
                if style.showChevron {
                    Image.airBundle("ChevronDown18")
                        .offset(y: 8)
                        .opacity(0.75)
                }
            }
            .backportGeometryGroup()
            .minimumScaleFactor(0.1)
            .sensitiveData(alignment: .center, cols: 14, rows: 3, cellSize: style.sensitiveDataCellSize, theme: style.sensitiveDataTheme, cornerRadius: 12)
            .animation(.default, value: balance)
        } else {
            Color.clear.frame(height: 60)
        }
    }
}

