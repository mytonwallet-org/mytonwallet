
import Foundation
import SwiftUI
import WalletCore
import WalletContext

@MainActor
public final class BadgeView: UIView {
    public enum TokenLabelStyle {
        case regular
        case stock
    }
    
    public enum Style {
        case regular
        case large
    }

    private static let stockLabelColor = UIColor(hex: "#DE8C00")
    private let horizontalPadding: CGFloat
    private let badgeHeight: CGFloat
    private let style: Style
    
    private var label = UILabel()
    private var backgroundGradient = CAGradientLayer()
    private var labelGradient = CAGradientLayer()
    
    public init(style: Style = .regular) {
        self.style = style
        
        switch style {
        case .regular:
            horizontalPadding = 6
            badgeHeight = 14
            label.font = .systemFont(ofSize: 10, weight: .semibold)
        case .large:
            horizontalPadding = 8
            badgeHeight = 16
            label.font = .systemFont(ofSize: 13, weight: .semibold)
        }

        super.init(frame: .zero)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 4
        layer.masksToBounds = true
        
        layer.addSublayer(backgroundGradient)
        backgroundGradient.startPoint = .init(x: 0, y: 0.5)
        backgroundGradient.endPoint = .init(x: 1, y: 0.5)
        backgroundGradient.compositingFilter = "sourceAtop"

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding / 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding / 2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            self.heightAnchor.constraint(equalToConstant: badgeHeight)
        ])
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.textColor = .white
        
        label.layer.addSublayer(labelGradient)
        labelGradient.startPoint = .init(x: 0, y: 0.5)
        labelGradient.endPoint = .init(x: 1, y: 0.5)
        labelGradient.compositingFilter = "sourceAtop"
        
        // Disable implicit animations to prevent unwanted layer resize/color transitions
        var noAnim = noAnim
        noAnim["colors"] = NSNull()
        backgroundGradient.actions = noAnim
        labelGradient.actions = noAnim
    }

    public override var intrinsicContentSize: CGSize {
        guard !isHidden else { return .zero }
        var labelWidth = label.intrinsicContentSize.width
        if labelWidth == UIView.noIntrinsicMetric || labelWidth <= 0 {
            labelWidth = label.sizeThatFits(
                CGSize(width: CGFloat.greatestFiniteMagnitude, height: badgeHeight)
            ).width
        }
        guard labelWidth > 0 else { return .zero }
        return CGSize(width: ceil(labelWidth) + horizontalPadding, height: badgeHeight)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        backgroundGradient.frame = bounds
        labelGradient.frame = label.bounds
    }
    
    public func configureStakingActive(yieldType: ApiYieldType, apy: Double) {
        
        backgroundColor = .white
        label.textColor = UIColor.white
        
        label.text = "\(apy.formatted(.number.precision(.fractionLength(2)).locale(.forNumberFormatters)))%"
        
        backgroundGradient.colors = [
            UIColor.airBundle("EarnGradientColorLeft").cgColor,
            UIColor.airBundle("EarnGradientColorRight").cgColor,
        ]
        backgroundGradient.isHidden = false
        labelGradient.isHidden = true
        
        self.isHidden = false
        invalidateIntrinsicContentSize()
    }
    
    public func configureStakingInactive(yieldType: ApiYieldType, apy: Double) {
        
        backgroundColor = .white.withAlphaComponent(0.15)
        label.textColor = UIColor.white
        
        label.text = "\(yieldType.rawValue) \(apy)%"
        
        backgroundGradient.colors = [
            UIColor.airBundle("EarnGradientColorLeft").cgColor,
            UIColor.airBundle("EarnGradientColorRight").cgColor,
        ]
        backgroundGradient.isHidden = false
        labelGradient.colors = [
            UIColor.airBundle("EarnGradientColorLeft").cgColor,
            UIColor.airBundle("EarnGradientColorRight").cgColor,
        ]
        labelGradient.isHidden = false
        
        self.isHidden = false
        invalidateIntrinsicContentSize()
    }

    public func configureChain(chain: ApiChain) {
        configureTokenLabel(text: chain.usdtBadgeText, style: .regular)
    }

    public func configureTokenLabel(text: String, style: TokenLabelStyle) {
        switch style {
        case .regular:
            configure(
                text: text,
                foregroundColor: .air.secondaryLabel,
                backgroundColor: .air.secondaryLabel.withAlphaComponent(0.15)
            )
        case .stock:
            configure(
                text: text,
                foregroundColor: Self.stockLabelColor,
                backgroundColor: Self.stockLabelColor.withAlphaComponent(0.15)
            )
        }
    }

    public func configure(text: String, foregroundColor: UIColor, backgroundColor: UIColor) {
        self.backgroundColor = backgroundColor
        label.textColor = foregroundColor
        label.text = text

        backgroundGradient.isHidden = true
        labelGradient.isHidden = true

        self.isHidden = false
        invalidateIntrinsicContentSize()
    }
    
    public func configureHidden() {
        label.text = " "
        self.isHidden = true
        invalidateIntrinsicContentSize()
    }
}
