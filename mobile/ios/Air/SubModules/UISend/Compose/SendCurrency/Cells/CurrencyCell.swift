//
//  CurrencyCell.swift
//  UISend
//
//  Created by Sina on 4/18/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

class CurrencyCell: UITableViewCell, WThemedView {
    
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
    private let selectedIcon = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    private let separatorLine = UIView()
    
    private func setupViews() {
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
        nameLabel.font = CurrencyCell.font
        labelsStackView.addArrangedSubview(nameLabel)

        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.font = CurrencyCell.secondaryFont
        amountLabelContainer.addContent(amountLabel)
        labelsStackView.addArrangedSubview(amountLabelContainer)
        
        selectedIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            selectedIcon.widthAnchor.constraint(equalToConstant: 22),
            selectedIcon.heightAnchor.constraint(equalToConstant: 22),
        ])
        stackView.addArrangedSubview(selectedIcon, margin: .init(top: 0, left: 16, bottom: 0, right: 16))
        
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separatorLine)
        NSLayoutConstraint.activate([
            separatorLine.heightAnchor.constraint(equalToConstant: 0.33),
            separatorLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 68),
            separatorLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateTheme()
        
        stackView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(currencySelected)))
    }
    
    public func updateTheme() {
        backgroundColor = .clear
        stackView.backgroundColor = .clear
        stackView.highlightBackgroundColor = WTheme.highlight
        amountLabel.textColor = WTheme.secondaryLabel
        selectedIcon.tintColor = WTheme.tint
        separatorLine.backgroundColor = WTheme.separatorDarkBackground
    }
    
    @objc private func currencySelected() {
        onSelect?()
    }
    
    func configure(with walletToken: MTokenBalance, currentTokenSlug: String, onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
        let token = TokenStore.tokens[walletToken.tokenSlug]
        iconView.config(with: token, isWalletView: false, shouldShowChain: AccountStore.account?.isMultichain == true)
        nameLabel.text = token?.name
        amountLabel.text = formatBigIntText(walletToken.balance,
                                             currency: token?.symbol,
                                             tokenDecimals: token?.decimals ?? 9,
                                             decimalsCount: token?.decimals,
                                             forceCurrencyToRight: true)
        selectedIcon.isHidden = walletToken.tokenSlug != currentTokenSlug
    }
    
}
