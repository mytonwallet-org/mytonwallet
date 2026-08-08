
import UIKit
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

@MainActor
public class HiddenNftsVC: WViewController, Sendable {
    
    enum Section {
        case hiddenByUser
        case unverified
        case likelyScam
        
        var localizedTitle: String {
            switch self {
            case .hiddenByUser: lang("Hidden By Me")
            case .unverified: lang("Unverified")
            case .likelyScam: lang("Probably Scam")
            }
        }
    }
    enum Row: Hashable {
        case hiddenByUser(String)
        case unverified(String)
        case likelyScam(String)
        
        var stringValue: String {
            switch self {
            case .hiddenByUser(let string), .unverified(let string), .likelyScam(let string):
                return string
            }
        }
    }
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = lang("No hidden NFTs.")
        label.applyTextStyle(.body)
        label.textColor = .air.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private let onUnhideNft: ((String) -> Void)?

    public init(onUnhideNft: ((String) -> Void)? = nil) {
        self.onUnhideNft = onUnhideNft
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        super.loadView()
        setupViews()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        addCloseNavigationItemIfNeeded()
        WalletCoreData.add(eventObserver: self)
    }
    
    private var cellStates: [String: HiddenNftCellViewModel] = [:]
    /// Append-only ordered row list. New items are prepended to their section; existing items never move or leave.
    private var trackedRows: [Row] = []
    
    private func setupViews() {
        title = lang("Hidden NFTs")
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.allowsSelection = false
        collectionView.alwaysBounceVertical = true
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        collectionView.clipsToBounds = false
        collectionView.delaysContentTouches = false
        view.addSubview(emptyStateLabel)
        NSLayoutConstraint.activate([
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48)
        ])

