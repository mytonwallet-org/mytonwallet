
import Foundation
import SwiftUI
import WalletCore
import WalletContext

@MainActor
public final class BadgeView: UIView {
    
    private var label = UILabel()
    private var backgroundGradient = CAGradientLayer()
    private var labelGradient = CAGradientLayer()
    
    public init() {
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
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            self.heightAnchor.constraint(equalToConstant: 14)
        ])
        label.font = .systemFont(ofSize: 10, weight: .semibold)
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
    }

    public func configureChain(chain: ApiChain) {
        
        backgroundColor = WTheme.secondaryLabel.withAlphaComponent(0.15)
        label.textColor = WTheme.secondaryLabel
        
        label.text = chain.usdtBadgeText
        
        backgroundGradient.isHidden = true
        labelGradient.isHidden = true
        
        self.isHidden = false
    }
    
    public func configureHidden() {
        label.text = " "
        self.isHidden = true
    }
}
