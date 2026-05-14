//
//  AssetsAndActivityTokenCell.swift
//  UISettings
//
//  Created by Sina on 7/5/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

final class AssetsAndActivityTokenCell: UICollectionViewListCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var onSelect: (() -> Void)? = nil

    private var containerView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var iconImageView = IconView(size: 40, accessoryGeometry: .forIcon40)
    
    private var titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 16, weight: .medium)
        lbl.numberOfLines = 1
        lbl.lineBreakMode = .byTruncatingTail
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return lbl
    }()
    
    private var symbolLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 14)
        lbl.numberOfLines = 1
        lbl.lineBreakMode = .byTruncatingTail
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return lbl
    }()
    
    private lazy var showTokenSwitch: UISwitch = {
        let switchControl = UISwitch()
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        switchControl.addTarget(self, action: #selector(showTokenSwitched), for: .valueChanged)
        return switchControl
    }()
    
    private func setupViews() {
        isUserInteractionEnabled = true
        contentView.isUserInteractionEnabled = true
        addSubview(containerView)
        containerView.addSubview(iconImageView)
        containerView.addSubview(showTokenSwitch)
        
        let titleContainerView = UIView()
        titleContainerView.translatesAutoresizingMaskIntoConstraints = false
        titleContainerView.addSubview(titleLabel)
        titleContainerView.addSubview(symbolLabel)
        containerView.addSubview(titleContainerView)

        let containerHeight = containerView.heightAnchor.constraint(equalToConstant: 60)
        containerHeight.priority = UILayoutPriority(rawValue: UILayoutPriority.required.rawValue - 1)

        NSLayoutConstraint.activate([
            containerHeight,
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            titleContainerView.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 10),
            titleContainerView.trailingAnchor.constraint(equalTo: showTokenSwitch.leadingAnchor, constant: -12),
            titleContainerView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: titleContainerView.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: titleContainerView.topAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: titleContainerView.trailingAnchor),
            
            symbolLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            symbolLabel.leadingAnchor.constraint(equalTo: titleContainerView.leadingAnchor),
            symbolLabel.trailingAnchor.constraint(equalTo: titleContainerView.trailingAnchor),
            symbolLabel.bottomAnchor.constraint(equalTo: titleContainerView.bottomAnchor),

            showTokenSwitch.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            showTokenSwitch.centerYAnchor.constraint(equalTo: centerYAnchor),

            separatorLayoutGuide.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
        ])

        backgroundColor = .clear
        contentView.backgroundColor = .clear
        containerView.backgroundColor = .clear
        showTokenSwitch.tintColor = .air.secondaryLabel
        titleLabel.textColor = UIColor.label
        symbolLabel.textColor = .air.secondaryLabel

        automaticallyUpdatesBackgroundConfiguration = false
        var bg = UIBackgroundConfiguration.listGroupedCell()
        bg.backgroundColor = .air.groupedItem
        backgroundConfiguration = bg
    }
        
    private var onTokenVisibilityChange: ((String, Bool) -> Void)? = nil
    private var token: ApiToken? = nil
    private var ignoreUpdatesForSlug: String? = nil
    
    func configure(with token: ApiToken,
                   isStaking: Bool,
                   balance: BigInt,
                   importedSlug: Bool,
                   isHidden: Bool,
                   onTokenVisibilityChange: @escaping (String, Bool) -> Void) {
        if token.slug == ignoreUpdatesForSlug { return }
        let tokenChanged = self.token != token
        self.token = token
        self.onTokenVisibilityChange = onTokenVisibilityChange
        iconImageView.config(with: token, shouldShowChain: AccountStore.account?.isMultichain == true)
        titleLabel.text = MTokenBalance.displayName(apiToken: token, isStaking: isStaking)
        symbolLabel.text = token.symbol
        if !tokenChanged {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.token != nil {
                    self.showTokenSwitch.setOn(!isHidden, animated: true)
                }
            }
        } else {
            showTokenSwitch.isOn = !isHidden
        }
    }
    
    func ignoreFutureUpdatesForSlug(_ slug: String) {
        self.ignoreUpdatesForSlug = slug
    }
    
    @objc private func showTokenSwitched() {
        onTokenVisibilityChange?(token!.slug, showTokenSwitch.isOn)
    }
}
