import UIKit
import WalletContext
import UIComponents

protocol NftDetailsPageViewDelegate: NftDetailsActionsDelegate {
    func pageDidRequestFullScreenPreview(forModel model: NftDetailsItemModel, view: UIView)
}

class NftDetailsPageView: UIView {
    let model: NftDetailsItemModel

    private weak var delegate: NftDetailsPageViewDelegate?

    private let stackView = UIStackView()
    
    private let header = UIView()
    private var headerHeightConstraint: NSLayoutConstraint!
    
    private let preview: NftDetailsItemPreview
    private var previewBottomConstraint: NSLayoutConstraint!
    private var previewWidthConstraint: NSLayoutConstraint!
    private var previewHeightConstraint: NSLayoutConstraint!
    
    private var processedImageSubscription: NftDetailsItemModel.Subscription?
    private var cachedContentHeight: CGFloat?
    private var contentColor: NftDetailsContentPalette?
    private var isExpanded: Bool

    struct LayoutGeometry: Equatable {
        let stackMargin: CGFloat = 16
        let expandedHeight: CGFloat
        let collapsedHeight: CGFloat
        let width: CGFloat
        
        func headerHeight(isExpanded: Bool) -> CGFloat { isExpanded ? expandedHeight : collapsedHeight }
        var stackWidth: CGFloat { width - (2 * stackMargin) }
    }

    private(set) var layoutGeometry: LayoutGeometry
    
