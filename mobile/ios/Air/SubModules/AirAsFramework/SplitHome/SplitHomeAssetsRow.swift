import UIKit
import UIAssets
import UIComponents
import WalletCore
import WalletContext

@MainActor
protocol SplitHomeAssetsRowViewDelegate: AnyObject {
    func splitHomeAssetsRowViewDidChangeReorderingState(_ view: SplitHomeAssetsRowView)
}

@MainActor
final class SplitHomeAssetsRowView: UIView, WThemedView, UICollectionViewDelegate, WalletAssetsViewModelDelegate, NftsViewControllerDelegate {
    static let itemSize = CGSize(width: 368, height: 424)
    static let rowHeight: CGFloat = 424
    static let itemSpacing: CGFloat = 16
    
    private enum Section: Hashable {
        case main
    }
    
    private enum Item: Hashable {
        case tab(DisplayAssetTab)
    }
    
    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.alwaysBounceVertical = false
        collectionView.delaysContentTouches = false
        collectionView.clipsToBounds = false
        collectionView.register(SplitHomeAssetSectionCollectionCell.self, forCellWithReuseIdentifier: SplitHomeAssetSectionCollectionCell.reuseIdentifier)
        return collectionView
    }()
    
    private lazy var dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
        switch item {
        case .tab(let tab):
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SplitHomeAssetSectionCollectionCell.reuseIdentifier, for: indexPath) as? SplitHomeAssetSectionCollectionCell else {
                return UICollectionViewCell()
            }
            guard let parentViewController = self.parentViewController, let viewController = self.makeViewController(for: tab, parentViewController: parentViewController) else {
                return cell
            }
            cell.configure(tab: tab, hostedViewController: viewController)
            return cell
        }
    }
    
    private weak var parentViewController: UIViewController?
    private var accountSource: AccountSource?
    private var tabsViewModel: WalletAssetsViewModel?
    private var displayTabs: [DisplayAssetTab] = []
    private var tabViewControllers: [DisplayAssetTab: (UIViewController & WSegmentedControllerContent)] = [:]
    private var tokensVC: WalletTokensVC?
    private var nftsVC: NftsVC?
    weak var delegate: (any SplitHomeAssetsRowViewDelegate)?
    private var _isReordering = false
    
    var isReordering: Bool { _isReordering }
    
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
    
    func configure(accountSource: AccountSource, parentViewController: UIViewController) {
        self.parentViewController = parentViewController
        
        if self.accountSource != accountSource || tabsViewModel == nil {
            self.accountSource = accountSource
            _isReordering = false
            tabsViewModel?.delegate = nil
            removeAllTabViewControllers()
            let tabsViewModel = WalletAssetsViewModel(accountSource: accountSource)
            tabsViewModel.delegate = self
            self.tabsViewModel = tabsViewModel
            displayTabsChanged()
        } else {
            tabsViewModel?.delegate = self
            applySnapshot()
        }
        delegate?.splitHomeAssetsRowViewDidChangeReorderingState(self)
    }
    
    func stopReordering(isCanceled: Bool) {
        tabsViewModel?.stopReordering(isCanceled: isCanceled)
    }
    
    func displayTabsChanged() {
        displayTabs = tabsViewModel?.displayTabs ?? []
        removeMissingTabViewControllers()
        applySnapshot()
    }
    
    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(displayTabs.map(Item.tab))
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    func updateTheme() {
        collectionView.backgroundColor = .clear
        for case let cell as SplitHomeAssetSectionCollectionCell in collectionView.visibleCells {
            cell.updateTheme()
        }
    }
    
    private func makeLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = Self.itemSize
        layout.minimumInteritemSpacing = Self.itemSpacing
        layout.minimumLineSpacing = Self.itemSpacing
        layout.sectionInset = .zero
        return layout
    }
    
    private func makeViewController(for tab: DisplayAssetTab, parentViewController: UIViewController) -> (UIViewController & WSegmentedControllerContent)? {
        if let existing = tabViewControllers[tab] {
            return existing
        }
        
        guard let accountSource else { return nil }
        let viewController: (UIViewController & WSegmentedControllerContent)
        
        switch tab {
        case .tokens:
            if let tokensVC {
                viewController = tokensVC
            } else {
                let vc = WalletTokensVC(accountSource: accountSource, mode: .compactLarge)
                tokensVC = vc
                viewController = vc
            }
        case .nfts:
            if let nftsVC {
                nftsVC.delegate = self
                viewController = nftsVC
            } else {
                let vc = NftsVC(accountSource: accountSource, mode: .compactLarge, filter: .none)
                vc.delegate = self
                nftsVC = vc
                viewController = vc
            }
        case .nftCollectionFilter(let filter):
            let vc = NftsVC(accountSource: accountSource, mode: .compactLarge, filter: filter)
            vc.delegate = self
            viewController = vc
        }
        
        if let nftsViewController = viewController as? NftsVC, _isReordering {
            nftsViewController.startReordering()
        }
        
        if viewController.parent == nil {
            parentViewController.addChild(viewController)
            _ = viewController.view
            viewController.didMove(toParent: parentViewController)
        }
        
        tabViewControllers[tab] = viewController
        return viewController
    }
    
    private func removeMissingTabViewControllers() {
        let tabsToKeep = Set(displayTabs)
        let tabsToRemove = tabViewControllers.keys.filter { !tabsToKeep.contains($0) }
        for tab in tabsToRemove {
            guard let viewController = tabViewControllers[tab] else { continue }
            viewController.willMove(toParent: nil)
            viewController.view.removeFromSuperview()
            viewController.removeFromParent()
            tabViewControllers.removeValue(forKey: tab)
        }
    }
    
    private func removeAllTabViewControllers() {
        for viewController in tabViewControllers.values {
            viewController.willMove(toParent: nil)
            viewController.view.removeFromSuperview()
            viewController.removeFromParent()
        }
        tabViewControllers.removeAll()
        tokensVC = nil
        nftsVC = nil
        displayTabs = []
    }
    
    private func forEachNftsVC(_ body: (NftsVC) -> Void) {
        var processedIds = Set<ObjectIdentifier>()
        
        if let nftsVC {
            processedIds.insert(ObjectIdentifier(nftsVC))
            body(nftsVC)
        }
        
        for viewController in tabViewControllers.values {
            guard let nftsVC = viewController as? NftsVC else { continue }
            let id = ObjectIdentifier(nftsVC)
            guard processedIds.insert(id).inserted else { continue }
            body(nftsVC)
        }
    }
    
    func walletAssetModelDidChangeDisplayTabs() {
        displayTabsChanged()
    }
    
    func walletAssetModelDidStartReordering() {
        _isReordering = true
        forEachNftsVC {
            $0.startReordering()
        }
        delegate?.splitHomeAssetsRowViewDidChangeReorderingState(self)
    }
    
    func walletAssetModelDidStopReordering(isCanceled: Bool) {
        _isReordering = false
        forEachNftsVC {
            $0.stopReordering(isCanceled: isCanceled)
        }
        delegate?.splitHomeAssetsRowViewDidChangeReorderingState(self)
    }
    
    func nftsViewControllerDidChangeReorderingState(_ vc: NftsVC) {
    }
    
    func nftsViewControllerRequestReordering(_ vc: NftsVC) {
        tabsViewModel?.startOrdering()
    }
}

