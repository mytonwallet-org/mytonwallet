import UIActivityList
import UIComponents
import UIKit
import WalletContext

/// The Hyperliquid balance in a single-row card of its own, shaped like the positions card above it.
@MainActor
final class PerpsBalanceWithdrawalSectionDataProvider: ActivityListViewController.CustomSectionDataProvider {
    let id = "balance-withdrawal"
    var data: PerpsBalanceWithdrawalRowDisplayData?
    var topSpacing: CGFloat = 16
    var onSelect: (() -> Void)?
    var itemIdentifiers: [String] { data == nil ? [] : [id] }

    private lazy var registration = UICollectionView.CellRegistration<PerpsBalanceWithdrawalCell, PerpsBalanceWithdrawalRowDisplayData> { cell, _, data in
        cell.configure(data)
        cell.configurationUpdateHandler = { cell, state in cell.isHighlighted = state.isHighlighted }
    }

    func prepareForUse() {
        _ = registration
    }

    func makeLayoutSection(layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.headerTopPadding = 0
        let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        section.contentInsets.top = topSpacing
        section.contentInsets.bottom = 0
        return section
    }

    func dequeueCell(_ collectionView: UICollectionView, _ indexPath: IndexPath, itemIdentifier: String) -> UICollectionViewCell {
        guard let data else { return UICollectionViewCell() }
        return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: data)
    }

    func shouldSelect(itemIdentifier: String) -> Bool {
        data?.canWithdraw == true && data?.isPreparing == false
    }

    func didSelect(itemIdentifier: String) {
        guard shouldSelect(itemIdentifier: itemIdentifier) else { return }
        onSelect?()
    }
}

final class PerpsBalanceWithdrawalCell: WHighlightCollectionViewCell {
    private let icon = IconView(size: 40, accessoryGeometry: .forIcon40)
    private let balanceLabel = UILabel()
    private let detailLabel = UILabel()
    private let withdrawPill = UIView()
    private let withdrawLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let balanceAmount = WSensitiveData<TradeShineView>(cols: 10, rows: 2, cellSize: 7, cornerRadius: 4, theme: .adaptive, alignment: .leading)
    private var balanceShine: TradeShineView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        baseBackgroundColor = .air.groupedItem
        highlightBackgroundColor = .air.highlight
        contentView.backgroundColor = .clear
        balanceLabel.textColor = .label
        balanceLabel.adjustsFontSizeToFitWidth = true
        balanceLabel.minimumScaleFactor = 0.75
        balanceLabel.accessibilityIdentifier = "perps.balance.amount"
        balanceLabel.translatesAutoresizingMaskIntoConstraints = false
        let shine = TradeShineView(content: balanceLabel, usesAutoLayout: true)
        shine.translatesAutoresizingMaskIntoConstraints = false
        balanceShine = shine
        balanceAmount.addContent(shine)
        detailLabel.textColor = .air.secondaryLabel
        detailLabel.accessibilityIdentifier = "perps.balance.detail"
        let details = UIStackView(arrangedSubviews: [balanceAmount, detailLabel])
        details.axis = .vertical
        details.alignment = .leading
        details.translatesAutoresizingMaskIntoConstraints = false
        withdrawPill.backgroundColor = .tintColor.withAlphaComponent(0.1)
        withdrawPill.layer.cornerRadius = 15
        withdrawPill.translatesAutoresizingMaskIntoConstraints = false
        withdrawLabel.textColor = .tintColor
        withdrawLabel.text = lang("PerpsWithdraw")
        withdrawLabel.accessibilityIdentifier = "perps.balance.withdraw"
        withdrawLabel.accessibilityTraits = .button
        withdrawLabel.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .tintColor
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        withdrawPill.addSubview(withdrawLabel)
        withdrawPill.addSubview(spinner)
        contentView.addSubview(icon)
        contentView.addSubview(details)
        contentView.addSubview(withdrawPill)
        for label in [balanceLabel, detailLabel] { label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
        withdrawLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            details.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            details.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            details.trailingAnchor.constraint(equalTo: withdrawPill.leadingAnchor, constant: -10),
            balanceAmount.heightAnchor.constraint(equalToConstant: 22),
            detailLabel.heightAnchor.constraint(equalToConstant: 18),
            withdrawPill.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            withdrawPill.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            withdrawPill.heightAnchor.constraint(equalToConstant: 30),
            withdrawLabel.leadingAnchor.constraint(equalTo: withdrawPill.leadingAnchor, constant: 12),
            withdrawLabel.trailingAnchor.constraint(equalTo: withdrawPill.trailingAnchor, constant: -12),
            withdrawLabel.centerYAnchor.constraint(equalTo: withdrawPill.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: withdrawPill.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: withdrawPill.centerYAnchor),
        ])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(_ data: PerpsBalanceWithdrawalRowDisplayData) {
        icon.config(with: data.token, shouldShowChain: false)
        balanceLabel.applyTextStyle(.calloutEmphasized, content: .technical)
        detailLabel.applyTextStyle(.supporting)
        withdrawLabel.applyTextStyle(.supportingBold)
        balanceLabel.text = data.balance
        detailLabel.text = lang("PerpsAvailable") + " · " + data.token.symbol
        withdrawLabel.isHidden = data.isPreparing
        withdrawLabel.accessibilityTraits = data.canWithdraw ? .button : [.button, .notEnabled]
        withdrawPill.alpha = data.canWithdraw ? 1 : 0.5
        if data.isPreparing { spinner.startAnimating() } else { spinner.stopAnimating() }
        balanceShine?.setActive(data.isStale, animated: window != nil)
        accessibilityIdentifier = "perps.balance"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        balanceAmount.resetReveal()
        balanceShine?.setActive(false, animated: false)
    }
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        attributes.size.height = PerpsPositionCell.height
        return attributes
    }
}