    init(model: NftDetailsItemModel, layoutGeometry: LayoutGeometry, isExpanded: Bool, delegate: NftDetailsPageViewDelegate) {
        self.model = model
        self.delegate = delegate
        self.layoutGeometry = layoutGeometry
        self.isExpanded = isExpanded
        self.preview = NftDetailsItemPreview(model: model)

        super.init(frame: .fromSize(width: layoutGeometry.width, height: .greatestFiniteMagnitude))

        clipsToBounds = false

        preview.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(preview)
        
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.clipsToBounds = false
        stackView.addArrangedSubview(UIView()) // spacer
        addSubview(stackView)
        
        headerHeightConstraint = header.heightAnchor.constraint(equalToConstant: layoutGeometry.headerHeight(isExpanded: isExpanded))
        previewHeightConstraint = preview.heightAnchor.constraint(equalToConstant: 100)
        previewWidthConstraint = preview.widthAnchor.constraint(equalToConstant: 100)
        previewBottomConstraint = preview.bottomAnchor.constraint(equalTo: header.bottomAnchor)
        NSLayoutConstraint.activate([
            preview.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            previewHeightConstraint,
            previewWidthConstraint,
            previewBottomConstraint,
            
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerHeightConstraint,
            
            stackView.topAnchor.constraint(equalTo: header.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: layoutGeometry.stackMargin),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -layoutGeometry.stackMargin),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: layoutGeometry.width)
        ])
        
        let item = model.item

        // Title
        do {
            let titleLabel = NftDetailsLabel()
            titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
            titleLabel.text = item.name
            titleLabel.numberOfLines = 0
            titleLabel.textAlignment = .center
            stackView.addArrangedSubview(titleLabel)
            stackView.setCustomSpacing(0, after: titleLabel)
        }

        // Collection
        do {
            let button = NftDetailsCollectionButton()
            if let collection = item.collection {
                button.name = collection.name
                button.onTap = { [weak self] in
                    self?.delegate?.nftDetailsOnShowCollection(forModel: model)
                }
            } else {
                button.name = lang("Standalone NFT")
            }
            stackView.addArrangedSubview(button)
            stackView.setCustomSpacing(16, after: button)
        }
        
        // Toolbar
        do {
            var buttons: [WScalableButton] = []
            for action in NftDetailsItemModel.Action.allCases {
                guard let config = delegate.ntfDetailsOnConfigureToolbarButton(forModel: model, action: action) else {
                    continue
                }
                
                let title: String
                let image: UIImage
                switch action {
                case .send:
                    title = lang("Send")
                    image = .airBundle("SendIconBold" )
                case .wear:
                    title = lang("Wear")
                    image = .airBundle("WearIconBold" )
                case .share:
                    title = lang("Share")
                    image = .airBundle("ShareIconBold" )
                case .more:
                    title = lang("More")
                    image = .airBundle("MoreIconBold" )
                }
                
                let button = WScalableButton(title: title, image: image, style: .thinGlass, onTap: config.onTap ?? { }, )
                if let menuConfig = config.onMenuConfiguration {
                    button.attachMenu(presentOnTap: true, makeConfig: menuConfig)
                }
                
                buttons.append(button)
            }
            if !buttons.isEmpty {
                let toolbar = ButtonsToolbar()
                buttons.forEach { toolbar.addArrangedSubview($0) }
                stackView.addArrangedSubview(toolbar)
                stackView.setCustomSpacing(26, after: toolbar)
            }
        }
        
        // Description
        if let description = item.description?.nilIfEmpty {
            let tile = NftDetailsDescriptionTile()
            tile.titleText = lang("Description").lowercased()
            tile.bodyText = description
            stackView.addArrangedSubview(tile)
            stackView.setCustomSpacing(28, after: tile)
        }
        
        // Domain
        if let tonDomain = item.tonDomain {
            let tile = NftDetailsDomanTile()
            tile.text = tonDomain.expirationText
            if tonDomain.canRenew {
                tile.showsRenewButton = true
                tile.onRenewTap = { [weak self] in
                    self?.delegate?.nftDetailsOnRenewDomain(forModel: model)
                }
            } else {
                tile.showsRenewButton = false
            }
            stackView.addArrangedSubview(tile)
            stackView.setCustomSpacing(20, after: tile)
        }
        
        // Attributes
        if let attributes = item.attributes, !attributes.isEmpty {
            let grid = NftDetailsAttributesGrid(width: layoutGeometry.stackWidth, attributes: attributes)

            let label = NftDetailsLabel()
            label.text = lang("Attributes")
            label.font = .systemFont(ofSize: 17, weight: .semibold)
            label.numberOfLines = 0
            label.contentPadding = .init(top: 0, left: grid.contentInsets.left, bottom: 0, right: 0)
            stackView.addArrangedSubview(label)
            stackView.setCustomSpacing(8, after: label)
            
            stackView.addArrangedSubview(grid)
        }
        
        if (isExpanded) {
            updateExpandedPreview(extraScrollDownHeight: 0)
        } else {
            updateCollapsedPreview()
        }
        
        header.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handlePreviewTap)))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        if superview != nil {
            processedImageSubscription = .init(model: model, event: .processedImageUpdated, tag: "Page/Color") { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.updateContentColor()
                }
            }
            updateContentColor()
            preview.isSubscribed = true
        } else {
            processedImageSubscription = nil
            preview.isSubscribed = false
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateContentColor()
        }
    }
    
    private func updateContentColor() {
        let baseColor: UIColor?
        if case .loaded(let processed) = model.processedImageState { baseColor = processed.baseColor } else { baseColor = nil }
        let c = baseColor ?? NftDetailsContentPalette.defaultBackgroundColor.resolvedColor(with: traitCollection)
        if c.isLightColor {
            contentColor = .init(
                baseColor: .black,
                subtleBackgroundColor: .black.withAlphaComponent(0.04),
                edgeColor: .white.withAlphaComponent(0.4),
                secondaryTextColor: .black.withAlphaComponent(0.75),
                highlightColor: .black.withAlphaComponent(0.2),
            )
        } else {
            contentColor = .init(
                baseColor: .white,
                subtleBackgroundColor: .white.withAlphaComponent(0.06),
                edgeColor: .white.withAlphaComponent(0.3),
                secondaryTextColor: .white.withAlphaComponent(0.75),
                highlightColor: .white.withAlphaComponent(0.6),
            )
        }
        propagateContentColor()
    }
    
    private func propagateContentColor() {
        guard let contentColor else { return }
        func visit(_ view: UIView) {
            if let consumer = view as? NftDetailsContentColorConsumer {
                if consumer.applyContentColorPalette(contentColor) == false {
                    return
                }
            }
            view.subviews.forEach { visit($0) }
        }
        subviews.forEach { visit($0) }
    }
    
    private func updateHeaderHeight() {
        headerHeightConstraint.constant = layoutGeometry.headerHeight(isExpanded: isExpanded)
    }
    
    func setPreviewHidden(_ isHidden: Bool) {
        preview.isHidden = isHidden
    }
    
    func playLottieIfPossible() {
        preview.playLottieIfPossible()
    }
    
    func expandToFullScreenPreview() {
        guard isExpanded else {
            assertionFailure()
            return
        }
        delegate?.pageDidRequestFullScreenPreview(forModel: model, view: preview)
    }

    func expand(extraScrollDownHeight: CGFloat, previewStartFrame: CGRect) {
        isExpanded = true
        
        // Set initial (small) preview frame, exactly at the same place where cover flow item is located
        let startFrame = header.convert(previewStartFrame, from: nil)
        previewBottomConstraint.constant = startFrame.maxY - header.frame.height
        previewWidthConstraint.constant = startFrame.width
        previewHeightConstraint.constant = startFrame.height

        layoutIfNeeded()
        
        // Setup destination constraint values. They will be driven by outer animation
        updateHeaderHeight()
        updateExpandedPreview(extraScrollDownHeight: extraScrollDownHeight)
    }
    
    func commitExpansion() {
        preview.playLottieIfPossible()
    }

    func collapse(previewEndFrame: CGRect) {
        isExpanded = false

        let endFrame = header.convert(previewEndFrame, from: nil)
        previewBottomConstraint.constant = endFrame.maxY - layoutGeometry.headerHeight(isExpanded: false)
        previewWidthConstraint.constant = endFrame.width
        previewHeightConstraint.constant = endFrame.height
        updateHeaderHeight()
    }

    func commitCollapsion() {
        updateCollapsedPreview()
    }
    
    func updateExpandedPreview(extraScrollDownHeight: CGFloat) {
        assert(isExpanded)
        
        let size = layoutGeometry.headerHeight(isExpanded: true) + max(extraScrollDownHeight, 0)
        previewHeightConstraint.constant = size
        previewWidthConstraint.constant = size
        previewBottomConstraint.constant = 0
        
        preview.alpha = 1.0
    }
    
    private func updateCollapsedPreview() {
        preview.alpha = 0.0
    }

    func updateWith(layoutGeometry: LayoutGeometry, isExpanded: Bool) {
        if self.layoutGeometry != layoutGeometry || self.isExpanded != isExpanded {
            
            self.layoutGeometry = layoutGeometry
            self.isExpanded = isExpanded
            
            updateHeaderHeight()
            if (isExpanded) {
                updateExpandedPreview(extraScrollDownHeight: 0)
            } else {
                updateCollapsedPreview()
            }
        }
    }
    
    func getFullHeight() -> CGFloat {
        return getContentHeight() + layoutGeometry.headerHeight(isExpanded: isExpanded)
    }

    func getContentHeight() -> CGFloat {
        if let cachedContentHeight {
            return cachedContentHeight
        }
        
        stackView.layoutIfNeeded()
        let stackSize = stackView.systemLayoutSizeFitting(
            CGSize(width: layoutGeometry.stackWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        cachedContentHeight = stackSize.height
        return stackSize.height
    }

    @objc private func handlePreviewTap() {
        expandToFullScreenPreview()
    }
}
