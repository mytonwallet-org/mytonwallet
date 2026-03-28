import UIKit

final class NftDomainExpirationBannerView: UIView {
    enum Style {
        case regular
        case compact

        var font: UIFont {
            switch self {
            case .regular:
                .systemFont(ofSize: 12, weight: .semibold)
            case .compact:
                .systemFont(ofSize: 9, weight: .semibold)
            }
        }

        var height: CGFloat {
            switch self {
            case .regular:
                24
            case .compact:
                18
            }
        }
    }

    private let textLabel = UILabel()
    private var heightConstraint: NSLayoutConstraint?

    var text: String? {
        didSet {
            textLabel.text = text
            isHidden = text == nil
        }
    }

    var style: Style = .regular {
        didSet {
            applyStyle()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        isHidden = true
        backgroundColor = .systemRed
        translatesAutoresizingMaskIntoConstraints = false

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.textColor = .white
        textLabel.textAlignment = .center
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.allowsDefaultTighteningForTruncation = true
        addSubview(textLabel)

        let heightConstraint = heightAnchor.constraint(equalToConstant: style.height)
        self.heightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            heightConstraint,
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        applyStyle()
    }

    private func applyStyle() {
        textLabel.font = style.font
        heightConstraint?.constant = style.height
    }
}
