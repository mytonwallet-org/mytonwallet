import UIKit
import WalletContext

final class NftForSaleTagView: UIView {
    enum Style {
        case regular
        case compact

        var size: CGSize {
            switch self {
            case .regular:
                .init(width: 28, height: 32)
            case .compact:
                .init(width: 20, height: 23)
            }
        }

        var topOverlap: CGFloat {
            switch self {
            case .regular:
                2
            case .compact:
                1.5
            }
        }

        var trailingInset: CGFloat {
            switch self {
            case .regular:
                16
            case .compact:
                14
            }
        }
    }

    private let imageView = UIImageView(image: UIImage.airBundle("NftForSaleMark"))
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

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
        isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let widthConstraint = widthAnchor.constraint(equalToConstant: style.size.width)
        let heightConstraint = heightAnchor.constraint(equalToConstant: style.size.height)
        self.widthConstraint = widthConstraint
        self.heightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        applyStyle()
    }

    private func applyStyle() {
        widthConstraint?.constant = style.size.width
        heightConstraint?.constant = style.size.height
    }
}
