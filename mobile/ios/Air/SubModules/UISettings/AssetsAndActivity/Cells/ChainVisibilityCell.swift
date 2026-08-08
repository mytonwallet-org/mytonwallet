import UIKit
import UIComponents
import WalletContext
import WalletCore

final class ChainVisibilityCell: UICollectionViewListCell {
    private let reorderImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "line.3.horizontal"))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .tertiaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.applyTextStyle(.body)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var visibilitySwitch: UISwitch = {
        let control = UISwitch()
        control.addTarget(self, action: #selector(visibilityChanged), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private var onVisibilityChange: ((Bool) -> Void)?
    private var onReorderGesture: ((UILongPressGestureRecognizer) -> Void)?
    private var iconLeadingConstraint: NSLayoutConstraint!
    private var iconLeadingReorderingConstraint: NSLayoutConstraint!
    private var showsReorderControl = false
    private var hasConfigured = false

    private lazy var reorderGestureRecognizer: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(reorderGestureChanged))
        gesture.minimumPressDuration = 0.15
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(reorderImageView)
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(visibilitySwitch)
        contentView.addGestureRecognizer(reorderGestureRecognizer)
        reorderGestureRecognizer.delegate = self

        iconLeadingConstraint = iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        iconLeadingReorderingConstraint = iconImageView.leadingAnchor.constraint(
            equalTo: reorderImageView.trailingAnchor,
            constant: 12
        )
        iconLeadingConstraint.isActive = true

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            reorderImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            reorderImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            reorderImageView.widthAnchor.constraint(equalToConstant: 24),
            reorderImageView.heightAnchor.constraint(equalToConstant: 24),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalTo: iconImageView.widthAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: visibilitySwitch.leadingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            visibilitySwitch.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            visibilitySwitch.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            separatorLayoutGuide.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
        ])

        automaticallyUpdatesBackgroundConfiguration = false
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = .air.groupedItem
        backgroundConfiguration = background
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        chain: ApiChain,
        isVisible: Bool,
        isSwitchEnabled: Bool,
        showsReorderControl: Bool,
        usesAutomaticAppearance: Bool,
        onVisibilityChange: @escaping (Bool) -> Void,
        onReorderGesture: @escaping (UILongPressGestureRecognizer) -> Void
    ) {
        iconImageView.image = chain.image
        titleLabel.text = chain.title
        titleLabel.textColor = usesAutomaticAppearance ? .air.secondaryLabel : .label
        iconImageView.alpha = usesAutomaticAppearance ? 0.5 : 1
        visibilitySwitch.isOn = isVisible
        visibilitySwitch.isEnabled = isSwitchEnabled
        visibilitySwitch.accessibilityLabel = chain.title
        setShowsReorderControl(
            showsReorderControl,
            animated: hasConfigured && self.showsReorderControl != showsReorderControl && window != nil
        )
        self.onVisibilityChange = onVisibilityChange
        self.onReorderGesture = onReorderGesture
        hasConfigured = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        reorderImageView.layer.removeAllAnimations()
        contentView.layer.removeAllAnimations()
        onVisibilityChange = nil
        onReorderGesture = nil
        hasConfigured = false
    }

    private func setShowsReorderControl(_ showsReorderControl: Bool, animated: Bool) {
        self.showsReorderControl = showsReorderControl
        reorderGestureRecognizer.isEnabled = showsReorderControl
        contentView.layoutIfNeeded()
        reorderImageView.layer.removeAllAnimations()

        if showsReorderControl {
            reorderImageView.isHidden = false
            if animated {
                reorderImageView.alpha = 0
            }
        }

        NSLayoutConstraint.deactivate([iconLeadingConstraint, iconLeadingReorderingConstraint])
        (showsReorderControl ? iconLeadingReorderingConstraint : iconLeadingConstraint).isActive = true

        let changes = {
            self.reorderImageView.alpha = showsReorderControl ? 1 : 0
            self.contentView.layoutIfNeeded()
        }
        let completion = { (_: Bool) in
            if !self.showsReorderControl {
                self.reorderImageView.isHidden = true
            }
        }

        if animated {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: changes,
                completion: completion
            )
        } else {
            changes()
            completion(true)
        }
    }

    @objc private func visibilityChanged() {
        onVisibilityChange?(visibilitySwitch.isOn)
    }

    @objc private func reorderGestureChanged(_ gesture: UILongPressGestureRecognizer) {
        onReorderGesture?(gesture)
    }
}

extension ChainVisibilityCell: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === reorderGestureRecognizer, showsReorderControl else { return false }
        let location = touch.location(in: contentView)
        let spacing: CGFloat = 12
        return switch contentView.effectiveUserInterfaceLayoutDirection {
        case .leftToRight:
            location.x < visibilitySwitch.frame.minX - spacing
        case .rightToLeft:
            location.x > visibilitySwitch.frame.maxX + spacing
        @unknown default:
            false
        }
    }
}
