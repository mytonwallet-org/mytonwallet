import UIKit
import WalletContext

/// Compact activity rows shared by account and asset histories.
open class ActivitySummaryCell: WHighlightCollectionViewCell {
    public static let rowHeight: CGFloat = 60
    public let icon: IconView
    public let titleLabel = UILabel()
    public let badge = BadgeView()
    public let dateLabel = UILabel()
    public let amountLabel = UILabel()
    public let detailLabel = UILabel()
    private let amounts = WSensitiveData<TradeShineView>(cols: 8, rows: 2, cellSize: 7, cornerRadius: 4,
                                                     theme: .adaptive, alignment: .trailing, reservesMaskWidth: true)
    private var amountShine: TradeShineView?
    private var isAmountMasked = false
    private var canSelect = false

    public override init(frame: CGRect) {
        icon = IconView(size: 40)
        super.init(frame: frame)
        setup()
    }

    private func setup() {
        baseBackgroundColor = .air.groupedItem
        highlightBackgroundColor = .air.highlight
        contentView.backgroundColor = .clear
        titleLabel.textColor = .label
        dateLabel.textColor = .air.secondaryLabel
        detailLabel.textColor = .air.secondaryLabel
        for label in [titleLabel, dateLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        for label in [amountLabel, detailLabel] {
            label.textAlignment = .right
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.75
        }
        let values = UIStackView(arrangedSubviews: [amountLabel, detailLabel])
        values.axis = .vertical
        values.alignment = .trailing
        values.translatesAutoresizingMaskIntoConstraints = false
        let shine = TradeShineView(content: values, usesAutoLayout: true)
        shine.translatesAutoresizingMaskIntoConstraints = false
        amountShine = shine
        amounts.addContent(shine)
        let heading = UIStackView(arrangedSubviews: [titleLabel, badge])
        heading.alignment = .center
        heading.spacing = 4
        let details = UIStackView(arrangedSubviews: [heading, dateLabel])
        details.axis = .vertical
        details.alignment = .leading
        details.translatesAutoresizingMaskIntoConstraints = false
        for view in [icon, details, amounts] { contentView.addSubview(view) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            details.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            details.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            details.trailingAnchor.constraint(equalTo: amounts.leadingAnchor, constant: -8),
            heading.widthAnchor.constraint(lessThanOrEqualTo: details.widthAnchor),
            dateLabel.widthAnchor.constraint(lessThanOrEqualTo: details.widthAnchor),
            titleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
            dateLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 18),
            amountLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
            amounts.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            amounts.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            amounts.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.42),
        ])
        amounts.onMaskStateChanged = { [weak self] hidden in
            guard let self else { return }
            isAmountMasked = hidden
            updateAccessibilityValue()
        }
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged)))
    }

    @available(*, unavailable) required public init?(coder: NSCoder) { nil }

    public func configure(title: String, badge badgeText: String = "", date: String,
                          amount: NSAttributedString, detail: String? = nil,
                          image: UIImage, gradientColors: [UIColor],
                          accessibilityIdentifier: String, canSelect: Bool, isStale: Bool = false) {
        self.canSelect = canSelect
        titleLabel.applyTextStyle(.calloutEmphasized)
        titleLabel.text = title
        dateLabel.applyTextStyle(.supporting)
        dateLabel.text = date
        amountLabel.applyTextStyle(.callout, content: .technical)
        amountLabel.attributedText = amount
        detailLabel.applyTextStyle(.supporting)
        detailLabel.text = detail
        detailLabel.isHidden = detail?.isEmpty != false
        if badgeText.isEmpty { badge.configureHidden() }
        else {
            badge.configureTokenLabel(text: badgeText, style: .regular, content: .default)
        }
        icon.config(activityImage: image, gradientColors: gradientColors)
        self.accessibilityIdentifier = accessibilityIdentifier
        isAccessibilityElement = true
        accessibilityLabel = [title, badgeText, date].filter { !$0.isEmpty }.joined(separator: ", ")
        accessibilityTraits = canSelect ? .button : []
        updateAccessibilityValue()
        amountShine?.setActive(isStale, animated: window != nil)
        if !canSelect { isHighlighted = false }
    }

    public override var isHighlighted: Bool {
        get { super.isHighlighted }
        set { super.isHighlighted = canSelect && newValue }
    }

    private func updateAccessibilityValue() {
        accessibilityValue = isAmountMasked ? nil : [amountLabel.attributedText?.string, detailLabel.text]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    @objc private func hoverChanged(_ gesture: UIHoverGestureRecognizer) {
        isHighlighted = gesture.state == .began || gesture.state == .changed
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        amounts.resetReveal()
        amountShine?.setActive(false, animated: false)
    }

    public override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let result = attributes.copy() as! UICollectionViewLayoutAttributes
        result.size.height = Self.rowHeight
        return result
    }
}
