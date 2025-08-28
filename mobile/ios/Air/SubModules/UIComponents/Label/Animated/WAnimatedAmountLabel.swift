//
//  WAnimatedAmountLabel.swift
//  UIComponents
//
//  Created by Sina on 7/2/24.
//

import UIKit
import WalletCore
import WalletContext

public struct WAnimatedAmountLabelConfig {
    public var primaryFont: UIFont
    public var secondaryFont: UIFont
    public var currencyFont: UIFont
    public var primaryTextColor: UIColor
    public var secondaryTextColor: UIColor
    public var minimumHorizontalPadding: CGFloat
    public var forceCurrencyToRight: Bool

    public static let card = WAnimatedAmountLabelConfig(
        primaryFont: .rounded(ofSize: 56, weight: .bold),
        secondaryFont: .rounded(ofSize: 40, weight: .bold),
        currencyFont: .rounded(ofSize: 48, weight: .bold),
        primaryTextColor: UIColor.white,
        secondaryTextColor: UIColor.white.withAlphaComponent(0.75),
        minimumHorizontalPadding: 80,
        forceCurrencyToRight: false,
    )
    public static let balanceHeader = WAnimatedAmountLabelConfig(
        primaryFont: .rounded(ofSize: 40, weight: .bold),
        secondaryFont: .rounded(ofSize: 33, weight: .bold),
        currencyFont: .rounded(ofSize: 35, weight: .bold),
        primaryTextColor: WTheme.primaryLabel,
        secondaryTextColor: WTheme.secondaryLabel,
        minimumHorizontalPadding: 80,
        forceCurrencyToRight: false,
    )
    public static let token = WAnimatedAmountLabelConfig(
        primaryFont: .rounded(ofSize: 40, weight: .bold),
        secondaryFont: .rounded(ofSize: 33, weight: .bold),
        currencyFont: .rounded(ofSize: 35, weight: .bold),
        primaryTextColor: WTheme.primaryLabel,
        secondaryTextColor: WTheme.secondaryLabel,
        minimumHorizontalPadding: 48,
        forceCurrencyToRight: true,
    )
    
    public static var cardToBalanceHeaderRatio: CGFloat {
        card.primaryFont.pointSize / balanceHeader.primaryFont.pointSize
    }
}

public class WAnimatedAmountLabel: UIView, WThemedView {

    public var config: WAnimatedAmountLabelConfig {
        didSet {
            updateLabelColors()
        }
    }

    private var amount: BigInt?
    private var currency: String?
    private var tokenDecimals: Int?
    private var decimalsCount: Int?
    
