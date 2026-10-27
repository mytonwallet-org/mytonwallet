import ContextMenuKit
import UIKit
import WalletContext
import WalletCore
import UIComponents

protocol NftDetailsPageViewDelegate: NftDetailsActionsDelegate {
    func pageDidRequestFullScreenPreview()
}

class NftDetailsPageView: UIView {
    let model: NftDetailsItemModel

    private weak var delegate: NftDetailsPageViewDelegate?
    private let colorResolver: NftDetailsColorResolver

    private let stackView = UIStackView()
    private var atmosphereEndView: UIView?
    private var cachedAtmosphereHeight: CGFloat?
    private var headerHeightConstraint: NSLayoutConstraint!
    private var processedImageSubscription: NftDetailsItemModel.Subscription?
    private var cachedContentHeight: CGFloat?
    private var contentColor: NftDetailsContentPalette?
    private var isExpanded: Bool
    private var descriptionMenuInteraction: ContextMenuInteraction?

    struct LayoutGeometry: Equatable {
        let stackMargin: CGFloat = 16
        let expandedImageFrame: CGRect
        let collapsedHeight: CGFloat
        let width: CGFloat
        
        var expandedHeight: CGFloat { expandedImageFrame.maxY }
        func headerHeight(isExpanded: Bool) -> CGFloat { isExpanded ? expandedHeight : collapsedHeight }
        var stackWidth: CGFloat { width - (2 * stackMargin) }
    }

    private(set) var layoutGeometry: LayoutGeometry

