
import UIKit
import UIComponents
import WalletContext
import WalletCore

internal final class NftCell: UICollectionViewCell, ReorderableCell  {
    
    static func getCornerRadius(compactMode: Bool) -> CGFloat {
        compactMode ? 8 : 12
    }
        
    override var isHighlighted: Bool {
        didSet { updateHighlight() }
    }
    
    let imageContainerView = UIView()

    private lazy var wiggle = WiggleBehavior(view: contentView)
    private let backgroundView1 = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textStack = UIStackView()
    private let contentStack = UIStackView()
    private let imageView = NftViewStatic()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.backgroundColor = .clear

        backgroundView1.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundView1)

        imageContainerView.translatesAutoresizingMaskIntoConstraints = false
        imageContainerView.clipsToBounds = true
        contentView.addSubview(imageContainerView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageContainerView.addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = WTheme.secondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.numberOfLines = 1

        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.alignment = .fill
        contentStack.addArrangedSubview(imageContainerView)
        contentStack.addArrangedSubview(textStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            backgroundView1.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView1.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView1.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView1.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),
            
            imageContainerView.widthAnchor.constraint(equalTo: imageContainerView.heightAnchor),
        ])
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.kf.cancelDownloadTask()
        wiggle.prepareForReuse()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        wiggle.layoutDidChange()
    }

    func configure(nft: ApiNft?, compactMode: Bool, isMultichain: Bool) {
        let cornerRadius = NftCell.getCornerRadius(compactMode: compactMode)
        imageContainerView.layer.cornerRadius = cornerRadius
        imageContainerView.backgroundColor = WTheme.secondaryFill

        imageView.configure(nft: nft)

        if compactMode {
            textStack.isHidden = true
        } else {
            textStack.isHidden = false
            let resolvedNft = nft ?? ApiNft.ERROR
            titleLabel.text = resolvedNft.name?.nilIfEmpty ?? formatStartEndAddress(resolvedNft.address, prefix: 4, suffix: 4)
            let subtitle = resolvedNft.collectionName?.nilIfEmpty ?? lang("Standalone NFT")
            let attr = NSMutableAttributedString()
            if isMultichain {
                let image = NSTextAttachment(image: .airBundle("ActivityAddress-\(resolvedNft.chain.rawValue)"))
                image.bounds = .init(x: 0, y: -1.5, width: 13, height: 13)
                attr.append(NSAttributedString(attachment: image))
            }
            attr.append(NSAttributedString(string: subtitle, attributes: [
                .font: subtitleLabel.font ?? .systemFont(ofSize: 12),
                .foregroundColor: WTheme.secondaryLabel
            ]))
            subtitleLabel.attributedText = attr
        }
    }

    private func updateHighlight() {
        let transform: CGAffineTransform = isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95): .identity
        UIView.animate( withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { [weak self ] in
            self?.imageContainerView.transform = transform
        }
    }
    
    private func updateDraggingState() {
        let shouldShowText = !reorderingState.contains(.dragging)
        let textStack = self.textStack
        UIView.animate( withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
           textStack.alpha = shouldShowText ? 1 : 0
        }
    }

    // MARK: - ReorderableCell
    
    var reorderingState: ReorderableCellState = [] {
        didSet {
            wiggle.isWiggling = reorderingState.contains(.reordering)
            updateDraggingState()
        }
    }
}
