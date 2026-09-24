import UIKit
import UIComponents
import WalletContext
import WalletCore

final class MintCardBenefitsView: UIView {
    private let rows = [
        MintCardBenefitView(icon: "MintCardUniqueIcon", title: "Unique",
                            detail: "Get a card with unique background and personalized palette for wallet interface."),
        MintCardBenefitView(icon: "MintCardTransferableIcon", title: "Transferable",
                            detail: "Easily send your upgraded card to any of your friends."),
        MintCardBenefitView(icon: "MintCardTradableIcon", title: "Tradable",
                            detail: "Sell or auction your card on third-party NFT marketplaces."),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        for row in rows { addSubview(row) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ info: MintCardTypeInfo) {
        let isBlack = info.type == .black
        for row in rows {
            row.icon.tintColor = info.accentColor(for: traitCollection)
            row.title.textColor = isBlack ? .white : .label
            row.detail.textColor = isBlack ? UIColor.white.withAlphaComponent(0.75) : .air.secondaryLabel
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: rows.reduce(0) { $0 + $1.sizeThatFits(size).height })
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var y: CGFloat = 0
        for row in rows {
            let height = row.sizeThatFits(bounds.size).height
            row.frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
            y += height
        }
    }
}

private final class MintCardBenefitView: UIView {
    let icon = UIImageView()
    let title = UILabel()
    let detail = UILabel()

    init(icon: String, title: String, detail: String) {
        super.init(frame: .zero)
        self.icon.image = UIImage.airBundle(icon).withRenderingMode(.alwaysTemplate)
        self.icon.contentMode = .scaleAspectFit
        self.title.text = lang(title)
        self.title.applyTextStyle(.bodyEmphasized, scaling: .dynamic)
        self.detail.text = lang(detail)
        self.detail.applyTextStyle(.supporting, scaling: .dynamic)
        for label in [self.title, self.detail] { label.numberOfLines = 0 }
        for view in [self.icon, self.title, self.detail] { addSubview(view) }
        isAccessibilityElement = true
        accessibilityLabel = "\(lang(title)), \(lang(detail))"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let textSize = CGSize(width: max(0, size.width - 70), height: .greatestFiniteMagnitude)
        return CGSize(width: size.width, height: max(90, 15 + max(22, title.sizeThatFits(textSize).height) + 3 + detail.sizeThatFits(textSize).height + 14))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let textWidth = max(0, bounds.width - 70)
        let titleHeight = max(22, title.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        icon.frame = CGRect(x: rtl ? bounds.width - 46 : 14, y: 15, width: 32, height: 32)
        title.frame = CGRect(x: rtl ? 14 : 56, y: 15, width: textWidth, height: titleHeight)
        detail.frame = CGRect(x: title.frame.minX, y: title.frame.maxY + 3, width: textWidth, height: bounds.height - title.frame.maxY - 3 - 14)
    }
}
