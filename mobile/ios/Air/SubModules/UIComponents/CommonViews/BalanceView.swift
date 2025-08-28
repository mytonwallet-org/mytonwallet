//
//  BalanceView.swift
//  UIWalletHome
//
//  Created by Sina on 4/21/23.
//

import UIKit
import WalletCore
import WalletContext

// used to represent the total balance of the wallet
public class BalanceView: UIView, WThemedView {

    private var balanceLabel: WAnimatedAmountLabel!
    private var heightConstraint: NSLayoutConstraint!
    private var widthConstraint: NSLayoutConstraint!
    private(set) public var scale: CGFloat = 1

    private var balance: BigInt? = nil
    private var isLoading: Bool = false
    
    // Loading gradient
    private let loadingGradientLayer = CAGradientLayer()
    private let gradientBaseColor: CGColor = UIColor(white: 1.0, alpha: 0.3).cgColor
    private let gradientAccentColor: CGColor = UIColor(white: 1.0, alpha: 0.7).cgColor
    
    // Gradient layer for gradient coloring
    private let gradientLayer = CAGradientLayer()
    
    public var alignment: NSTextAlignment = .center {
        didSet {
            balanceLabel.alignment = alignment
        }
    }
    
    private var config: WAnimatedAmountLabelConfig = .card

    public convenience init(config: WAnimatedAmountLabelConfig) {
        self.init()
        self.config = config
        setupView()
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: 0)
        heightConstraint = heightAnchor.constraint(equalToConstant: 56)
        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint
        ])

        balanceLabel = WAnimatedAmountLabel(config: config)
        balanceLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(balanceLabel)
        NSLayoutConstraint.activate([
            balanceLabel.leftAnchor.constraint(equalTo: leftAnchor),
            balanceLabel.rightAnchor.constraint(equalTo: rightAnchor),
            balanceLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        balanceLabel.isUserInteractionEnabled = false
        
        setupLoadingGradient()
        setupGradientLayer()
        
        // Disable implicit animations to prevent unwanted layer resize transitions
        loadingGradientLayer.actions = noAnim
        gradientLayer.actions = noAnim

        updateTheme()

        update(scale: 1, force: true)
    }
    
    public func updateTheme() {
//        balanceLabel.setTextColor(primary: textColor, secondary: secondTextColor, charColor: secondTextColor)
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        loadingGradientLayer.frame = bounds.insetBy(dx: -8, dy: -8)
        gradientLayer.frame = bounds.insetBy(dx: -8, dy: -8)
    }
    
    public override var forLastBaselineLayout: UIView {
        balanceLabel.label2
    }
    
    // MARK: - Update methdos

    public func set(balance: BigInt?, currency: String?, tokenDecimals: Int, decimalsCount: Int, animated: Bool?) {
        balanceLabel.set(amount: balance,
                         currency: currency,
                         tokenDecimals: tokenDecimals,
                         decimalsCount: decimalsCount,
                         animated: animated ?? (self.balance != nil),
                         isIncreasing: self.balance == nil || self.balance! < (balance ?? 0))
        self.balance = balance
        updateBalanceLabelFont()
        superview?.layoutIfNeeded()
    }
    
    public func set(balanceInBaseCurrency: Double?, baseCurrency: MBaseCurrency?, animated: Bool?) {
        let balance = balanceInBaseCurrency != nil ? doubleToBigInt(balanceInBaseCurrency!,
                                                                   decimals: baseCurrency?.decimalsCount ?? 9) : nil
        self.set(balance: balance,
            currency: baseCurrency?.sign,
            tokenDecimals: baseCurrency?.decimalsCount ?? 9,
            decimalsCount: baseCurrency?.decimalsCount ?? 9,
            animated: animated)
    }
    
    public func setLoading(_ isLoading: Bool) {
        self.isLoading = isLoading
        if isLoading {
            animateLoadingGradient()
        } else {
            stopLoadingAnimation()
        }
    }

    /// Update scale of the balance view.
    ///
    /// - Parameters:
    ///     - scale: A number between 0 (collapsed) and 1 (expanded).
    public func update(scale: CGFloat, force: Bool = false) {
        if self.scale == scale && force == false {
            return
        }
        self.scale = scale
        heightConstraint.constant = 22 + 40 * (scale - 0.5)
        updateBalanceLabelFont()
    }
    
    private func updateBalanceLabelFont() {
        var effectiveScale = scale
        let labelWidth = balanceLabel.totalWidth
        if let containerWidth = window?.bounds.width, containerWidth > config.minimumHorizontalPadding {
            let maxLabelWidth = containerWidth - config.minimumHorizontalPadding
            if labelWidth * scale > maxLabelWidth {
                effectiveScale = maxLabelWidth / labelWidth
            }
        }
        widthConstraint.constant = max(0, labelWidth * effectiveScale)
        let dx = balanceLabel.totalWidth / 2 * effectiveScale
        balanceLabel.transform = CGAffineTransform
            .init(translationX: -dx, y: 0)
            .scaledBy(x: effectiveScale, y: effectiveScale)
            .translatedBy(x: dx, y: 0)
    }
    
    
    // MARK: - Loading gradient
    
    private func setupLoadingGradient() {
        loadingGradientLayer.colors = [gradientBaseColor, gradientAccentColor, gradientBaseColor, gradientAccentColor, gradientBaseColor,]
        loadingGradientLayer.locations = [0.0, 0.25, 0.5, 0.75, 1.0]
        loadingGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        loadingGradientLayer.endPoint = CGPoint(x: 1, y: 0.3)
        loadingGradientLayer.frame = bounds
        
//        loadingGradientLayer.borderColor = UIColor.red.cgColor
//        loadingGradientLayer.borderWidth = 2
//        layer.addSublayer(loadingGradientLayer)
    }
    
    private func animateLoadingGradient() {
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-1.0, -0.75, -0.5, -0.25, 0.0]
        animation.toValue = [1.5, 1.75, 2.0, 2.25, 2.5]
        
        animation.duration = 2.5
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        
        loadingGradientLayer.add(animation, forKey: "glareAnimation")
        
        layer.mask = loadingGradientLayer
    }
    
    private func stopLoadingAnimation() {
        loadingGradientLayer.removeAnimation(forKey: "glareAnimation")
        
        layer.mask = nil
    }
    
    // MARK: - Gradient layer
    
    private func setupGradientLayer() {
        gradientLayer.colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 1).cgColor]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradientLayer)
        gradientLayer.compositingFilter = "sourceAtop"
        gradientLayer.isHidden = true
    }
    
    public func setGradientColors(leftColor: UIColor, rightColor: UIColor, startPoint: CGFloat? = nil) {
        gradientLayer.colors = [leftColor.cgColor, rightColor.cgColor]
        gradientLayer.startPoint.x = startPoint ?? 0
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.isHidden = false
    }
    
    public func hideGradient() {
        gradientLayer.isHidden = true
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

