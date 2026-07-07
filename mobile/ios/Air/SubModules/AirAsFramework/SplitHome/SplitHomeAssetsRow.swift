import UIKit
import ContextMenuKit
import UIAssets
import UIComponents
import WalletCore
import WalletContext

@MainActor
protocol SplitHomeAssetsRowViewDelegate: AnyObject {
    var editingNavigator: NftsEditingNavigator? { get set }
}

@MainActor
final class SplitHomeAssetsRowView: UIView, UICollectionViewDelegate, UICollectionViewDragDelegate, UICollectionViewDropDelegate, WalletAssetsViewModelDelegate {
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
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = false
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
            cell.configure(
                tab: tab,
                hostedViewController: viewController,
                contextMenuProvider: self.tabContextMenuProviders?.provider(for: tab)
            )
            return cell
        }
    }

    private weak var parentViewController: UIViewController?
    private var accountSource: AccountSource?
    private var tabsViewModel: WalletAssetsViewModel?
    private var displayTabs: [DisplayAssetTab] = []
    private var tabViewControllers: [DisplayAssetTab: WSegmentedControllerContent] = [:]
    private var tokensVC: WalletTokensVC?
    private var nftsVC: NftsVC?
    private var nftsVCManager: NftsVCManager?
    private var tabContextMenuProviders: WalletAssetsTabContextMenuProviders?
    private var isReorderingTabs = false

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
            let nftsVCManager = NftsVCManager(tabsViewModel: tabsViewModel)
            nftsVCManager.restoreTabsOnReorderCanceling = true
            nftsVCManager.onStateChange = { [weak self] _, newState in
                self?.setIsReorderingTabs(newState.editingState == .reordering)
            }
            self.nftsVCManager = nftsVCManager
            tabContextMenuProviders = WalletAssetsTabContextMenuProviders(
                accountSource: accountSource,
                nftsVCManager: nftsVCManager,
                sourceViewProvider: { nil },
                onReorder: { [weak nftsVCManager] in
                    nftsVCManager?.startReordering()
                },
                onSelectTab: { [weak self] tab in
                    guard let self, let index = displayTabs.firstIndex(of: tab) else { return }
                    collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: true)
                },
                includesTokenLimitActions: false
            )
            delegate?.editingNavigator = nftsVCManager.editingNavigator
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
            updateVisibleNftAnimationPlayback(isActive: false)
        } else {
            delegate?.editingNavigator = nftsVCManager?.editingNavigator
            updateVisibleNftAnimationPlayback(isActive: true)
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
        updateVisibleNftAnimationPlayback(isActive: window != nil)
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
        let viewController: WSegmentedControllerContent

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
            (viewController as? NftAnimationPlaybackControlling)?.setNftAnimationPlaybackActive(false)
            viewController.willMove(toParent: nil)
            viewController.view.removeFromSuperview()
            viewController.removeFromParent()
            tabViewControllers.removeValue(forKey: tab)
        }
    }

    private func removeAllTabViewControllers() {
        for viewController in tabViewControllers.values {
            (viewController as? NftAnimationPlaybackControlling)?.setNftAnimationPlaybackActive(false)
            viewController.willMove(toParent: nil)
            viewController.view.removeFromSuperview()
            viewController.removeFromParent()
        }
        tabViewControllers.removeAll()
        tokensVC = nil
        nftsVC = nil
        tabContextMenuProviders = nil
        setIsReorderingTabs(false)
        displayTabs = []
    }

    func walletAssetModelDidChangeDisplayTabs(dueToAccountSwitch: Bool) {
        displayTabsChanged()
    }

    private func updateVisibleNftAnimationPlayback(isActive: Bool) {
        for case let cell as SplitHomeAssetSectionCollectionCell in collectionView.visibleCells {
            cell.setNftAnimationPlaybackActive(isActive)
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? SplitHomeAssetSectionCollectionCell)?.setNftAnimationPlaybackActive(window != nil)
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? SplitHomeAssetSectionCollectionCell)?.setNftAnimationPlaybackActive(false)
    }

    private func setIsReorderingTabs(_ isReordering: Bool) {
        guard isReorderingTabs != isReordering else { return }
        isReorderingTabs = isReordering
        collectionView.dragInteractionEnabled = isReordering
    }

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard isReorderingTabs, displayTabs.indices.contains(indexPath.item) else { return [] }
        let itemProvider = NSItemProvider(object: displayTabs[indexPath.item].debugDescription as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = displayTabs[indexPath.item]
        return [dragItem]
    }

    func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? SplitHomeAssetSectionCollectionCell else { return nil }
        return cell.dragPreviewParameters()
    }

    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        isReorderingTabs && session.localDragSession != nil
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, dropPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        self.collectionView(collectionView, dragPreviewParametersForItemAt: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard isReorderingTabs,
              let dropItem = coordinator.items.first,
              let sourceIndexPath = dropItem.sourceIndexPath,
              displayTabs.indices.contains(sourceIndexPath.item) else {
            return
        }

        let proposedDestinationIndex = coordinator.destinationIndexPath?.item ?? displayTabs.count
        let destinationIndex = min(max(proposedDestinationIndex, 0), displayTabs.count)
        let adjustedDestinationIndex = sourceIndexPath.item < destinationIndex ? destinationIndex - 1 : destinationIndex
        guard sourceIndexPath.item != adjustedDestinationIndex else { return }

        let movedTab = displayTabs.remove(at: sourceIndexPath.item)
        displayTabs.insert(movedTab, at: adjustedDestinationIndex)
        applySnapshot()

        let tabsViewModel = tabsViewModel
        let reorderedTabs = displayTabs
        Task {
            try? await tabsViewModel?.setOrder(displayTabs: reorderedTabs)
        }

        coordinator.drop(dropItem.dragItem, toItemAt: IndexPath(item: adjustedDestinationIndex, section: 0))
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

    private let titleView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 4
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        stackView.isAccessibilityElement = true
        stackView.isUserInteractionEnabled = true
        return stackView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let titleMenuImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage.airBundle("ArrowUpDownSmall").withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.alpha = 0.6
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        return imageView
    }()

    private var hostedViewController: UIViewController?
    private var titleMenuInteraction: ContextMenuInteraction?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        backgroundColor = .clear

        contentView.addSubview(cardView)
        contentView.addSubview(titleView)
        titleView.addArrangedSubview(titleLabel)
        titleView.addArrangedSubview(titleMenuImageView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.heightAnchor.constraint(equalToConstant: 404),

            titleView.topAnchor.constraint(equalTo: cardView.bottomAnchor, constant: 3),
            titleView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 8),
            titleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -8),
            titleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            titleMenuImageView.widthAnchor.constraint(equalToConstant: 6.3),
            titleMenuImageView.heightAnchor.constraint(equalToConstant: 12.6),
        ])

        updateTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        setNftAnimationPlaybackActive(false)
        hostedViewController = nil
        updateTitleMenu(contextMenuProvider: nil)
        cardView.subviews.forEach { $0.removeFromSuperview() }
    }

    func configure(
        tab: DisplayAssetTab,
        hostedViewController: UIViewController,
        contextMenuProvider: SegmentedControlContextMenuProvider?
    ) {
        titleLabel.text = makeTitle(for: tab)
        titleView.accessibilityLabel = titleLabel.text
        updateTitleMenu(contextMenuProvider: contextMenuProvider)

        if self.hostedViewController !== hostedViewController {
            setNftAnimationPlaybackActive(false)
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

    private func updateTitleMenu(contextMenuProvider: SegmentedControlContextMenuProvider?) {
        titleMenuInteraction?.detach()
        titleMenuInteraction = nil

        guard let contextMenuProvider else {
            titleMenuImageView.isHidden = true
            titleView.accessibilityTraits = [.staticText]
            return
        }

        titleMenuImageView.isHidden = false
        let interaction = ContextMenuInteraction(
            triggers: [.tap, .longPress],
            sourcePortal: ContextMenuSourcePortal(
                mask: .roundedAttachmentRect(cornerRadius: 12, cornerCurve: .continuous),
                showsBackdropCutout: true
            )
        ) { _ in
            contextMenuProvider.makeConfiguration()
        }
        interaction.attach(to: titleView)
        titleMenuInteraction = interaction
        titleView.accessibilityTraits = [.button]
    }

    func setNftAnimationPlaybackActive(_ isActive: Bool) {
        (hostedViewController as? NftAnimationPlaybackControlling)?.setNftAnimationPlaybackActive(isActive)
    }

    func dragPreviewParameters() -> UIDragPreviewParameters {
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: cardView.frame, cornerRadius: 26)
        return parameters
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
        titleMenuImageView.tintColor = UIColor.secondaryLabel
    }
}
