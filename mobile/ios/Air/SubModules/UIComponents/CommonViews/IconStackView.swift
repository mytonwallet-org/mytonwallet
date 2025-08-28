
import UIKit
import WalletCore
import WalletContext


public class IconStackView: UIView {
    
    private var iconViews: [IconView] = []
    private var iconSizes: [CGFloat] = [40, 36, 30]
    private var alphaValues: [CGFloat] = [1.0, 0.6, 0.3]
    private var offset: CGFloat = 4
    private var bottomConstraint: NSLayoutConstraint?
    
    public init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure()
    }

    private func configure() {
        for (index, (size, alpha)) in zip(iconSizes, alphaValues).enumerated() {
            let iconView = IconView(size: size)
            iconView.alpha = alpha
            insertSubview(iconView, at: 0)
            iconViews.append(iconView)
            
            if index > 0, let firstIcon = iconViews.first {
                NSLayoutConstraint.activate([
                    iconView.centerXAnchor.constraint(equalTo: firstIcon.centerXAnchor),
                    iconView.bottomAnchor.constraint(equalTo: firstIcon.bottomAnchor, constant: CGFloat(index) * offset)
                ])
            }
        }
        
        if let firstIcon = iconViews.first, let lastIcon = iconViews.last {
            let bottomConstraint = bottomAnchor.constraint(equalTo: lastIcon.bottomAnchor)
            self.bottomConstraint = bottomConstraint
            NSLayoutConstraint.activate([
                leadingAnchor.constraint(equalTo: firstIcon.leadingAnchor),
                trailingAnchor.constraint(equalTo: firstIcon.trailingAnchor),
                topAnchor.constraint(equalTo: firstIcon.topAnchor),
                bottomConstraint
            ])
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func configureAll(with item: MStakingHistoryItem) {
        for iconView in iconViews {
            iconView.config(with: item)
        }
    }
    
    public func setVisibleIcons(_ count: Int) {
        guard count >= 1 && count <= 3 && iconViews.count == 3 else { return }
        
        for (index, iconView) in iconViews.enumerated() {
            iconView.isHidden = index >= count
        }
        
        // Update bottom constraint to use the last visible icon
        if let bottomConstraint {
            removeConstraint(bottomConstraint)
        }
        let bottomConstraint = bottomAnchor.constraint(equalTo: iconViews[count - 1].bottomAnchor)
        self.bottomConstraint = bottomConstraint
        NSLayoutConstraint.activate([
            bottomConstraint
        ])
    }
}