    public init(config: WAnimatedAmountLabelConfig) {
        self.config = config
        super.init(frame: CGRect.zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public var alignment: NSTextAlignment = .center

    private let label1 = {
        let lbl = WAnimatedLabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    public let label2 = {
        let lbl = WAnimatedLabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private var label1xConstraint: NSLayoutConstraint!
    private var label2xConstraint: NSLayoutConstraint!
    
    private func setupViews() {
        addSubview(label1)
        addSubview(label2)
        label1xConstraint = label1.leftAnchor.constraint(equalTo: leftAnchor)
        label2xConstraint = label2.leftAnchor.constraint(equalTo: label1.leftAnchor, constant: 0)
        NSLayoutConstraint.activate([
            label1xConstraint,
            label2xConstraint,
            label1.topAnchor.constraint(equalTo: topAnchor),
            label1.bottomAnchor.constraint(equalTo: bottomAnchor),
            label2.firstBaselineAnchor.constraint(equalTo: label1.firstBaselineAnchor)
        ])
        updateTheme()
    }

    public func updateTheme() {
        backgroundColor = .clear
        updateLabelColors()
    }

    var fadeDecimals = false
    
    private func updateLabelColors() {
        set(amount: amount,
            currency: currency,
            tokenDecimals: tokenDecimals,
            decimalsCount: decimalsCount,
            animated: false,
            force: true)
    }

    private var prevAmount: BigInt? = nil
    private var prevFormattedString: NSAttributedString? = nil
    public func set(amount: BigInt?, currency: MBaseCurrency? = nil, forceCurrencyToRight: Bool, animated: Bool) {
        set(amount: amount,
            currency: currency?.sign,
            tokenDecimals: currency?.decimalsCount,
            decimalsCount: currency?.decimalsCount,
            animated: animated)
    }
    
    public func set(amount: BigInt?,
                    currency: String?,
                    tokenDecimals: Int?,
                    decimalsCount: Int?,
                    animated: Bool = true,
                    isIncreasing: Bool = true,
                    force: Bool = false) {
        self.amount = amount
        self.currency = currency
        self.tokenDecimals = tokenDecimals
        self.decimalsCount = decimalsCount
        // check if amount is nil
        guard let amount else {
            prevFormattedString = nil
            prevAmount = nil
            label1.attributedText = nil
            label2.attributedText = nil
            return
        }
        label1.morphFromTop = isIncreasing
        label2.morphFromTop = isIncreasing

        fadeDecimals = integerPart(amount, tokenDecimals: tokenDecimals ?? 9) >= 10
        
        let amt = DecimalAmount(
            amount,
            decimals: tokenDecimals ?? 9,
            symbol: currency,
            forceCurrencyToRight: config.forceCurrencyToRight
        )
        let formattedString = amt.formatAttributed(
            format: .init(
                maxDecimals: decimalsCount,
                showPlus: false,
                showMinus: false,
                roundUp: false,
                precision: .exact
            ),
            integerFont: config.primaryFont,
            fractionFont: config.secondaryFont,
            symbolFont: config.currencyFont,
            integerColor: config.primaryTextColor,
            fractionColor: config.secondaryTextColor,
            symbolColor: config.secondaryTextColor
        )
        if prevFormattedString?.string == formattedString.string && !force {
            // nothing changed
            return
        }
        prevAmount = amount
        prevFormattedString = formattedString

        let labelsAreTheSame = config.primaryFont == config.secondaryFont
        if labelsAreTheSame {
            _set(text: formattedString, secondText: nil, animated: animated)
        } else {
            let dotRange = (formattedString.string as NSString).range(of: ".")
            if dotRange.location == NSNotFound {
                _set(text: formattedString, secondText: nil, animated: animated)
            } else {
                let text1 = formattedString.attributedSubstring(from: NSRange(location: 0, length: dotRange.location))
                let text2 = formattedString.attributedSubstring(from: NSRange(location: dotRange.location, length: formattedString.length - dotRange.location))
                _set(text: text1, secondText: text2, animated: animated)
            }
            
        }
    }

    private func _set(text: NSAttributedString?, secondText: NSAttributedString? = nil, animated: Bool = true) {
        if !animated {
            label1.morphingEnabled = false
            label2.morphingEnabled = false
            label1.onWidthChange = nil
        } else {
            label1.morphingEnabled = true
            label2.morphingEnabled = true
            label1.morphingDuration = 1
            label2.morphingDuration = 1
            label1.firstDelayInMs = label2.nextLabelDelay
            label2.additionalCharacterCountForTiming = max(label1.attributedText?.length ?? 0, label1.prevAttributedText?.length ?? 0)
            label1.onWidthChange = { [weak self] in
                guard let self else { return }
                let progress: CGFloat
                progress = label1.elapsedTime / label2.nextLabelDelay
                // Use custom easing function since UIView.easeInOut doesn't exist
                let t = min(1, progress)
                let animatedProgress = t * t * (3.0 - 2.0 * t)
                label2xConstraint.constant = label1.totalWidth * animatedProgress + label1.prevWidth * (1 - animatedProgress)
                if alignment == .center {
                    let prevTotalWidth = label1.prevWidth + label2.prevWidth
                    let newTotalWidth = label1.totalWidth + label2.totalWidth
                    label1xConstraint.constant = (newTotalWidth - prevTotalWidth) / 2 * (1 - animatedProgress)
                } else {
                    label1xConstraint.constant = 0
                }
            }
        }
        if label1.attributedText?.string != text?.string {
            label1.attributedText = text
            label2.forceMorphLeftCharacters = true
        } else {
            label2.forceMorphLeftCharacters = false
        }
        label2.attributedText = secondText
        
        if !animated {
            label1xConstraint.constant = 0
            label2xConstraint.constant = label1.totalWidth
        }
    }

    public var totalWidth: CGFloat {
        let label1Width = CGFloat(label1.totalWidth)
        let label2Width = CGFloat(label2.totalWidth)
        return label1Width + label2Width
    }
}


#if DEBUG
@available(iOS 18, *)
#Preview {
    let _ = UIFont.registerAirFonts()
    let view = {
        let view = BalanceView(config: .balanceHeader)
        view.set(balanceInBaseCurrency: 223.92, baseCurrency: .USD, animated: true)
        return view
    }()
    view
}
#endif
