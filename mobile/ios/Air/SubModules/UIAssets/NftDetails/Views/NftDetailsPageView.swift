import ContextMenuKit
import UIKit
import WalletContext
import UIComponents

protocol NftDetailsPageViewDelegate: NftDetailsActionsDelegate {
    func pageDidRequestFullScreenPreview()
}

class NftDetailsPageView: UIView {
    let model: NftDetailsItemModel

    private weak var delegate: NftDetailsPageViewDelegate?

    private let stackView = UIStackView()
    private var headerHeightConstraint: NSLayoutConstraint!
    private var processedImageSubscription: NftDetailsItemModel.Subscription?
    private var cachedContentHeight: CGFloat?
    private var contentColor: NftDetailsContentPalette?
    private var isExpanded: Bool
    private var toolbarMenuInteractions: [ContextMenuInteraction] = []

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

        super.init(frame: .fromSize(width: layoutGeometry.width, height: .greatestFiniteMagnitude))

        clipsToBounds = false
                        
        // Imitates expanded image tap: real or background render picture
        do {
            let p =  UITapGestureRecognizer(target: self, action: #selector(handleTapForExpandedPreview))
            p.cancelsTouchesInView = false
            addGestureRecognizer(p)
        }
        
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.clipsToBounds = false
        stackView.addArrangedSubview(UIView()) // spacer
        addSubview(stackView)
        
        headerHeightConstraint = stackView.topAnchor.constraint(equalTo: topAnchor, constant: layoutGeometry.headerHeight(isExpanded: isExpanded))
        NSLayoutConstraint.activate([
            headerHeightConstraint,
            
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
            if let collection = item.collection, let config = delegate.ntfDetailsOnConfigureAction(forModel: model, action: .showCollection) {
                button.name = collection.name
                button.onTap = config.onTap
            } else {
                button.name = lang("Standalone NFT")
            }
            stackView.addArrangedSubview(button)
            stackView.setCustomSpacing(16, after: button)
        }
        
        // Toolbar
        do {
            var buttons: [WScalableButton] = []
            var menuInteractions: [ContextMenuInteraction] = []
            
            func add(_ action: NftDetailsItemModel.Action, _ title: String, _ imageName: String) {
                if let config = delegate.ntfDetailsOnConfigureAction(forModel: model, action: action) {
                    let button = WScalableButton(
                        title: title,
                        image: .airBundle(imageName),
                        style: .thinGlass,
                        onTap: config.onTap ?? {},
                    )
                    if let menuConfig = config.onMenuConfiguration {
                        let interaction = ContextMenuInteraction(
                            triggers: [.tap, .longPress],
                            longPressDuration: 0.25,
                            sourcePortal: ContextMenuSourcePortal(
                                mask: .roundedAttachmentRect(
                                    cornerRadius: WScalableButton.preferredCornerRadius,
                                    cornerCurve: .continuous
                                )
                            )
                        ) { _ in
                            menuConfig()
                        }
                        interaction.attach(to: button)
                        menuInteractions.append(interaction)
                    }
                    buttons.append(button)
                }
            }
            
            add(.wear, lang("Wear"), "WearIconBold" )
            add(.send, lang("Send"), "SendIconBold" )
            add(.share, lang("Share"), "ShareIconBold" )
            add(.more, lang("More"), "MoreIconBold")
            
            toolbarMenuInteractions = menuInteractions
            
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
            let tile = NftDetailsDomainTile()
            tile.text = tonDomain.expirationText
            if tonDomain.canRenew, let config = delegate.ntfDetailsOnConfigureAction(forModel: model, action: .renewDomain) {
                tile.showsRenewButton = true
                tile.onRenewTap = config.onTap
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
        } else {
            processedImageSubscription = nil
        }
    }

    @objc private func handleTapForExpandedPreview(_ gr: UITapGestureRecognizer) {
        var rect = bounds
        rect.size.height = rect.width
        if isExpanded, rect.contains(gr.location(in: self)) {
            delegate?.pageDidRequestFullScreenPreview()
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
        
    func expand(extraScrollDownHeight: CGFloat) {
        isExpanded = true
        layoutIfNeeded()
        updateHeaderHeight()
    }
    
    func collapse() {
        isExpanded = false
        updateHeaderHeight()
    }

    func updateWith(layoutGeometry: LayoutGeometry, isExpanded: Bool) {
        if self.layoutGeometry != layoutGeometry || self.isExpanded != isExpanded {
            
            self.layoutGeometry = layoutGeometry
            self.isExpanded = isExpanded
            
            updateHeaderHeight()
        }
    }
    
    func getFullHeight() -> CGFloat {
        return getContentHeight() + layoutGeometry.headerHeight(isExpanded: isExpanded)
    }

    private func getContentHeight() -> CGFloat {
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
}
