
import Foundation
import UIKit
import UIComponents
import WalletContext
import WalletCore


class SettingsAccountCell: UICollectionViewCell, WThemedView {

    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var containerView: WHighlightView = {
        let view = WHighlightView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private var iconImageView = IconView(size: 40)
    
    private var titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 17)
        return lbl
    }()
    
    private var badge: BadgeView = BadgeView()

    private lazy var titleAndBadge: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        view.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            badge.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor, constant: 0.333),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            badge.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
        ])
        return view
    }()
    
    private var subtitleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 14)
        lbl.textColor = WTheme.secondaryLabel
        return lbl
    }()
    
    private lazy var labelStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleAndBadge)
        stack.addArrangedSubview(subtitleLabel)
        return stack
    }()
    
    private var leadingGuide = UILayoutGuide()
    
    private var valueContainer: WSensitiveData<UILabel> = .init(cols: 8, rows: 2, cellSize: 9, cornerRadius: 5, theme: .adaptive, alignment: .trailing)
    
    private var valueLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 17)
        return lbl
    }()
    
    private var rightArrow: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "RightArrowIcon", in: AirBundle, compatibleWith: nil)!.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private var valueToLeftOfArrowConstraint: NSLayoutConstraint!
    private var titleCenterXConstraint: NSLayoutConstraint!
    private var heightConstraint: NSLayoutConstraint!
    
    private func setupViews() {
        isUserInteractionEnabled = true
        contentView.isUserInteractionEnabled = true
        contentView.addSubview(containerView)
        
        heightConstraint = containerView.heightAnchor.constraint(equalToConstant: 44).withPriority(.init(999))
        
        NSLayoutConstraint.activate([
            heightConstraint,
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 0),
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        containerView.addLayoutGuide(leadingGuide)
        containerView.addSubview(iconImageView)
        containerView.addSubview(labelStack)
        valueContainer.addContent(valueLabel)
        containerView.addSubview(valueContainer)
        containerView.addSubview(rightArrow)
        
        valueContainer.isTapToRevealEnabled = false
        
        let titleLabelLeadingConstraint = labelStack.leadingAnchor.constraint(equalTo: leadingGuide.trailingAnchor)
        titleLabel.setContentCompressionResistancePriority(.init(749), for: .horizontal)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleCenterXConstraint = labelStack.centerXAnchor.constraint(equalTo: containerView.centerXAnchor)
        
        let valueToRightConstraint = valueLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16)
        valueToRightConstraint.priority = .init(999)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        // This constraint will be deactivated, whenever rightArrow is not visible.
        valueToLeftOfArrowConstraint = valueLabel.trailingAnchor.constraint(equalTo: rightArrow.leadingAnchor, constant: -8)
        
        NSLayoutConstraint.activate([
            
            leadingGuide.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            leadingGuide.widthAnchor.constraint(equalToConstant: 60),
            leadingGuide.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            iconImageView.centerXAnchor.constraint(equalTo: leadingGuide.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            titleLabelLeadingConstraint,
            labelStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            valueToRightConstraint,
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: labelStack.trailingAnchor, constant: 12),
            valueLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            rightArrow.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            rightArrow.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        
        updateTheme()
    }
    
    public func updateTheme() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        if containerView.backgroundColor != .clear {
            containerView.backgroundColor = WTheme.groupedItem
        }
        containerView.highlightBackgroundColor = WTheme.highlight
        valueLabel.textColor = WTheme.secondaryLabel
        rightArrow.tintColor = WTheme.secondaryLabel.withAlphaComponent(0.85)
    }
    
    func configure(with accountId: String, title: String, subtitle: String?, value: String?) {
        if let account = AccountStore.accountsById[accountId] {
            iconImageView.config(with: account)
            badge.configureWithAccountType(account.type)
        } else {
            badge.configureHidden()
        }
        valueContainer.isDisabled = false
        let cols = 6 + (abs(accountId.hashValue) % 6)
        valueContainer.setCols(cols)
        titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.nilIfEmpty == nil
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            heightConstraint.constant = subtitleLabel.isHidden ? 52 : 58
        } else {
            heightConstraint.constant = subtitleLabel.isHidden ? 44 : 52
        }
        valueLabel.text = value
        titleCenterXConstraint.isActive = false
        titleLabel.textColor = WTheme.primaryLabel
        rightArrow.isHidden = true
        valueToLeftOfArrowConstraint.isActive = !rightArrow.isHidden
        containerView.backgroundColor = WTheme.groupedItem
    }
}
