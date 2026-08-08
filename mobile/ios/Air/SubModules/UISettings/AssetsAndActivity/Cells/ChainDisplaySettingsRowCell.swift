import UIComponents
import UIKit
import WalletContext
import WalletCore

final class ChainDisplaySettingsRowCell: UICollectionViewListCell {
    private let iconStack = OverlappingIconStackView(iconSize: 36)
    private let chevron: UIImageView = {
        let imageView = UIImageView(image: UIImage.airBundle("RightArrowIcon").withRenderingMode(.alwaysTemplate))
        imageView.tintColor = .air.secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true

        iconStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconStack)
        contentView.addSubview(chevron)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            iconStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconStack.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -12),
            iconStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconStack.heightAnchor.constraint(equalToConstant: iconStack.iconSize),
            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        updateBackground(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(chains: [ApiChain]) {
        iconStack.configure(images: chains.map(\.image))
        accessibilityLabel = lang("Blockchains")
        accessibilityTraits = .button
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            updateBackground(animated: true)
        }
    }

    private func updateBackground(animated: Bool) {
        let changes = {
            var background = UIBackgroundConfiguration.listGroupedCell()
            background.backgroundColor = self.isHighlighted ? .air.highlight : .air.groupedItem
            self.backgroundConfiguration = background
        }
        if animated {
            UIView.animate(
                withDuration: isHighlighted ? 0.1 : 0.5,
                delay: 0,
                options: .allowUserInteraction,
                animations: changes
            )
        } else {
            changes()
        }
    }
}
