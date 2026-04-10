
import UIKit
import UIComponents
import WalletContext
import WalletCore

internal final class NftCell: UICollectionViewCell, ReorderableCell  {
    
    static func getCornerRadius(compactMode: Bool) -> CGFloat {
        compactMode ? 8 : 12
    }
        
    override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue {
                updateHighlight()
            }
        }
    }
    
    let imageContainerView = UIView()

    private lazy var wiggle = WiggleBehavior(view: contentView)
    private let backgroundView1 = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textStack = UIStackView()
    private let contentStack = UIStackView()
    private let imageView = NftViewStatic()
    private let noImagePlaceholderView = NftNoImagePlaceholderView()
    private let domainExpirationBannerView = NftDomainExpirationBannerView()
    private let forSaleTagView = NftForSaleTagView()
    private var forSaleTagTopConstraint: NSLayoutConstraint?
    private var forSaleTagTrailingConstraint: NSLayoutConstraint?
    private var selectionIcon: UIImageView?
    
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

        noImagePlaceholderView.translatesAutoresizingMaskIntoConstraints = false
        noImagePlaceholderView.isHidden = true
        imageContainerView.addSubview(noImagePlaceholderView)

        imageContainerView.addSubview(domainExpirationBannerView)

        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1

        subtitleLabel.textColor = .air.secondaryLabel
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

        imageContainerView.addSubview(forSaleTagView)
        let forSaleTagTopConstraint = forSaleTagView.topAnchor.constraint(equalTo: imageContainerView.topAnchor, constant: -NftForSaleTagView.Style.regular.topOverlap)
        let forSaleTagTrailingConstraint = forSaleTagView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor, constant: -NftForSaleTagView.Style.regular.trailingInset)
        self.forSaleTagTopConstraint = forSaleTagTopConstraint
        self.forSaleTagTrailingConstraint = forSaleTagTrailingConstraint

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

            noImagePlaceholderView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            noImagePlaceholderView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            noImagePlaceholderView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            noImagePlaceholderView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),

            domainExpirationBannerView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            domainExpirationBannerView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            domainExpirationBannerView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),

            forSaleTagTopConstraint,
            forSaleTagTrailingConstraint,

            imageContainerView.widthAnchor.constraint(equalTo: imageContainerView.heightAnchor),
        ])

        imageView.onStateChange = { [weak self] state in
            self?.applyImageState(state)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.reset()
        noImagePlaceholderView.isHidden = true
        imageView.isHidden = false
        domainExpirationBannerView.text = nil
        forSaleTagView.isHidden = true
        wiggle.prepareForReuse()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        wiggle.layoutDidChange()
    }

    private func configureSelection(isSelected: Bool?) {
        // Note that configure() could be called during collection reload/apply; nested UIView.animate is 0-duration there.
        // So we use deferred animation
        
        // remove icon is not in select mode
        guard let isSelected else {
            if let icon = selectionIcon {
                self.selectionIcon = nil
                DispatchQueue.main.async {
                    UIView.animate(withDuration: 0.25, animations: {
                        icon.alpha = 0
                    }) { _ in
                        icon.removeFromSuperview()
                    }
                }
            }
            return
        }

        func updateSelectionIconImage(_ icon: UIImageView) {
            icon.image = .airBundleOptional(isSelected ? "SelectedItem" : "UnselectedItem")
        }

        // add new icon in select mode
        guard let selectionIcon else {
            let newIcon = UIImageView()
            newIcon.translatesAutoresizingMaskIntoConstraints = false
            imageContainerView.addSubview(newIcon)
            NSLayoutConstraint.activate([
                newIcon.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor, constant: -6),
                newIcon.topAnchor.constraint(equalTo: imageContainerView.topAnchor, constant: 6),
                newIcon.widthAnchor.constraint(equalToConstant: 28),
                newIcon.heightAnchor.constraint(equalToConstant: 28),
            ])
            self.selectionIcon = newIcon
            newIcon.alpha = 0.0
            updateSelectionIconImage(newIcon)
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.25) {
                    newIcon.alpha = 1.0
                }
            }
            return
        }
        
        // update existing
        DispatchQueue.main.async {
            guard selectionIcon.superview != nil else { return }
            UIView.transition(with: selectionIcon, duration: 0.25, options: .transitionCrossDissolve) {
                updateSelectionIconImage(selectionIcon)
            }
        }
    }

    func configure(nft: ApiNft?, compactMode: Bool, domainExpirationText: String?, isSelected: Bool?) {
        let cornerRadius = NftCell.getCornerRadius(compactMode: compactMode)
        let forSaleTagStyle: NftForSaleTagView.Style = compactMode ? .compact : .regular
        imageContainerView.layer.cornerRadius = cornerRadius
        imageContainerView.backgroundColor = .air.secondaryFill
        noImagePlaceholderView.apply(style: compactMode ? .compact : .regular)

        imageView.configure(nft: nft)
        domainExpirationBannerView.style = compactMode ? .compact : .regular
        domainExpirationBannerView.text = domainExpirationText
        forSaleTagView.style = forSaleTagStyle
        forSaleTagTopConstraint?.constant = -forSaleTagStyle.topOverlap
        forSaleTagTrailingConstraint?.constant = -forSaleTagStyle.trailingInset
        forSaleTagView.isHidden = !(nft?.isOnSale ?? false)
        configureSelection(isSelected: isSelected)

        if compactMode {
            textStack.isHidden = true
        } else {
            textStack.isHidden = false
            let resolvedNft = nft ?? ApiNft.ERROR
            titleLabel.text = resolvedNft.name?.nilIfEmpty ?? formatStartEndAddress(resolvedNft.address, prefix: 4, suffix: 4)
            let subtitle = resolvedNft.collectionName?.nilIfEmpty ?? lang("Standalone NFT")
            let subtitleAttr = NSAttributedString(string: subtitle, attributes: [.font: UIFont.systemFont(ofSize: 12)])
            subtitleLabel.textColor = .air.secondaryLabel
            subtitleLabel.attributedText =  ChainIcon(resolvedNft.chain, style: .s12).prepended(to: subtitleAttr)
        }
    }

    private func applyImageState(_ state: NftViewStatic.ImageState) {
        switch state {
        case .loading, .loaded:
            noImagePlaceholderView.isHidden = true
            imageView.isHidden = false
        case .unavailable:
            noImagePlaceholderView.isHidden = false
            imageView.isHidden = true
        }
    }

    private func updateHighlight() {
        // Only for multiselect mode for now. All other states assumes long-tap-to-context-menu invocation (i.e. concurrent transforming)
        guard selectionIcon != nil else { return }
        
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
