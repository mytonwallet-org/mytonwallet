import UIKit
import UIComponents
import WalletCore
import WalletContext

final class EarnHistoryHeaderCell: UICollectionViewCell {

    private let titleLabel = UILabel()
    private let earnedLabel = UILabel()
    private let earnedContainer: WSensitiveData<UILabel> = .init(
        cols: 14,
        rows: 2,
        cellSize: 8,
        cornerRadius: 4,
        theme: .adaptive,
        alignment: .trailing
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .air.secondaryLabel
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        contentView.addSubview(titleLabel)

        earnedLabel.translatesAutoresizingMaskIntoConstraints = false
        earnedLabel.font = .systemFont(ofSize: 16, weight: .regular)
        earnedLabel.textColor = .air.secondaryLabel
        earnedLabel.textAlignment = .right
        earnedLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        earnedContainer.addContent(earnedLabel)
        earnedContainer.isTapToRevealEnabled = false
        contentView.addSubview(earnedContainer)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: earnedContainer.leadingAnchor, constant: -12),

            earnedContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            earnedContainer.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        earnedLabel.text = nil
        earnedContainer.isHidden = true
    }

    func configure(earnedAmount: TokenAmount?) {
        titleLabel.text = lang("History")

        guard let earnedAmount, earnedAmount.doubleValue > 0 else {
            earnedLabel.text = nil
            earnedContainer.isHidden = true
            return
        }

        earnedLabel.text = "\(lang("Earned")): \(earnedAmount.formatted(.defaultAdaptive))"
        earnedContainer.isHidden = false
        earnedContainer.resetReveal()
    }
}
