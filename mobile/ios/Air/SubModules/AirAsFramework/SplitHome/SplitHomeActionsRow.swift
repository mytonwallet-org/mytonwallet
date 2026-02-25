import UIComponents
import UIKit
import WalletCore
import WalletContext
import SwiftNavigation

@MainActor
final class SplitHomeActionsRowCell: FirstRowCell {
    static let assetsTopSpacing: CGFloat = 24
    static let rowHeight: CGFloat = SplitHomeActionsRowView.rowHeight + assetsTopSpacing + SplitHomeAssetsRowView.rowHeight
    
    private let actionsRowView = SplitHomeActionsRowView()
    private let assetsRowView = SplitHomeAssetsRowView()
    
    // remove after conversion to collection view
    override class var layerClass: AnyClass { Layer.self }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        clipsToBounds = false
        actionsRowView.translatesAutoresizingMaskIntoConstraints = false
        assetsRowView.translatesAutoresizingMaskIntoConstraints = false
        
        let actionsHostView: UIView
        if #available(iOS 26, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = SplitHomeActionsRowView.itemSpacing * 0.5
            let glassContainerView = UIVisualEffectView(effect: effect)
            glassContainerView.translatesAutoresizingMaskIntoConstraints = false
            glassContainerView.contentView.addSubview(actionsRowView)
            NSLayoutConstraint.activate([
                actionsRowView.topAnchor.constraint(equalTo: glassContainerView.contentView.topAnchor),
                actionsRowView.leadingAnchor.constraint(equalTo: glassContainerView.contentView.leadingAnchor),
                actionsRowView.trailingAnchor.constraint(equalTo: glassContainerView.contentView.trailingAnchor),
                actionsRowView.bottomAnchor.constraint(equalTo: glassContainerView.contentView.bottomAnchor),
            ])
            actionsHostView = glassContainerView
        } else {
            actionsHostView = actionsRowView
        }
        
        contentView.addSubview(actionsHostView)
        contentView.addSubview(assetsRowView)
        
        NSLayoutConstraint.activate([
            actionsHostView.topAnchor.constraint(equalTo: contentView.topAnchor),
            actionsHostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            actionsHostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionsHostView.heightAnchor.constraint(equalToConstant: SplitHomeActionsRowView.rowHeight),
            
            assetsRowView.topAnchor.constraint(equalTo: actionsHostView.bottomAnchor, constant: Self.assetsTopSpacing),
            assetsRowView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            assetsRowView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            assetsRowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            assetsRowView.heightAnchor.constraint(equalToConstant: SplitHomeAssetsRowView.rowHeight),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureIfNeeded()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        configureIfNeeded()
    }
    
    private weak var configuredAccountContext: AccountContext?
    private weak var configuredParentViewController: SplitHomeVC?
    
    private func configureIfNeeded() {
        guard let splitHomeVC = splitHomeViewController else { return }
        assetsRowView.delegate = splitHomeVC
        let accountContext = splitHomeVC.splitHomeAccountContext
        if configuredAccountContext !== accountContext || configuredParentViewController !== splitHomeVC {
            configuredAccountContext = accountContext
            configuredParentViewController = splitHomeVC
            actionsRowView.configure(accountContext: accountContext)
            assetsRowView.configure(accountSource: accountContext.source, parentViewController: splitHomeVC)
        }
        assetsRowView.updateTheme()
    }
    
    var isAssetsReordering: Bool {
        assetsRowView.isReordering
    }
    
    func stopAssetsReordering(isCanceled: Bool) {
        assetsRowView.stopReordering(isCanceled: isCanceled)
    }
    
    private var splitHomeViewController: SplitHomeVC? {
        var responder: UIResponder? = self
        while let current = responder {
            if let splitHomeVC = current as? SplitHomeVC {
                return splitHomeVC
            }
            responder = current.next
        }
        return nil
    }
}

private class Layer: CALayer {
    override var masksToBounds: Bool {
        get { false }
        set {}
    }
}

@MainActor
final class SplitHomeActionsRowView: UIView, WThemedView, UICollectionViewDelegate {
    static let rowHeight: CGFloat = WActionTileButton.sideLength
    static let itemSpacing: CGFloat = 16
    
    private enum Section: Hashable {
        case main
    }
    
