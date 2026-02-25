import UIKit
import WalletContext

public final class WActionTileButton: UIControl {
    public static let sideLength: CGFloat = 96

    public var onTap: (() -> Void)?

    public let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .tintColor
        return view
    }()

    public let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .label
        label.allowsDefaultTighteningForTruncation = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.heightAnchor.constraint(equalToConstant: 13).isActive = true
        return label
    }()

    private lazy var containerView: UIView = {
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            effect.tintColor = WColors.folderFill
            let view = UIVisualEffectView(effect: effect)
            view.cornerConfiguration = .corners(radius: 26)
            return view
        }

        let view = UIView()
        view.backgroundColor = WTheme.groupedItem
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private var containerContentView: UIView {
        if #available(iOS 26, iOSApplicationExtension 26, *),
           let effectView = containerView as? UIVisualEffectView {
            effectView.contentView
        } else {
            containerView
        }
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: Self.sideLength, height: Self.sideLength)
    }

    public init(title: String, image: UIImage?, onTap: (() -> Void)? = nil) {
        self.onTap = onTap
        super.init(frame: .zero)
        setup()
        configure(title: title, image: image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(title: String, image: UIImage?) {
        titleLabel.text = title
        imageView.image = image
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerContentView.addSubview(imageView)
        containerContentView.addSubview(titleLabel)
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.leadingAnchor.constraint(equalTo: containerContentView.leadingAnchor, constant: 12),
            imageView.topAnchor.constraint(equalTo: containerContentView.topAnchor, constant: 12),

            titleLabel.bottomAnchor.constraint(equalTo: containerContentView.bottomAnchor, constant: -12),
            titleLabel.leadingAnchor.constraint(equalTo: containerContentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerContentView.trailingAnchor, constant: -6),
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        containerView.addGestureRecognizer(tapGesture)
    }

    @objc private func didTap() {
        sendActions(for: .touchUpInside)
        onTap?()
    }
}
