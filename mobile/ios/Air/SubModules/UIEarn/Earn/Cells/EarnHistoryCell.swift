//
//  EarnHistoryCell.swift
//  UIEarn
//
//  Created by Sina on 5/13/24.
//

import UIKit
import UIComponents
import WalletContext
import WalletCore


class EarnHistoryCell: WHighlightCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // left icon
    private var iconStackView: IconStackView!

    // address label to show short presentation of the address
    private var titleLabel: UILabel!
    private var timeLabel: UILabel!
    private var amountContainer: WSensitiveData<WAmountLabel> = .init(cols: 12, rows: 2, cellSize: 9, cornerRadius: 5, theme: .adaptive, alignment: .trailing)
    private var amountLabel: WAmountLabel!
    private var amount2Container: WSensitiveData<WAmountLabel> = .init(cols: 9, rows: 2, cellSize: 7, cornerRadius: 4, theme: .adaptive, alignment: .trailing)
    private var amount2Label: WAmountLabel!
    private var separatorView: UIView!

    private func setupViews() {
        selectionStyle = .none
        
        // MARK: left icon
        iconStackView = IconStackView()
        iconStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconStackView)
        
        // MARK: title / time
        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.numberOfLines = 0
        contentView.addSubview(titleLabel)
        
        timeLabel = UILabel()
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .systemFont(ofSize: 14, weight: .regular)
        contentView.addSubview(timeLabel)
        
        // MARK: amount labels
        amountLabel = WAmountLabel()
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.font = .systemFont(ofSize: 17, weight: .regular)
        amountContainer.addContent(amountLabel)
        contentView.addSubview(amountContainer)
        
        amount2Label = WAmountLabel(primaryColor: WTheme.secondaryLabel, showNegativeSign: true)
        amount2Label.translatesAutoresizingMaskIntoConstraints = false
        amount2Label.font = .systemFont(ofSize: 14, weight: .regular)
        amount2Container.addContent(amount2Label)
        contentView.addSubview(amount2Container)
        
        // TODO: Migrate to system separators (tableView.separatorStyle)
        separatorView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = WTheme.separator
        addSubview(separatorView)
        
        // Setup all constraints
        NSLayoutConstraint.activate([
            // Icon
            iconStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            // Title label
            titleLabel.leadingAnchor.constraint(equalTo: iconStackView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: amountContainer.leadingAnchor, constant: -10),
            
            // Time label
            timeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            timeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            timeLabel.trailingAnchor.constraint(lessThanOrEqualTo: amount2Container.leadingAnchor, constant: -10),
            
            // Amount container
            amountContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            amountContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            
            // Amount2 container
            amount2Container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            amount2Container.topAnchor.constraint(equalTo: amountContainer.bottomAnchor, constant: 2),
            amount2Container.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
            
            // Separator
            separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: IOS_26_MODE_ENABLED ? -16 : 0),
            separatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 62),
            separatorView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
        
        // Set content compression priorities
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        amountContainer.isTapToRevealEnabled = false
        amount2Container.isTapToRevealEnabled = false
        
        updateTheme()
    }
    
    func updateTheme() {
        baseBackgroundColor = WTheme.groupedItem
        highlightBackgroundColor = WTheme.highlight
        timeLabel.textColor = WTheme.secondaryLabel
        separatorView.backgroundColor = WTheme.separator
    }
    
    func setSeparatorHidden(_ hidden: Bool) {
        separatorView.isHidden = hidden
    }
    
    func formatDateTime(date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.dateFormat = "d MMMM · HH:mm"
        return dateFormatter.string(from: date)
    }
    
    func formatDate(date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.dateFormat = "d MMMM"
        return dateFormatter.string(from: date)
    }

    // MARK: - Configure using ApiActivity
    public func configure(earnHistoryItem: MStakingHistoryItem, token: ApiToken) {
        contentView.alpha = 1
        // MARK: configure icon views
        iconStackView.configureAll(with: earnHistoryItem)
        iconStackView.setVisibleIcons(1)

        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.textColor = WTheme.secondaryLabel

        // address
        titleLabel.text = earnHistoryItem.type.localized

        // time
        timeLabel.text = formatDateTime(date: Date(timeIntervalSince1970: Double(earnHistoryItem.timestamp / 1000)))

        // set amount
        amountLabel.set(amount: earnHistoryItem.amount,
                        currency: token.symbol,
                        tokenDecimals: token.decimals,
                        decimalsCount: tokenDecimals(for: earnHistoryItem.amount, tokenDecimals: token.decimals),
                        forcePositiveColor: earnHistoryItem.type == .unstakeRequest ? WTheme.primaryLabel : nil)
        let price = TokenStore.tokens[token.slug]?.price ?? token.price ?? 0
        if price > 0 {
            let amnt = price * earnHistoryItem.amount.doubleAbsRepresentation(decimals: token.decimals)
            let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(amnt, TokenStore.baseCurrency)
            amount2Label.text = baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundUp: true)
        } else {
            amount2Label.text = " "
        }
        amount2Label.textColor = WTheme.secondaryLabel

        let amountCols = 4 + abs(earnHistoryItem.hashValue % 8)
        let fiatAmountCols = 5 + (amountCols % 6)
        amountContainer.setCols(amountCols)
        amount2Container.setCols(fiatAmountCols)
        amountContainer.setTheme(earnHistoryItem.type == .profit ? .color(WTheme.positiveAmount) : .adaptive)
        amount2Container.setTheme(.adaptive)
    }
    
    public func configure(stackedProfits: MStakingHistoryItem, startTimestamp: Int64, count: Int, token: ApiToken) {
        contentView.alpha = 1
        let earnHistoryItem = stackedProfits
        // MARK: configure icon views
        iconStackView.configureAll(with: earnHistoryItem)
        iconStackView.setVisibleIcons(min(3, count))

        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.textColor = WTheme.secondaryLabel

        titleLabel.text = "\(earnHistoryItem.type.localized) ×\(count)"

        // time
        let startDate = Date(timeIntervalSince1970: Double(startTimestamp / 1000))
        let endDate = Date(timeIntervalSince1970: Double(earnHistoryItem.timestamp / 1000))
        timeLabel.text = "\(formatDate(date: startDate))…\(formatDate(date: endDate))"

        // set amount
        amountLabel.set(amount: earnHistoryItem.amount,
                        currency: token.symbol,
                        tokenDecimals: token.decimals,
                        decimalsCount: tokenDecimals(for: earnHistoryItem.amount, tokenDecimals: token.decimals),
                        forcePositiveColor: earnHistoryItem.type == .unstakeRequest ? WTheme.primaryLabel : nil)
        let price = TokenStore.tokens[token.slug]?.price ?? token.price ?? 0
        if price > 0 {
            let amnt = price * earnHistoryItem.amount.doubleAbsRepresentation(decimals: token.decimals)
            let baseCurrencyAmount = BaseCurrencyAmount.fromDouble(amnt, TokenStore.baseCurrency)
            amount2Label.text = baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundUp: true)
        } else {
            amount2Label.text = " "
        }
        amount2Label.textColor = WTheme.secondaryLabel

        let amountCols = 5 + abs(earnHistoryItem.hashValue % 8)
        let fiatAmountCols = 6 + (amountCols % 6)
        amountContainer.setCols(amountCols)
        amount2Container.setCols(fiatAmountCols)
        amountContainer.setTheme(.color(WTheme.positiveAmount))
        amount2Container.setTheme(.adaptive)
    }
}
