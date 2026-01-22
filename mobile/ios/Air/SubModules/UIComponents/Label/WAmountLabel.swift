//
//  WAmountLabel.swift
//  UIComponents
//
//  Created by Sina on 4/20/23.
//

import UIKit
import WalletContext

public class WAmountLabel: UILabel {
    
    private static let defaultNumberFont = UIFont.systemFont(ofSize: 16, weight: .regular)
    private static let defaultDecimalsFont = UIFont.systemFont(ofSize: 15, weight: .regular)
    private let primaryColor: UIColor
    
    private var amount: BigInt = 0
    private var currency: String = ""
    private var tokenDecimals: Int? = nil
    private var decimalsCount: Int? = nil
    private var showNegativeSign: Bool = false

    private let numberFont: UIFont
    private let decimalsFont: UIFont
    public init(numberFont: UIFont? = nil,
                decimalsFont: UIFont? = nil,
                primaryColor: UIColor = WTheme.primaryLabel,
                showNegativeSign: Bool = false) {
        self.numberFont = numberFont ?? WAmountLabel.defaultNumberFont
        self.decimalsFont = decimalsFont ?? WAmountLabel.defaultDecimalsFont
        self.primaryColor = primaryColor
        self.showNegativeSign = showNegativeSign
        super.init(frame: CGRect.zero)
        updateTheme()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func awakeFromNib() {
        super.awakeFromNib()
        setup()
    }
    
    public override func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
        setup()
    }
    
    private func setup() {
        // set theme colors
        updateTheme()
    }
    
    public func set(amount: BigInt, currency: String = "", tokenDecimals: Int?, decimalsCount: Int?, forcePositiveColor: UIColor? = nil) {
        self.amount = amount
        self.currency = currency
        if let tokenDecimals {
            self.tokenDecimals = tokenDecimals
        }
        if let decimalsCount {
            self.decimalsCount = decimalsCount
        }
        updateTheme(forcePositiveColor: forcePositiveColor)
    }
    public func set(doubleAmount: Double,
                    tokenDecimals: Int?,
                    decimalsCount: Int?,
                    currency: String = "",
                    hidePositiveSign: Bool = false,
                    forcePositiveColor: UIColor? = nil) {
        guard let tokenDecimals else {
            self.amount = 0
            self.currency = currency
            self.tokenDecimals = nil
            self.decimalsCount = decimalsCount
            attributedText = nil
            return
        }
        self.amount = doubleToBigInt(doubleAmount, decimals: tokenDecimals)
        self.currency = currency
        self.tokenDecimals = tokenDecimals
        if let decimalsCount {
            self.decimalsCount = decimalsCount
        }
        updateTheme(hidePositiveSign: hidePositiveSign, forcePositiveColor: forcePositiveColor)
    }

    func updateTheme(hidePositiveSign: Bool = false, forcePositiveColor: UIColor? = nil) {
        guard let tokenDecimals else {
            attributedText = nil
            return
        }
        // reset text color
        let components = formatBigIntText(amount,
                                         negativeSign: showNegativeSign,
                                         tokenDecimals: tokenDecimals,
                                         decimalsCount: decimalsCount)
            .components(separatedBy: ".")
        let attr = NSMutableAttributedString(string: "\(amount > 0 && !hidePositiveSign ? "+\(signSpace)" : "")\(components[0])", attributes: [
            NSAttributedString.Key.font: numberFont,
            NSAttributedString.Key.foregroundColor: amount > 0 ? (forcePositiveColor ?? WTheme.positiveAmount) : primaryColor
        ])
        if components.count > 1 {
            attr.append(NSAttributedString(string: ".\(components[1])", attributes: [
                NSAttributedString.Key.font: decimalsFont,
                NSAttributedString.Key.foregroundColor: amount > 0 ? (forcePositiveColor ?? WTheme.positiveAmount) : primaryColor
            ]))
        }
        if !currency.isEmpty {
            attr.append(NSAttributedString(string: " \(currency)", attributes: [
                NSAttributedString.Key.font: decimalsFont,
                NSAttributedString.Key.foregroundColor: amount > 0 ? (forcePositiveColor ?? WTheme.positiveAmount) : primaryColor
            ]))
        }
        attributedText = attr
    }
}
