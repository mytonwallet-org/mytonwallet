import Kingfisher
import UIComponents
import UIKit
import WalletContext
import WalletCore

final class ExploreCategoryCell: UICollectionViewListCell {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let telegramView = UIImageView(image: UIImage.airBundle("TelegramLogo20").withRenderingMode(.alwaysTemplate))
    private let descriptionLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private let separator = UIView()
    private var openAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(site: ApiSite, openAction: @escaping () -> Void) {
        self.openAction = openAction
        iconView.kf.setImage(with: URL(string: site.icon))
        titleLabel.text = site.name
        descriptionLabel.text = site.description
        telegramView.isHidden = site.tgUrl == nil
        openButton.accessibilityLabel = "\(lang("Open")), \(site.name)"
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.kf.cancelDownloadTask()
        iconView.image = nil
        openAction = nil
    }

    private func setupViews() {
        accessibilityIdentifier = "explore_site_row"
        backgroundConfiguration = .clear()
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)

        iconView.contentMode = .scaleAspectFill
        iconView.layer.cornerRadius = 23
        iconView.layer.cornerCurve = .continuous
        iconView.clipsToBounds = true
        let iconContainer: UIView
        if #available(iOS 26, *), IOS_26_MODE_ENABLED {
            let glassView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glassView.cornerConfiguration = .corners(radius: 23)
            glassView.isUserInteractionEnabled = false
            glassView.contentView.addStretchedToBounds(subview: iconView)
            iconContainer = glassView
        } else {
            iconContainer = iconView
        }

        titleLabel.applyTextStyle(.body)
        titleLabel.textColor = .label
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        telegramView.contentMode = .scaleAspectFit
        telegramView.tintColor = .air.secondaryLabel.withAlphaComponent(0.5)
        telegramView.isAccessibilityElement = false
        let titleStack = UIStackView(arrangedSubviews: [titleLabel, telegramView])
        titleStack.spacing = 4
        titleStack.alignment = .center

        descriptionLabel.applyTextStyle(.footnote)
        descriptionLabel.textColor = .air.secondaryLabel

        var configuration = UIButton.Configuration.filled()
        configuration.title = lang("Open")
        configuration.baseForegroundColor = .tintColor
        configuration.baseBackgroundColor = .airBundle("ButtonBackground")
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = WTypography.uiFont(.calloutBold)
            return attributes
        }
        openButton.configuration = configuration
        openButton.addTarget(self, action: #selector(openSite), for: .touchUpInside)

        separator.backgroundColor = UIColor(light: "#C8C7CB", dark: "#3A3A3D")
        for subview in [iconContainer, titleStack, descriptionLabel, openButton, separator] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }
        let margins = contentView.layoutMarginsGuide
        let telegramWidth = telegramView.widthAnchor.constraint(equalToConstant: 18)
        telegramWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(equalToConstant: 114),
            iconContainer.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            iconContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            iconContainer.widthAnchor.constraint(equalToConstant: 88),
            iconContainer.heightAnchor.constraint(equalToConstant: 88),
            titleStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 14),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: margins.trailingAnchor),
            titleStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            telegramWidth,
            telegramView.heightAnchor.constraint(equalToConstant: 18),
            descriptionLabel.leadingAnchor.constraint(equalTo: titleStack.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            descriptionLabel.topAnchor.constraint(equalTo: titleStack.bottomAnchor, constant: 4),
            openButton.leadingAnchor.constraint(equalTo: titleStack.leadingAnchor),
            openButton.trailingAnchor.constraint(lessThanOrEqualTo: margins.trailingAnchor),
            openButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            separator.leadingAnchor.constraint(equalTo: titleStack.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)),
        ])
    }

    @objc private func openSite() {
        openAction?()
    }
}
