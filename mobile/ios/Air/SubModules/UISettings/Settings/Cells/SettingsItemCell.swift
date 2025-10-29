//
//  SettingsItemCell.swift
//  UISettings
//
//  Created by Sina on 6/26/24.
//

import Foundation
import UIKit
import UIComponents
import WalletContext
import WalletCore


class SettingsItemCell: UICollectionViewCell, WThemedView {

    override init(frame: CGRect) {
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private(set) var item: SettingsItem!
    
    private var containerView: WHighlightView = {
        let view = WHighlightView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private var iconImageView = IconView(size: 30)
    private var gradintLayer = CAGradientLayer()
    
    private var titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 17)
        return lbl
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
        stack.spacing = 0.667
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
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
        let imageView = UIImageView(image: .airBundle("RightArrowIcon"))
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
        
        iconImageView.layer.cornerRadius = 8
        iconImageView.layer.cornerCurve = .continuous
        iconImageView.clipsToBounds = true
        
        valueContainer.isTapToRevealEnabled = false
        
        let titleLabelLeadingConstraint = labelStack.leadingAnchor.constraint(equalTo: leadingGuide.trailingAnchor)
        titleLabelLeadingConstraint.priority = .defaultLow
        
        titleCenterXConstraint = labelStack.centerXAnchor.constraint(equalTo: containerView.centerXAnchor)
        
        let valueToRightConstraint = valueLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16)
        valueToRightConstraint.priority = .defaultLow

        // This constraint will be deactivated, whenever rightArrow is not visible.
        valueToLeftOfArrowConstraint = valueLabel.trailingAnchor.constraint(equalTo: rightArrow.leadingAnchor, constant: -8)
        
        layer.addSublayer(gradintLayer)
        gradintLayer.colors = [
            UIColor.white.withAlphaComponent(1).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor,
        ]
        gradintLayer.locations = [0, 1]
        gradintLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradintLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradintLayer.opacity = 0.5
        gradintLayer.cornerRadius = 8
        gradintLayer.compositingFilter = "softLightBlendMode"
        
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
    }
    
    func configure(with item: SettingsItem, value: String?) {
        self.item = item
        switch item.id {
        case .account(let accountId):
            iconImageView.setSize(40)
            if let account = AccountStore.allAccounts.first(where: { $0.id == accountId }) {
                iconImageView.config(with: account)
            } else {
                iconImageView.config(with: item.icon, tintColor: WTheme.tint)
            }
            valueContainer.isDisabled = false
            let cols = 6 + (abs(accountId.hashValue) % 6)
            valueContainer.setCols(cols)
            titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
        default:
            iconImageView.setSize(30)
            iconImageView.config(with: item.icon, tintColor: WTheme.tint)
            valueContainer.isDisabled = true
            titleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        }
        titleLabel.text = item.title
        subtitleLabel.text = item.subtitle
        subtitleLabel.isHidden = item.subtitle?.nilIfEmpty == nil
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            heightConstraint.constant = subtitleLabel.isHidden ? 52 : 60
        } else {
            heightConstraint.constant = subtitleLabel.isHidden ? 44 : 50
        }
        valueLabel.text = value
        if item.isDangerous {
            titleCenterXConstraint.isActive = true
            titleLabel.textColor = item.hasPrimaryColor ? WTheme.primaryButton.background : WTheme.error
            rightArrow.isHidden = true
        } else {
            titleCenterXConstraint.isActive = false
            titleLabel.textColor = item.hasPrimaryColor ? WTheme.primaryButton.background : WTheme.primaryLabel
            rightArrow.isHidden = !item.hasChild
        }
        valueToLeftOfArrowConstraint.isActive = !rightArrow.isHidden
        containerView.backgroundColor = WTheme.groupedItem
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradintLayer.frame = iconImageView.frame
    }
}
