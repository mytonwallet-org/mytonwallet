import UIKit
import WalletContext

public class WAccentButton: WBaseButton, WThemedView {

    public static let defaultHeight: CGFloat = 60
    public static let cornerRadius: CGFloat = 12
    public static let imageHeight: CGFloat = 24
    public static let spacing: CGFloat = 5
    public static let font = UIFont.systemFont(ofSize: 12, weight: .regular)

    // MARK: - UI Components

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = WAccentButton.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        return stack
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let textLabel: UILabel = {
        let label = UILabel()
        label.font = WAccentButton.font
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Public Properties

    public var title: String? {
        get { textLabel.text }
        set { textLabel.text = newValue }
    }

    public var image: UIImage? {
        get { iconImageView.image }
        set { iconImageView.image = newValue?.withRenderingMode(.alwaysTemplate) }
    }

    // MARK: - Initialization

    public convenience init() {
        self.init(type: .custom)
        setup()
    }

    public convenience init(title: String?, image: UIImage?) {
        self.init()
        self.title = title
        self.image = image
    }

    // MARK: - Setup

    private func setup() {
        layer.cornerRadius = Self.cornerRadius

        addSubview(stackView)
        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(textLabel)

        NSLayoutConstraint.activate([
            // Height constraint with priority 800 to allow flexibility
            heightAnchor.constraint(equalToConstant: Self.defaultHeight).withPriority(.init(800)),

            // Image size
            iconImageView.heightAnchor.constraint(equalToConstant: Self.imageHeight),
            iconImageView.widthAnchor.constraint(equalToConstant: Self.imageHeight),

            // Center stack view
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateTheme()
    }

    // MARK: - Highlight

    public override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: isHighlighted ? 0.1 : 0.3, delay: 0, options: .allowUserInteraction) {
                self.stackView.alpha = self.isHighlighted ? 0.5 : 1.0
            }
        }
    }

    // MARK: - Theme

    public func updateTheme() {
        backgroundColor = WTheme.accentButton.background
        tintColor = WTheme.accentButton.tint
        iconImageView.tintColor = WTheme.accentButton.tint
        textLabel.textColor = WTheme.accentButton.tint
    }
}

