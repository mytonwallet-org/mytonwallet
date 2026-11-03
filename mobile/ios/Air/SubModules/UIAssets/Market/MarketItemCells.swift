import UIComponents
import UIKit
import WalletContext
import WalletCore

/// Market item interaction matches wallet rows, including immediate touch-down and cancellation.
class MarketItemCell: WHighlightCollectionViewCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        baseBackgroundColor = .clear
        highlightBackgroundColor = .air.highlight
        isAccessibilityElement = true
        accessibilityTraits = .button
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hoverChanged)))
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    @objc private func hoverChanged(_ gesture: UIHoverGestureRecognizer) {
        isHighlighted = gesture.state == .began || gesture.state == .changed
    }
}

final class MarketTileCell: MarketItemCell {
    private let icon = IconView(size: 56, accessoryGeometry: .forIcon56)
    private let nameLabel = UILabel()
    private let changeLabel = UILabel()
    private lazy var changeShine = TradeShineView(content: changeLabel)

    override init(frame: CGRect) {
        super.init(frame: frame)
        highlightBackgroundColor = .clear
        highlightedContentAlpha = 0.5
        unhighlightingTime = 0.2
        icon.isUserInteractionEnabled = false
        for view in [icon, nameLabel, changeShine] { contentView.addSubview(view) }
        icon.translatesAutoresizingMaskIntoConstraints = true
        nameLabel.textAlignment = .center
        changeLabel.textAlignment = .center
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.8
        changeLabel.adjustsFontSizeToFitWidth = true
        changeLabel.minimumScaleFactor = 0.8
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(_ token: MarketItemDisplayData) {
        icon.config(with: token.token, shouldShowChain: false)
        nameLabel.applyTextStyle(.supportingEmphasized)
        nameLabel.textColor = .label
        nameLabel.text = token.name
        changeLabel.applyTextStyle(.supporting)
        changeLabel.textColor = token.isPositive ? .air.positiveAmount : .air.negativeAmount
        changeLabel.text = token.changeText
        changeShine.setActive(token.isStale, animated: window != nil)
        accessibilityLabel = "\(token.name), \(token.changeText)"
        accessibilityIdentifier = "market.tile." + token.id
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        icon.frame = CGRect(x: (width - 56) / 2, y: 0, width: 56, height: 56)
        nameLabel.frame = CGRect(x: 1, y: 62, width: width - 2, height: 18)
        changeShine.frame = CGRect(x: 1, y: 80, width: width - 2, height: 18)
    }
}

final class MarketQuoteView: UIView {
    private let priceLabel = UILabel()
    private let changeLabel = UILabel()
    private let quoteContent = UIView()
    private lazy var shine = TradeShineView(content: quoteContent)
    var centered = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(shine)
        quoteContent.addSubview(priceLabel)
        quoteContent.addSubview(changeLabel)
        for label in [priceLabel, changeLabel] { label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.7 }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(_ item: MarketItemDisplayData) {
        priceLabel.applyTextStyle(.supporting, content: .technical)
        priceLabel.text = item.priceText
        priceLabel.textColor = .air.secondaryLabel
        changeLabel.applyTextStyle(.supporting)
        changeLabel.text = item.changeText
        changeLabel.textColor = item.isPositive ? .air.positiveAmount : .air.negativeAmount
        shine.setActive(item.isStale, animated: window != nil)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shine.frame = bounds
        let priceWidth = priceLabel.sizeThatFits(CGSize(width: 1000, height: bounds.height)).width
        let changeWidth = changeLabel.sizeThatFits(CGSize(width: 1000, height: bounds.height)).width
        let gap: CGFloat = priceLabel.text?.isEmpty == false ? 4 : 0
        let scale = min(1, bounds.width / max(1, priceWidth + changeWidth + gap))
        let width = (priceWidth + changeWidth + gap) * scale
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let x = centered ? (bounds.width - width) / 2 : (rtl ? bounds.width - width : 0)
        priceLabel.frame = CGRect(x: rtl ? x + (changeWidth + gap) * scale : x, y: 0, width: priceWidth * scale, height: bounds.height)
        changeLabel.frame = CGRect(x: rtl ? x : x + (priceWidth + gap) * scale, y: 0, width: changeWidth * scale, height: bounds.height)
    }
}

final class MarketRowCell: MarketItemCell {
    private let icon = IconView(size: 40, accessoryGeometry: .forIcon40)
    private let nameLabel = UILabel()
    private let badge = BadgeView()
    private let quote = MarketQuoteView()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.forward", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)))
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.isUserInteractionEnabled = false
        icon.translatesAutoresizingMaskIntoConstraints = true
        badge.translatesAutoresizingMaskIntoConstraints = true
        chevron.contentMode = .center
        chevron.tintColor = .tertiaryLabel
        separator.backgroundColor = .air.separator
        for view in [icon, nameLabel, badge, quote, chevron, separator] { contentView.addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(_ item: MarketItemDisplayData, showsChevron: Bool, showsSeparator: Bool = false) {
        icon.config(with: item.token, shouldShowChain: item.showsChain && !item.token.isRwaStock)
        nameLabel.applyTextStyle(.calloutEmphasized)
        nameLabel.textColor = .label
        nameLabel.text = item.name.nilIfEmpty ?? item.token.symbol
        if let label = item.token.label?.nilIfEmpty { badge.configureTokenLabel(text: label, style: .stock) }
        else { badge.configureHidden() }
        quote.configure(item)
        chevron.isHidden = !showsChevron
        separator.isHidden = !showsSeparator
        accessibilityLabel = "\(item.name), \(item.token.symbol), \(item.priceText ?? ""), \(item.changeText)"
        accessibilityIdentifier = "market.row." + item.id
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rtl ? width - x - w : x, y: y, width: w, height: h)
        }
        icon.frame = rect(12, 10, 40, 40)
        let available = max(0, width - 62 - (chevron.isHidden ? 12 : 40))
        let nameWidth = min(available, nameLabel.sizeThatFits(CGSize(width: 1000, height: 22)).width)
        nameLabel.frame = rect(62, 10, nameWidth, 22)
        let badgeWidth = min(max(0, available - nameWidth - 4), badge.intrinsicContentSize.width)
        badge.frame = rect(62 + nameWidth + 4, 14, badgeWidth, 14)
        quote.frame = rect(62, 32, available, 18)
        chevron.frame = rect(width - 30, 19, 16, 22)
        separator.frame = rect(62, bounds.height - 1 / traitCollection.displayScale, max(0, width - 74), 1 / traitCollection.displayScale)
    }

    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let result = attributes.copy() as! UICollectionViewLayoutAttributes
        result.size.height = 60
        return result
    }
}

