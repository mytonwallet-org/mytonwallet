import UIKit
import UIComponents

final class PerpsOrderTitleView: UIView {
    private let titleLabel = UILabel()
    private let priceLabel = UILabel()
    private var fullTitle = ""
    private var compactTitle = ""

    init() {
        super.init(frame: .zero)
        titleLabel.applyTextStyle(.bodyStrong)
        priceLabel.applyTextStyle(.footnote)
        priceLabel.textColor = .air.secondaryLabel
        for label in [titleLabel, priceLabel] {
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            label.isAccessibilityElement = false
            addSubview(label)
        }
        isAccessibilityElement = true
        accessibilityIdentifier = "perps.order.title"
        accessibilityTraits = .header
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(title: String, compactTitle: String, price: String) {
        fullTitle = title
        self.compactTitle = compactTitle
        priceLabel.text = price
        accessibilityLabel = title
        accessibilityValue = price
        sizeToFit()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: ceil(max(fullTitle.size(withAttributes: [.font: titleLabel.font!]).width,
                               priceLabel.intrinsicContentSize.width)), height: 44)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let ideal = intrinsicContentSize
        return CGSize(width: size.width > 0 ? min(size.width, ideal.width) : ideal.width, height: ideal.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.text = fullTitle.size(withAttributes: [.font: titleLabel.font!]).width <= bounds.width + 0.5 ? fullTitle : compactTitle
        titleLabel.frame = CGRect(x: 0, y: 2, width: bounds.width, height: 22)
        priceLabel.frame = CGRect(x: 0, y: 24, width: bounds.width, height: 18)
    }
}
