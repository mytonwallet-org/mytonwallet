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

public final class TokenCell: UITableViewCell {
    
    private static let horizontalInset: CGFloat = 12
    private static let tokenImageToTextSpacing: CGFloat = 12
    private static let titleFont = UIFont.systemFont(ofSize: 16, weight: .medium)
    private static let amountFont = UIFont.systemFont(ofSize: 16, weight: .regular)
    private static let secondaryFont = UIFont.systemFont(ofSize: 14, weight: .regular)
    private static let badgeForegroundColor = UIColor.air.secondaryLabel
    private static let badgeBackgroundColor = UIColor.air.secondaryLabel.withAlphaComponent(0.15)

    private let selectionIndicatorView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var onSelect: (() -> Void)? = nil
    private let stackView = WHighlightStackView()
    private let iconView = IconView(size: 40)
    private let contentStackView = UIStackView()
    private let leftLabelsStackView = UIStackView()
    private let titleRowStackView = UIStackView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let badgeView = BadgeView()
    private let amountLabelContainer = WSensitiveData(cols: 8, rows: 2, cellSize: 6, cornerRadius: 3, theme: .adaptive, alignment: .trailing)
    private let amountLabel = UILabel()
    private let secondaryAmountLabelContainer = WSensitiveData(cols: 8, rows: 2, cellSize: 6, cornerRadius: 3, theme: .adaptive, alignment: .trailing)
    private let secondaryAmountLabel = UILabel()
    
    private func setupViews() {
        isUserInteractionEnabled = true
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionIndicatorView.tintColor = .tintColor

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Self.tokenImageToTextSpacing
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = .init(top: 0, leading: Self.horizontalInset, bottom: 0, trailing: Self.horizontalInset)
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        stackView.addArrangedSubview(iconView)

        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .horizontal
        contentStackView.alignment = .center
        contentStackView.spacing = 12
        stackView.addArrangedSubview(contentStackView)

        leftLabelsStackView.translatesAutoresizingMaskIntoConstraints = false
        leftLabelsStackView.axis = .vertical
        leftLabelsStackView.alignment = .leading
        leftLabelsStackView.spacing = 1
        leftLabelsStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentStackView.addArrangedSubview(leftLabelsStackView)

        titleRowStackView.translatesAutoresizingMaskIntoConstraints = false
        titleRowStackView.axis = .horizontal
        titleRowStackView.alignment = .center
        titleRowStackView.spacing = 4
        titleRowStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        leftLabelsStackView.addArrangedSubview(titleRowStackView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = TokenCell.titleFont
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleRowStackView.addArrangedSubview(titleLabel)

        badgeView.setContentCompressionResistancePriority(.required, for: .horizontal)
        badgeView.setContentHuggingPriority(.required, for: .horizontal)
        titleRowStackView.addArrangedSubview(badgeView)
        badgeView.configureHidden()

        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = TokenCell.secondaryFont
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        leftLabelsStackView.addArrangedSubview(descriptionLabel)

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentStackView.addArrangedSubview(spacer)

        let trailingLabelsStackView = UIStackView()
        trailingLabelsStackView.translatesAutoresizingMaskIntoConstraints = false
        trailingLabelsStackView.axis = .vertical
        trailingLabelsStackView.alignment = .trailing
        trailingLabelsStackView.spacing = 1
        trailingLabelsStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
        trailingLabelsStackView.setContentHuggingPriority(.required, for: .horizontal)
        contentStackView.addArrangedSubview(trailingLabelsStackView)

        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.font = TokenCell.amountFont
        amountLabel.textAlignment = .right
        amountLabelContainer.addContent(amountLabel)
        trailingLabelsStackView.addArrangedSubview(amountLabelContainer)

        secondaryAmountLabel.translatesAutoresizingMaskIntoConstraints = false
        secondaryAmountLabel.font = TokenCell.secondaryFont
        secondaryAmountLabel.textAlignment = .right
        secondaryAmountLabelContainer.addContent(secondaryAmountLabel)
        trailingLabelsStackView.addArrangedSubview(secondaryAmountLabelContainer)

        amountLabelContainer.isTapToRevealEnabled = false
        secondaryAmountLabelContainer.isTapToRevealEnabled = false

        updateTheme()

        stackView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tokenSelected)))
    }
    
    private func updateTheme() {
        stackView.backgroundColor = .clear
        stackView.highlightBackgroundColor = .air.highlight
        titleLabel.textColor = .label
        descriptionLabel.textColor = .air.secondaryLabel
        amountLabel.textColor = .label
        secondaryAmountLabel.textColor = .air.secondaryLabel
        selectionIndicatorView.tintColor = .tintColor
    }
    
    @objc func tokenSelected() {
        onSelect?()
    }
    
    public func configure(with walletToken: MTokenBalance, isAvailable: Bool, isCurrentSelection: Bool = false, onSelect: @escaping () -> Void) {
        let token = TokenStore.tokens[walletToken.tokenSlug]
        configure(
            token: token,
            balance: walletToken.balance,
            isAvailable: isAvailable,
            isStaking: walletToken.isStaking,
            fallbackName: walletToken.tokenSlug,
            isCurrentSelection: isCurrentSelection,
            onSelect: onSelect
        )
    }

    public func configure(with token: ApiToken, balance: BigInt, isAvailable: Bool, isCurrentSelection: Bool = false, onSelect: @escaping () -> Void) {
        configure(
            token: token,
            balance: balance,
            isAvailable: isAvailable,
            isStaking: false,
            fallbackName: token.name,
            isCurrentSelection: isCurrentSelection,
            onSelect: onSelect
        )
    }
    
    private func configure(token: ApiToken?, balance: BigInt, isAvailable: Bool, isStaking: Bool, fallbackName: String, isCurrentSelection: Bool, onSelect: @escaping () -> Void) {
        self.onSelect = onSelect
        iconView.config(with: token, isStaking: isStaking, isWalletView: false, shouldShowChain: AccountStore.account?.isMultichain == true || token?.chain != .ton)
        titleLabel.text = if let token {
            MTokenBalance.displayName(apiToken: token, isStaking: isStaking)
        } else {
            fallbackName
        }
        if let badgeText = token?.label?.nilIfEmpty {
            badgeView.configure(
                text: badgeText,
                foregroundColor: Self.badgeForegroundColor,
                backgroundColor: Self.badgeBackgroundColor
            )
        } else {
            badgeView.configureHidden()
        }
        descriptionLabel.text = isAvailable ? token?.chain.title : lang("Unavailable")
        amountLabel.text = formatAmount(balance: balance, token: token)
        secondaryAmountLabel.text = formatSecondaryAmount(balance: balance, token: token)
        stackView.alpha = isAvailable ? 1 : 0.5
        selectionStyle = .none
        accessoryView = isCurrentSelection ? selectionIndicatorView : nil
    }
    
    private func formatAmount(balance: BigInt, token: ApiToken?) -> String {
        guard let token else { return "" }
        return TokenAmount(balance, token).formatted(.defaultAdaptive, roundHalfUp: false)
    }
    
    private func formatSecondaryAmount(balance: BigInt, token: ApiToken?) -> String {
        guard let price = token?.price, price != 0 else {
            return lang("No Price")
        }
        let amount = balance.doubleAbsRepresentation(decimals: token?.decimals ?? 0)
        let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(amount * price, TokenStore.baseCurrency)
        return baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundHalfUp: true)
    }
}