    private enum Item: Hashable {
        case action(SplitHomeActionItem)
    }
    
    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = false
        collectionView.alwaysBounceVertical = false
        collectionView.delaysContentTouches = false
        collectionView.clipsToBounds = false
        collectionView.register(SplitHomeActionCollectionCell.self, forCellWithReuseIdentifier: SplitHomeActionCollectionCell.reuseIdentifier)
        return collectionView
    }()
    
    private lazy var dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
        switch item {
        case .action(let action):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SplitHomeActionCollectionCell.reuseIdentifier, for: indexPath) as? SplitHomeActionCollectionCell else {
                return UICollectionViewCell()
            }
            cell.configure(item: action)
            return cell
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: Self.rowHeight),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private weak var accountContext: AccountContext?
    private var viewModel: SplitHomeActionsViewModel?
    
    func configure(accountContext: AccountContext) {
        guard self.accountContext !== accountContext || viewModel == nil else { return }
        self.accountContext = accountContext
        viewModel?.onItemsChanged = nil
        let viewModel = SplitHomeActionsViewModel(accountContext: accountContext)
        viewModel.onItemsChanged = { [weak self] items in
            self?.applyItems(items)
        }
        self.viewModel = viewModel
        applyItems(viewModel.items)
        updateTheme()
    }
    
    private func applyItems(_ items: [SplitHomeActionItem]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items.map(Item.action))
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    func updateTheme() {
        collectionView.backgroundColor = .clear
    }
    
    private func makeLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: WActionTileButton.sideLength, height: WActionTileButton.sideLength)
        layout.minimumInteritemSpacing = Self.itemSpacing
        layout.minimumLineSpacing = Self.itemSpacing
        layout.sectionInset = .zero
        return layout
    }
}

@MainActor
private final class SplitHomeActionsViewModel: WalletCoreData.EventsObserver {
    @AccountContext private var account: MAccount
    
    private(set) var items: [SplitHomeActionItem] = []
    var onItemsChanged: (([SplitHomeActionItem]) -> Void)?
    private var observeAccount: ObserveToken?
    
    init(accountContext: AccountContext) {
        self._account = accountContext
        WalletCoreData.add(eventObserver: self)
        observeAccount = observe { [weak self] in
            guard let self else { return }
            _ = account.supportsSwap
            _ = account.supportsEarn
            _ = account.supportsSend
            updateItems()
        }
    }
    
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .configChanged:
            updateItems()
        default:
            break
        }
    }
    
    private func updateItems() {
        _ = ConfigStore.shared.config
        let shouldShowBuy = !ConfigStore.shared.shouldRestrictSwapsAndOnRamp
        let shouldShowSell = !ConfigStore.shared.shouldRestrictSell
        
        var updatedItems: [SplitHomeActionItem]
        if account.isView {
            updatedItems = [.deposit]
            updatedItems.append(.scan)
        } else {
            updatedItems = [.deposit]
            if shouldShowBuy {
                updatedItems.append(.buy)
            }
            if account.supportsSend {
                updatedItems.append(.send)
            }
            if account.supportsSend, shouldShowSell {
                updatedItems.append(.sell)
            }
            if account.supportsSwap {
                updatedItems.append(.swap)
            }
            if account.supportsEarn {
                updatedItems.append(.earn)
            }
            updatedItems.append(.scan)
        }
        
        guard updatedItems != items else { return }
        items = updatedItems
        onItemsChanged?(updatedItems)
    }
}

@MainActor
private final class SplitHomeActionCollectionCell: UICollectionViewCell {
    static let reuseIdentifier = "SplitHomeActionCollectionCell"
    
    private var actionButton: WActionTileButton?
    private var item: SplitHomeActionItem?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(item: SplitHomeActionItem) {
        if actionButton == nil {
            let actionButton = WActionTileButton(title: item.title, image: item.image)
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(actionButton)
            NSLayoutConstraint.activate([
                actionButton.topAnchor.constraint(equalTo: contentView.topAnchor),
                actionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                actionButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
            self.actionButton = actionButton
        }

        guard self.item != item else { return }

        self.item = item
        actionButton?.configure(title: item.title, image: item.image)
        actionButton?.onTap = { [item] in
            item.perform()
        }
    }
}
