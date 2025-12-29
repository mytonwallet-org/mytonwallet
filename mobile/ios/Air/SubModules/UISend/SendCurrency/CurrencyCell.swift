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

        updateTheme()
        
        stackView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(currencySelected)))
    }
    
    public func updateTheme() {
        backgroundColor = .clear
        stackView.backgroundColor = .clear
        stackView.highlightBackgroundColor = WTheme.highlight
        amountLabel.textColor = WTheme.secondaryLabel
        selectedIcon.tintColor = WTheme.tint
    }
    
    @objc private func currencySelected() {
        onSelect?()
    }
    
    func configure(with walletToken: MTokenBalance, token: ApiToken?, isMultichain: Bool, currentTokenSlug: String, onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
        iconView.config(with: token, isWalletView: false, shouldShowChain: isMultichain)
        nameLabel.text = token?.name
        if let token {
            let amount = TokenAmount(walletToken.balance, token)
            amountLabel.text = amount.formatted(.defaultAdaptive)
        }
        selectedIcon.isHidden = walletToken.tokenSlug != currentTokenSlug
    }
    
}
