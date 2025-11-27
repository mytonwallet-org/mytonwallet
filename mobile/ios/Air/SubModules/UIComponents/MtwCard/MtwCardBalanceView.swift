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

public struct MtwCardBalanceView: View {
    
    public struct Style {
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
            integerFont: .rounded(ofSize: 19, weight: .bold),
            fractionFont: .rounded(ofSize: 13, weight: .bold),
            symbolFont: .rounded(ofSize: 16, weight: .bold),
            integerColor: nil,
            fractionColor: nil,
            symbolColor: nil,
            showChevron: false,
            sensitiveDataCellSize: 6,
            sensitiveDataTheme: .adaptive,
        )
        public static let homeCard = Style(
            integerFont: .rounded(ofSize: 56, weight: .bold),
            fractionFont: .rounded(ofSize: 40, weight: .bold),
            symbolFont: .rounded(ofSize: 48, weight: .bold),
            integerColor: nil,
            fractionColor: nil,
            symbolColor: nil,
            showChevron: true,
            sensitiveDataCellSize: 16,
            sensitiveDataTheme: .light,
        )
        public static let homeCollaped = Style(
            integerFont: .rounded(ofSize: 40, weight: .bold),
            fractionFont: .rounded(ofSize: 33, weight: .bold),
            symbolFont: .rounded(ofSize: 35, weight: .bold),
            integerColor: WTheme.primaryLabel,
            fractionColor: WTheme.secondaryLabel,
            symbolColor: WTheme.secondaryLabel,
            showChevron: false,
            sensitiveDataCellSize: 14,
            sensitiveDataTheme: .adaptive,
        )
        public static let customizeWalletCard = Style(
            integerFont: .rounded(ofSize: 40, weight: .bold),
            fractionFont: .rounded(ofSize: 33, weight: .bold),
            symbolFont: .rounded(ofSize: 35, weight: .bold),
            integerColor: nil,
            fractionColor: nil,
            symbolColor: nil,
            showChevron: false,
            sensitiveDataCellSize: 18,
            sensitiveDataTheme: .light,
        )
    }
    
    var balance: BaseCurrencyAmount?
    var isNumericTranstionEnabled: Bool
    var style: Style
    
    public init(balance: BaseCurrencyAmount?, isNumericTranstionEnabled: Bool = true, style: Style) {
        self.balance = balance
        self.isNumericTranstionEnabled = isNumericTranstionEnabled
        self.style = style
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
                        fractionColor: style.fractionColor ?? UIColor.label.withAlphaComponent(0.75),
                        symbolColor: style.symbolColor ?? UIColor.label.withAlphaComponent(0.75),
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
        }
    }
}