final class MarketMoverCell: MarketItemCell {
    private let surface: UIView
    private let tint = UIView()
    private let icon = IconView(size: 44)
    private let nameLabel = UILabel()
    private let quote = MarketQuoteView()
    private let chart = MarketChartView()
    private lazy var chartShine = TradeShineView(content: chart)

    override init(frame: CGRect) {
        if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            let glass = UIVisualEffectView(effect: effect)
            glass.cornerConfiguration = .corners(radius: 32)
            surface = glass
        } else {
            surface = UIView()
            surface.backgroundColor = .air.groupedItem
            surface.layer.cornerRadius = 32
            surface.layer.cornerCurve = .continuous
            surface.layer.borderWidth = 0.5
            surface.layer.borderColor = UIColor.air.separator.withAlphaComponent(0.55).cgColor
        }
        super.init(frame: frame)
        layer.cornerRadius = 32
        layer.cornerCurve = .continuous
        contentView.addSubview(surface)
        let content = (surface as? UIVisualEffectView)?.contentView ?? surface
        content.layer.cornerRadius = 32
        content.layer.cornerCurve = .continuous
        content.clipsToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = true
        icon.isUserInteractionEnabled = false
        nameLabel.textAlignment = .center
        quote.centered = true
        for view in [tint, chartShine, icon, nameLabel, quote] { content.addSubview(view) }
        tint.isUserInteractionEnabled = false
        if !(surface is UIVisualEffectView) {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.02
            layer.shadowRadius = 7.5
            layer.shadowOffset = CGSize(width: 0, height: 8)
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(_ item: MarketItemDisplayData) {
        icon.config(with: item.token, shouldShowChain: item.showsChain)
        nameLabel.applyTextStyle(.calloutStrong)
        nameLabel.textColor = .label
        nameLabel.text = item.name
        quote.configure(item)
        chart.configure(item.chart)
        chartShine.setActive(item.isStale, animated: window != nil)
        tint.backgroundColor = item.chart.map { UIColor(rgb: $0.tint).withAlphaComponent(0.06) }
        accessibilityLabel = "\(item.name), \(item.priceText ?? ""), \(item.changeText)"
        accessibilityIdentifier = "market.mover." + item.id
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.frame = contentView.bounds
        tint.frame = contentView.bounds
        icon.frame = CGRect(x: 58, y: 16, width: 44, height: 44)
        nameLabel.frame = CGRect(x: 8, y: 68, width: 144, height: 22)
        quote.frame = CGRect(x: 4, y: 92, width: 152, height: 18)
        chartShine.frame = CGRect(x: 0, y: 120, width: 160, height: 40)
    }
}

private final class MarketChartView: UIView {
    private let fillImage = UIImageView()
    private let lineImage = UIImageView()
    private let fill = CAShapeLayer()
    private let line = CAShapeLayer()
    private var points: [Double] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.addSublayer(fill)
        layer.addSublayer(line)
        addSubview(fillImage)
        addSubview(lineImage)
        line.fillColor = nil
        line.lineWidth = 2
        line.lineCap = .round
        line.lineJoin = .round
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func configure(_ chart: MarketItemDisplayData.Chart?) {
        points = []
        fillImage.image = nil
        lineImage.image = nil
        switch chart {
        case .bundled(let fillName, let lineName, _):
            fillImage.image = .airBundle(fillName)
            lineImage.image = .airBundle(lineName)
        case .sparkline(let values, let color):
            points = values
            line.strokeColor = UIColor(rgb: color).cgColor
            fill.fillColor = UIColor(rgb: color).withAlphaComponent(0.09).cgColor
        case nil: break
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fillImage.frame = bounds
        lineImage.frame = CGRect(x: -0.75, y: 0, width: bounds.width + 1.5, height: 24.5)
        let path = UIBezierPath()
        if points.count >= 2 {
            for (index, value) in points.enumerated() {
                let point = CGPoint(x: CGFloat(index) / CGFloat(points.count - 1) * bounds.width, y: 2 + CGFloat(min(1, max(0, value))) * 20)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        line.path = path.cgPath
        if points.count >= 2 {
            path.addLine(to: CGPoint(x: bounds.width, y: bounds.height))
            path.addLine(to: CGPoint(x: 0, y: bounds.height))
            path.close()
        }
        fill.path = path.cgPath
        CATransaction.commit()
    }
}