    init(model: NftDetailsItemModel, colorResolver: NftDetailsColorResolver, layoutGeometry: LayoutGeometry, isExpanded: Bool, delegate: NftDetailsPageViewDelegate) {
        self.model = model
        self.colorResolver = colorResolver
        self.delegate = delegate
        self.layoutGeometry = layoutGeometry
        self.isExpanded = isExpanded

        super.init(frame: .fromSize(width: layoutGeometry.width, height: 0))

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
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: 0).isActive = true
        stackView.addArrangedSubview(spacer)
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
            titleLabel.applyTextStyle(.prominentTitle)
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
            atmosphereEndView = button
        }
        
        // Toolbar
        do {
            var buttons: [UIView] = []
            
            func add(_ action: NftDetailsItemModel.Action, _ title: String, _ imageName: String) {
                if let config = delegate.ntfDetailsOnConfigureAction(forModel: model, action: action) {
                    if #available(iOS 26, *) {
                        let button = WGlassActionButton(title: title, image: .airBundle(imageName), onTap: config.onTap)
                        if let menuConfig = config.onMenuConfiguration {
                            button.menu = UIMenu(children: [UIDeferredMenuElement.uncached { completion in
                                completion(Self.nativeMenuElements(from: menuConfig().rootPage))
                            }])
                            button.showsMenuAsPrimaryAction = true
                            button.preferredMenuElementOrder = .fixed
                        }
                        buttons.append(button)
                        return
                    }
                    let button = WScalableButton(
                        title: title,
                        image: .airBundle(imageName),
                        imageSize: CGSize(width: 26, height: 26),
                        style: .plain,
                        onTap: config.onTap ?? {},
                    )
                    if let menuConfig = config.onMenuConfiguration {
                        let menuButton = NftDetailsLegacyMenuButton(content: button)
                        menuButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { completion in
                            completion(Self.nativeMenuElements(from: menuConfig().rootPage))
                        }])
                        menuButton.showsMenuAsPrimaryAction = true
                        menuButton.preferredMenuElementOrder = .fixed
                        buttons.append(menuButton)
                        return
                    }
                    buttons.append(button)
                }
            }
            
            add(.wear, lang("Wear"), "WearIconBold" )
            add(.send, lang("Send"), "SendIconBold" )
            add(.share, lang("Share"), "ShareIconBold" )
            add(.more, lang("More"), "MoreIconBold")
            
            
            if !buttons.isEmpty {
                let toolbar = ButtonsToolbar()
                toolbar.beginUpdate()
                buttons.forEach { toolbar.addArrangedSubview($0) }
                toolbar.endUpdate()
                let toolbarContainer: UIView
                if #available(iOS 26, *) {
                    let effect = UIGlassContainerEffect()
                    // At rest the buttons remain distinct. Native press/hover expansion
                    // brings their glass surfaces within the shared merge distance.
                    effect.spacing = toolbar.spacing
                    let glass = UIVisualEffectView(effect: effect)
                    glass.clipsToBounds = false
                    toolbar.translatesAutoresizingMaskIntoConstraints = false
                    glass.contentView.addSubview(toolbar)
                    NSLayoutConstraint.activate([
                        toolbar.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
                        toolbar.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
                        toolbar.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
                        toolbar.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
                    ])
                    toolbarContainer = glass
                } else {
                    toolbarContainer = toolbar
                }
                stackView.addArrangedSubview(toolbarContainer)
                stackView.setCustomSpacing(26, after: toolbarContainer)
                self.atmosphereEndView = toolbarContainer
            }
        }
        
        // Description
        if let description = item.description?.nilIfEmpty {
            let tile = NftDetailsDescriptionTile()
            tile.titleText = lang("Description").lowercased()
            tile.bodyText = description
            if #available(iOS 26, *) {
                let interaction = ContextMenuInteraction(
                    triggers: [.longPress],
                    sourcePortal: ContextMenuSourcePortal(
                        mask: .roundedAttachmentRect(
                            cornerRadius: NftDetailsDescriptionTile.cornerRadius,
                            cornerCurve: .continuous
                        ),
                        showsBackdropCutout: true
                    )
                ) { [description] _ in
                    Self.makeDescriptionMenuConfiguration(description: description)
                }
                interaction.attach(to: tile)
                descriptionMenuInteraction = interaction
            } else {
                tile.addInteraction(UIContextMenuInteraction(delegate: self))
            }
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
            label.applyTextStyle(.bodyStrong)
            label.numberOfLines = 0
            label.contentPadding = .init(top: 0, left: grid.contentInsets.left, bottom: 0, right: grid.contentInsets.right)
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
        if containsExpandedPreview(at: gr.location(in: self)) {
            delegate?.pageDidRequestFullScreenPreview()
        }
    }

    func containsExpandedPreview(at point: CGPoint) -> Bool {
        guard isExpanded else { return false }
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NftDetailMainScrollView {
                let frame = NftDetailsHeroLayout.scrolledFrame(layoutGeometry.expandedImageFrame,
                    offsetY: scrollView.contentOffset.y)
                    .offsetBy(dx: scrollView.bounds.minX, dy: scrollView.bounds.minY)
                return convert(frame, from: scrollView).contains(point)
            }
            ancestor = view.superview
        }
        return layoutGeometry.expandedImageFrame.contains(point)
    }

    /// Preserve the existing action handlers and groups; UIKit owns the menu's
    /// material, positioning, selection gestures and transition from the button.
    static func nativeMenuElements(from page: ContextMenuPage) -> [UIMenuElement] {
        func image(_ icon: ContextMenuIcon?) -> UIImage? {
            guard case let .image(image, mode) = icon else { return nil }
            switch mode {
            case .automatic: return image
            case .template: return image.withRenderingMode(.alwaysTemplate)
            case .original: return image.withRenderingMode(.alwaysOriginal)
            }
        }
        var groups: [[UIMenuElement]] = [[]]
        for item in page.items {
            switch item {
            case .action(let action):
                var attributes: UIMenuElement.Attributes = []
                if action.role == .destructive { attributes.insert(.destructive) }
                if !action.isEnabled { attributes.insert(.disabled) }
                if !action.dismissesMenu { attributes.insert(.keepsMenuPresented) }
                let native = UIAction(title: action.title, image: image(action.icon),
                                      identifier: UIAction.Identifier(action.id), attributes: attributes) { _ in
                    action.handler?()
                }
                native.subtitle = action.subtitle
                groups[groups.count - 1].append(native)
            case .separator:
                if !groups[groups.count - 1].isEmpty { groups.append([]) }
            case .submenu(let submenu):
                guard submenu.isEnabled else {
                    groups[groups.count - 1].append(UIAction(title: submenu.title, image: image(submenu.icon), attributes: .disabled) { _ in })
                    continue
                }
                let child = UIMenu(title: submenu.title, image: image(submenu.icon),
                                   children: nativeMenuElements(from: submenu.makePage()))
                child.subtitle = submenu.subtitle
                groups[groups.count - 1].append(child)
            case .back, .custom:
                assertionFailure("NFT toolbar menus contain actions and submenus only")
            }
        }
        let nonempty = groups.filter { !$0.isEmpty }
        if nonempty.count == 1 { return nonempty[0] }
        return nonempty.map { UIMenu(options: .displayInline, children: $0) }
    }

    private static func makeDescriptionMenuConfiguration(description: String) -> ContextMenuConfiguration {
        ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(
                    ContextMenuAction(
                        title: lang("Copy Description"),
                        icon: .airBundle("SendCopy"),
                        handler: {
                            UIPasteboard.general.string = description
                            AppActions.showToast(icon: .animatedCopy, message: lang("Description Copied"))
                            Haptics.play(.lightTap)
                        }
                    )
                ),
            ]),
            backdrop: .untintedBlur(radius: 20, dimAlpha: 0.20),
            backdropTintColor: .black,
            preservesSourceAppearance: true,
            style: ContextMenuStyle(minWidth: 220.0, maxWidth: 280.0)
        )
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateContentColor()
        }
    }
    
    var atmosphereHeight: CGFloat {
        if let cachedAtmosphereHeight { return cachedAtmosphereHeight }
        var height: CGFloat = 0
        for child in stackView.arrangedSubviews {
            height += child.systemLayoutSizeFitting(
                CGSize(width: layoutGeometry.stackWidth, height: 0),
                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
            let spacing = stackView.customSpacing(after: child)
            height += spacing == UIStackView.spacingUseDefault ? stackView.spacing : spacing
            if child === atmosphereEndView { break }
        }
        cachedAtmosphereHeight = height
        return height
    }

    private func updateContentColor() {
        contentColor = colorResolver.contentPalette(for: model)
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
        
    func updateWith(layoutGeometry: LayoutGeometry, isExpanded: Bool) {
        if self.layoutGeometry != layoutGeometry || self.isExpanded != isExpanded {
            
            if self.layoutGeometry != layoutGeometry {
                cachedContentHeight = nil
                cachedAtmosphereHeight = nil
            }
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

// iOS 18 and earlier use UIKit's own menu panel, backdrop and presentation.
extension NftDetailsPageView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let description = model.item.description, !description.isEmpty else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: Self.nativeMenuElements(from: Self.makeDescriptionMenuConfiguration(description: description).rootPage))
        }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        descriptionPreview(for: interaction)
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        descriptionPreview(for: interaction)
    }

    private func descriptionPreview(for interaction: UIContextMenuInteraction) -> UITargetedPreview? {
        guard let source = interaction.view else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: source.bounds, cornerRadius: NftDetailsDescriptionTile.cornerRadius)
        return UITargetedPreview(view: source, parameters: parameters)
    }
}
