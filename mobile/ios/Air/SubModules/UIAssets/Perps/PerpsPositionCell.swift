import UIComponents
import UIKit
import WalletContext

final class PerpsPositionCell: WHighlightCollectionViewCell {
    static let height: CGFloat = 60
    private let icon = IconView(size: 40, accessoryGeometry: .forIcon40)
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let valueLabel = UILabel()
    private let pnlLabel = UILabel()
    private let warning = UIImageView(image: UIImage(systemName: "exclamationmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12)))
    private let amounts = WSensitiveData<TradeShineView>(cols: 10, rows: 2, cellSize: 7, cornerRadius: 4, theme: .adaptive, alignment: .trailing)
    private var amountShine: TradeShineView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        baseBackgroundColor = .air.groupedItem
        highlightBackgroundColor = .air.highlight
        contentView.backgroundColor = .clear
        nameLabel.textColor = .label
        detailLabel.textColor = .air.secondaryLabel
        valueLabel.textColor = .label
        valueLabel.textAlignment = .right
        pnlLabel.textAlignment = .right
        warning.tintColor = .air.negativeAmount
        warning.contentMode = .scaleAspectFit
        warning.isAccessibilityElement = true
        warning.accessibilityLabel = lang("Liquidation Risk")
        warning.accessibilityIdentifier = "perps.positions.liquidationWarning"
        let result = UIStackView(arrangedSubviews: [warning, pnlLabel])
        result.spacing = 4
        result.alignment = .center
        let values = UIStackView(arrangedSubviews: [valueLabel, result])
        values.axis = .vertical
        values.alignment = .trailing
        values.translatesAutoresizingMaskIntoConstraints = false
        let shine = TradeShineView(content: values, usesAutoLayout: true)
        shine.translatesAutoresizingMaskIntoConstraints = false
        amountShine = shine
        amounts.addContent(shine)
        let details = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        details.axis = .vertical
        details.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(icon)
        contentView.addSubview(details)
        contentView.addSubview(amounts)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for label in [valueLabel, pnlLabel] { label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.75 }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            details.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            details.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            details.trailingAnchor.constraint(equalTo: amounts.leadingAnchor, constant: -8),
            amounts.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            amounts.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            amounts.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.55),
            warning.heightAnchor.constraint(equalToConstant: 14),
        ])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(_ data: PerpsPositionRowDisplayData, isStale: Bool) {
        icon.config(with: data.token, shouldShowChain: false)
        nameLabel.applyTextStyle(.calloutEmphasized)
        detailLabel.applyTextStyle(.supporting)
        valueLabel.applyTextStyle(.callout, content: .technical)
        pnlLabel.applyTextStyle(.supporting, content: .technical)
        nameLabel.text = data.token.name
        detailLabel.text = data.directionAndLeverage
        valueLabel.text = data.value
        pnlLabel.text = data.profitLoss.text
        pnlLabel.textColor = data.profitLoss.tone.uiColor
        warning.isHidden = !data.isAtRisk
        amountShine?.setActive(isStale, animated: window != nil)
        accessibilityIdentifier = "perps.positions." + data.id
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        amounts.resetReveal()
        amountShine?.setActive(false, animated: false)
    }
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        attributes.size.height = Self.height
        return attributes
    }
}
