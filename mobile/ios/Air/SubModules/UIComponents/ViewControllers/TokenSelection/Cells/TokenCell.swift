//
//  TokenCell.swift
//  UIComponents
//
//  Created by Sina on 5/10/24.
//

import Foundation
import UIKit
import WalletCore
import WalletContext

class TokenCell: UITableViewCell, WThemedView {
    
    private static let font = UIFont.systemFont(ofSize: 16, weight: .medium)
    private static let secondaryFont = UIFont.systemFont(ofSize: 13, weight: .regular)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var onSelect: (() -> Void)? = nil
    private let stackView = WHighlightStackView()
    private let iconView = IconView(size: 40)
    private let nameLabel = UILabel()
    
    private let amountLabelContainer = WSensitiveData(cols: 8, rows: 2, cellSize: 6, cornerRadius: 3, theme: .adaptive, alignment: .leading)
    private let amountLabel = UILabel()
    private let separatorLine = UIView()
    private func setupViews() {
        isUserInteractionEnabled = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leftAnchor.constraint(equalTo: leftAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.rightAnchor.constraint(equalTo: rightAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        stackView.addArrangedSubview(iconView, spacing: 16)

        let labelsStackView = UIStackView()
        labelsStackView.translatesAutoresizingMaskIntoConstraints = false
        labelsStackView.axis = .vertical
        stackView.addArrangedSubview(labelsStackView, spacing: 12)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = TokenCell.font
        labelsStackView.addArrangedSubview(nameLabel)

        
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.font = TokenCell.secondaryFont
        amountLabelContainer.addContent(amountLabel)
        labelsStackView.addArrangedSubview(amountLabelContainer)
        
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separatorLine)
        NSLayoutConstraint.activate([
            separatorLine.heightAnchor.constraint(equalToConstant: 0.33),
            separatorLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 68),
            separatorLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        updateTheme()

        stackView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tokenSelected)))
    }
    
    public func updateTheme() {
        backgroundColor = .clear
        stackView.backgroundColor = .clear
        stackView.highlightBackgroundColor = WTheme.highlight
        amountLabel.textColor = WTheme.secondaryLabel
        separatorLine.backgroundColor = WTheme.separatorDarkBackground
    }
    
    @objc func tokenSelected() {
        onSelect?()
    }
    
    func configure(with walletToken: MTokenBalance, isAvailable: Bool, onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
        let token = TokenStore.tokens[walletToken.tokenSlug]
        iconView.config(with: token, isStaking: false, isWalletView: false, shouldShowChain: AccountStore.account?.isMultichain == true || token?.chain != .ton)
        nameLabel.text = token?.name
        if isAvailable {
            if let token {
                let amount = TokenAmount(walletToken.balance, token)
                amountLabel.text = amount.formatted(.none, maxDecimals: token.decimals)
            }
        } else {
            amountLabel.text = lang("Unavailable")
        }
        stackView.alpha = isAvailable ? 1 : 0.5
        selectionStyle = isAvailable ? .gray : .none
    }

    func configure(with token: ApiToken, isAvailable: Bool, onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
        iconView.config(with: token, isStaking: false, shouldShowChain: AccountStore.account?.isMultichain == true || token.chain != .ton)
        nameLabel.text = token.name
        if isAvailable {
            amountLabel.text = token.chain.title
        } else {
            amountLabel.text = lang("Unavailable")
        }
        stackView.alpha = isAvailable ? 1 : 0.5
        selectionStyle = isAvailable ? .gray : .none
    }
    
}