@MainActor
private final class SplitHomeAssetSectionCollectionCell: UICollectionViewCell {
    static let reuseIdentifier = "SplitHomeAssetSectionCollectionCell"
    
    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 26
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textAlignment = .center
        return label
    }()
    
    private var hostedViewController: UIViewController?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        backgroundColor = .clear
        
        contentView.addSubview(cardView)
        contentView.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.heightAnchor.constraint(equalToConstant: 404),
            
            titleLabel.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        
        updateTheme()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        hostedViewController = nil
        cardView.subviews.forEach { $0.removeFromSuperview() }
    }
    
    func configure(tab: DisplayAssetTab, hostedViewController: UIViewController) {
        titleLabel.text = makeTitle(for: tab)
        
        if self.hostedViewController !== hostedViewController {
            self.hostedViewController = hostedViewController
            cardView.subviews.forEach { $0.removeFromSuperview() }
            let hostedView = hostedViewController.view!
            hostedView.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview(hostedView)
            NSLayoutConstraint.activate([
                hostedView.topAnchor.constraint(equalTo: cardView.topAnchor),
                hostedView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
                hostedView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
                hostedView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            ])
        }
        
        updateTheme()
    }
    
    private func makeTitle(for tab: DisplayAssetTab) -> String {
        switch tab {
        case .tokens:
            return lang("Assets")
        case .nfts:
            return lang("Collectibles")
        case .nftCollectionFilter(let filter):
            return filter.displayTitle
        }
    }
    
    func updateTheme() {
        cardView.backgroundColor = WTheme.groupedItem
        titleLabel.textColor = WTheme.primaryLabel
    }
}
