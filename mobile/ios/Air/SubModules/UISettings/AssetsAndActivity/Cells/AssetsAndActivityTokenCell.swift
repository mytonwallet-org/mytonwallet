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

final class AssetsAndActivityTokenCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
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

    private var iconImageView: IconView = IconView(size: 40)
    
    private var titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 16)
        lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return lbl
    }()
    
    private var symbolLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 13)
        return lbl
    }()
    
    private lazy var showTokenSwitch: UISwitch = {
        let switchControl = UISwitch()
        switchControl.translatesAutoresizingMaskIntoConstraints = false
        switchControl.addTarget(self, action: #selector(showTokenSwitched), for: .valueChanged)
        return switchControl
    }()
    
    private func setupViews() {
        selectionStyle = .none
        isUserInteractionEnabled = true
        contentView.isUserInteractionEnabled = true
        addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.heightAnchor.constraint(equalToConstant: 56),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        containerView.addSubview(iconImageView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(symbolLabel)
        containerView.addSubview(showTokenSwitch)
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(equalTo: showTokenSwitch.leadingAnchor, constant: -12),
            
            symbolLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            symbolLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            
            showTokenSwitch.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            showTokenSwitch.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        containerView.backgroundColor = WTheme.groupedItem
        showTokenSwitch.tintColor = WTheme.secondaryLabel
        titleLabel.textColor = WTheme.primaryLabel
        symbolLabel.textColor = WTheme.secondaryLabel
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
