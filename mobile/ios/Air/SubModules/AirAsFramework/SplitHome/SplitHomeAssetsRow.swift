import UIKit
import UIAssets
import UIComponents
import WalletCore
import WalletContext

@MainActor
protocol SplitHomeAssetsRowViewDelegate: AnyObject {
    var editingNavigator: NftsEditingNavigator? { get set }
}

@MainActor
final class SplitHomeAssetsRowView: UIView, UICollectionViewDelegate, WalletAssetsViewModelDelegate {
    static let itemSize = CGSize(width: 368, height: 424)
    static let rowHeight: CGFloat = 424
    static let itemSpacing: CGFloat = 16
    static let horizontalInset: CGFloat = S.insetSectionHorizontalMargin
    
    private enum Section: Hashable {
        case main
    }
    
    private enum Item: Hashable, Sendable {
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
    private var nftsVCManager: NftsVCManager?
    
    weak var delegate: (any SplitHomeAssetsRowViewDelegate)?
    
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
            tabsViewModel?.delegate = nil
            removeAllTabViewControllers()
            let tabsViewModel = WalletAssetsViewModel(accountSource: accountSource)
            tabsViewModel.delegate = self
            self.tabsViewModel = tabsViewModel
            nftsVCManager = NftsVCManager(tabsViewModel: tabsViewModel)
            delegate?.editingNavigator = nftsVCManager?.editingNavigator
            displayTabsChanged()
        } else {
            tabsViewModel?.delegate = self
            applySnapshot()
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        if window == nil {
            delegate?.editingNavigator = nil
        } else {
            delegate?.editingNavigator = nftsVCManager?.editingNavigator
        }
    }
    
    private func displayTabsChanged() {
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
        layout.sectionInset = UIEdgeInsets(top: 0, left: Self.horizontalInset, bottom: 0, right: Self.horizontalInset)
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
                viewController = nftsVC
            } else {
                let vc = NftsVC(accountSource: accountSource, manager: nftsVCManager, layoutMode: .compactLarge, filter: .none)
                nftsVC = vc
                viewController = vc
            }
        case .nftCollectionFilter(let filter):
            viewController = NftsVC(accountSource: accountSource, manager: nftsVCManager, layoutMode: .compactLarge, filter: filter)
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
        
    func walletAssetModelDidChangeDisplayTabs() {
        displayTabsChanged()
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
    
    fileprivate func updateTheme() {
        cardView.backgroundColor = .air.groupedItem
        titleLabel.textColor = UIColor.label
    }
}
