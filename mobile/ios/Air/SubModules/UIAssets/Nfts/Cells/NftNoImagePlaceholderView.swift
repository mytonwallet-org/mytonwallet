import UIKit
import WalletContext

final class NftNoImagePlaceholderView: UIView {

    enum Style {
        case regular
        case compact

        var imageSize: CGFloat {
            switch self {
            case .regular: 87
            case .compact: 52
            }
        }

        var spacing: CGFloat {
            switch self {
            case .regular: 10
            case .compact: 4
            }
        }

        var labelFont: UIFont {
            switch self {
            case .regular:
                .systemFont(ofSize: 20, weight: .bold)
            case .compact:
                .systemFont(ofSize: 12, weight: .bold)
            }
        }
    }

    private let stackView = UIStackView()
    private let imageView = UIImageView(image: UIImage.airBundle("NoNftImage").withRenderingMode(.alwaysTemplate))
    private let titleLabel = UILabel()

    private lazy var imageWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: Style.regular.imageSize)
    private lazy var imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: Style.regular.imageSize)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        apply(style: .regular)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(style: Style) {
        stackView.spacing = style.spacing
        imageWidthConstraint.constant = style.imageSize
        imageHeightConstraint.constant = style.imageSize
        titleLabel.font = style.labelFont
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        backgroundColor = .air.groupedBackground
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .air.secondaryLabel
        imageView.alpha = 0.5

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.text = lang("No Image")
        titleLabel.textColor = .air.secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.alpha = 0.5
        titleLabel.minimumScaleFactor = 0.8
        titleLabel.allowsDefaultTighteningForTruncation = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(titleLabel)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            imageWidthConstraint,
            imageHeightConstraint,
            
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }
}
