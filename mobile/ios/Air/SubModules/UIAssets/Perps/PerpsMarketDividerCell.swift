import UIComponents
import UIKit
import WalletContext

final class PerpsMarketDividerCell: UICollectionViewCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        let title = UILabel()
        title.applyTextStyle(.body)
        title.text = lang("Futures Market")
        title.textColor = .air.secondaryLabel
        title.textAlignment = .center
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.8
        title.accessibilityTraits = .header
        let lines = (0..<2).map { _ in UIImageView(image: UIImage.airBundle("PerpsMarketDivider").withRenderingMode(.alwaysTemplate)) }
        for line in lines {
            line.tintColor = .air.secondaryLabel
            line.contentMode = .scaleToFill
            line.isAccessibilityElement = false
            line.widthAnchor.constraint(equalToConstant: 64.66).isActive = true
        }
        let row = UIStackView(arrangedSubviews: [lines[0], title, lines[1]])
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 22),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 22),
        ])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}