        let hiddenByUserRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, itemIdentifier in
            guard let self, let state = cellStates[itemIdentifier] else { return }
            let onUnhideNft = self.onUnhideNft
            cell.configurationUpdateHandler = { cell, _ in
                cell.contentConfiguration = UIHostingConfiguration {
                    HiddenByUserCell(state: state, onPreviewTap: { [weak self] in
                        self?.openNftDetails(nftId: state.displayNft.id)
                    }, action: { isHiddenByUser in
                        if let accountId = AccountStore.accountId {
                            NftStore.setHiddenByUser(accountId: accountId, nft: state.displayNft.nft, isHidden: isHiddenByUser)
                        }
                        if !isHiddenByUser { onUnhideNft?(state.displayNft.id) }
                    })
                }
                .background(Color.air.groupedItem)
                .margins(.all, 0)
            }
        }
        let likelyScamRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, itemIdentifier in
            guard let self, let state = cellStates[itemIdentifier] else { return }
            let onUnhideNft = self.onUnhideNft
            cell.configurationUpdateHandler = { cell, _ in
                cell.contentConfiguration = UIHostingConfiguration {
                    LikelyScamCell(state: state, onPreviewTap: { [weak self] in
                        self?.openNftDetails(nftId: state.displayNft.id)
                    }, action: { isUnhiddenByUser in
                        if let accountId = AccountStore.accountId {
                            NftStore.setHiddenByUser(accountId: accountId, nft: state.displayNft.nft, isHidden: !isUnhiddenByUser)
                        }
                        if isUnhiddenByUser { onUnhideNft?(state.displayNft.id) }
                    })
                }
                .background(Color.air.groupedItem)
                .margins(.all, 0)
            }
        }
        let sectionHeader = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] cell, _, indexPath in
            guard let section = self?.dataSource.sectionIdentifier(for: indexPath.section) else { return }
            var content = UIListContentConfiguration.groupedHeader()
            content.text = section.localizedTitle
            content.applyTextStyle(.sectionHeader, scaling: .dynamic)
            cell.contentConfiguration = content
        }
        let sectionFooter = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(elementKind: UICollectionView.elementKindSectionFooter) { [weak self] cell, _, indexPath in
            guard self?.dataSource.sectionIdentifier(for: indexPath.section) == .likelyScam else {
                cell.contentConfiguration = nil
                return
            }
            var content = UIListContentConfiguration.groupedFooter()
            content.text = lang("$settings_nft_probably_scam_description")
            content.applyTextStyle(.footnote, scaling: .dynamic)
            cell.contentConfiguration = content
        }
        dataSource = .init(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .hiddenByUser(let nftId):
                collectionView.dequeueConfiguredReusableCell(using: hiddenByUserRegistration, for: indexPath, item: nftId)
            case .unverified(let nftId), .likelyScam(let nftId):
                collectionView.dequeueConfiguredReusableCell(using: likelyScamRegistration, for: indexPath, item: nftId)
            }
        }
        dataSource.supplementaryViewProvider =  { collectionView, elementKind, indexPath in
            switch elementKind {
            case UICollectionView.elementKindSectionHeader:
                collectionView.dequeueConfiguredReusableSupplementary(using: sectionHeader, for: indexPath)
            case UICollectionView.elementKindSectionFooter:
                collectionView.dequeueConfiguredReusableSupplementary(using: sectionFooter, for: indexPath)
            default:
                nil
            }
        }
        
        UIView.performWithoutAnimation {
            updateNfts()
        }
        
        updateTheme()
    }
    
    private func makeLayout() -> UICollectionViewCompositionalLayout {
        var configuration = UICollectionLayoutListConfiguration.init(appearance: .insetGrouped)
        configuration.headerMode = .supplementary
        configuration.footerMode = .supplementary
        configuration.separatorConfiguration.bottomSeparatorInsets.leading = NftPreviewRow.textLeadingInset
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
        } else {
            configuration.separatorConfiguration.color = .air.separator
        }
        configuration.backgroundColor = .clear
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] sectionIndex, layoutEnvironment in
            var sectionConfiguration = configuration
            sectionConfiguration.footerMode = self?.dataSource?.sectionIdentifier(for: sectionIndex) == .likelyScam ? .supplementary : .none
            return NSCollectionLayoutSection.list(using: sectionConfiguration, layoutEnvironment: layoutEnvironment)
        })
        return layout
    }
    
    public override func scrollToTop(animated: Bool) {
        collectionView?.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
        collectionView.backgroundColor = .clear
    }
    
    public var scrollingView: UIScrollView? {
        return collectionView
    }
    
    private func updateNfts() {
        guard let latestNfts = NftStore.getAccountNfts(accountId: AccountStore.currentAccountId) else { return }

        // Discover items that belong in the list but aren't tracked yet.
        let trackedIds = Set(trackedRows.map(\.stringValue))
        var newHiddenByUser: [Row] = []
        var newUnverified: [Row] = []
        var newLikelyScam: [Row] = []
        for (id, displayNft) in latestNfts where !trackedIds.contains(id) {
            if displayNft.isHiddenByUser {
                newHiddenByUser.append(.hiddenByUser(id))
            } else if displayNft.nft.isHidden == true {
                newLikelyScam.append(.likelyScam(id))
            } else if AppStorageHelper.hideUnverifiedNfts, displayNft.nft.isUnverified == true {
                newUnverified.append(.unverified(id))
            }
        }

        let hasNewItems = !newHiddenByUser.isEmpty || !newUnverified.isEmpty || !newLikelyScam.isEmpty
        if hasNewItems {
            // Prepend new items to the front of their respective section.
            let existingHidden = trackedRows.filter { if case .hiddenByUser = $0 { true } else { false } }
            let existingUnverified = trackedRows.filter { if case .unverified = $0 { true } else { false } }
            let existingScam = trackedRows.filter { if case .likelyScam = $0 { true } else { false } }
            trackedRows = newHiddenByUser + existingHidden
                + newUnverified + existingUnverified
                + newLikelyScam + existingScam
            // Create cell state objects for new items.
            for row in newHiddenByUser + newUnverified + newLikelyScam {
                if let nft = latestNfts[row.stringValue] {
                    cellStates[row.stringValue] = HiddenNftCellViewModel(nft)
                }
            }
        }

        // Turning the setting off makes the unverified rows disappear from the list
        var didRemoveRows = false
        if !AppStorageHelper.hideUnverifiedNfts {
            let unverifiedRows = trackedRows.filter { if case .unverified = $0 { true } else { false } }
            if !unverifiedRows.isEmpty {
                trackedRows.removeAll { if case .unverified = $0 { true } else { false } }
                for row in unverifiedRows {
                    cellStates[row.stringValue] = nil
                }
                didRemoveRows = true
            }
        }

        for (id, state) in cellStates {
            if let updated = latestNfts[id] {
                state.displayNft = updated
            }
        }

        emptyStateLabel.isHidden = !trackedRows.isEmpty
        if hasNewItems || didRemoveRows {
            applySnapshot(makeSnapshot(), animated: true)
        }
    }
    
    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Row> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        guard !trackedRows.isEmpty else { return snapshot }

        let hiddenByUser = trackedRows.filter { if case .hiddenByUser = $0 { true } else { false } }
        let unverified = trackedRows.filter { if case .unverified = $0 { true } else { false } }
        let likelyScam = trackedRows.filter { if case .likelyScam = $0 { true } else { false } }

        if !hiddenByUser.isEmpty {
            snapshot.appendSections([.hiddenByUser])
            snapshot.appendItems(hiddenByUser)
        }
        if !unverified.isEmpty {
            snapshot.appendSections([.unverified])
            snapshot.appendItems(unverified)
        }
        if !likelyScam.isEmpty {
            snapshot.appendSections([.likelyScam])
            snapshot.appendItems(likelyScam)
        }
        return snapshot
    }
    
    private func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animated: Bool) {
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func openNftDetails(nftId: String) {
        guard let nft = cellStates[nftId]?.displayNft.nft else { return }
        let vc = NftDetailsVC(accountId: AccountStore.currentAccountId, source: .hiddenManagement(nft))
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension HiddenNftsVC: WalletCoreData.EventsObserver {
    public nonisolated func walletCore(event: WalletCore.WalletCoreData.Event) {
        Task { @MainActor in
            switch event {
            case .nftsChanged(let accountId) where accountId == AccountStore.currentAccountId:
                updateNfts()
            case .hideUnverifiedNftsChanged:
                updateNfts()
            default:
                break
            }
        }
    }
}
