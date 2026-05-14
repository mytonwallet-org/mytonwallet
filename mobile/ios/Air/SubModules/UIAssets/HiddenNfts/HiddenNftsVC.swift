
import UIKit
import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import OrderedCollections
import Kingfisher

private let log = Log("HiddenNftsVC")


@MainActor
public class HiddenNftsVC: WViewController, Sendable {
    
    enum Section {
        case hiddenByUser
        case likelyScam
        
        var localizedTitle: String {
            switch self {
            case .hiddenByUser: lang("Hidden By Me")
            case .likelyScam: lang("Probably Scam")
            }
        }
    }
    enum Row: Hashable {
        case hiddenByUser(String)
        case likelyScam(String)
        
        var stringValue: String {
            switch self {
            case .hiddenByUser(let string), .likelyScam(let string):
                return string
            }
        }
    }
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!
    
    private var animateIfPossible: Bool { false }
    private var isAppActive: Bool = true
    private var isVisible: Bool = true
    
    private var cornerRadius: CGFloat = 12

    private let horizontalMargins: CGFloat = 16
    private let spacing: CGFloat = 16
    private let compactSpacing: CGFloat = 8
    
    private var contextMenuExtraBlurView: UIView?
    
    public init() {
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
    
    private var displayNfts: OrderedDictionary<String, DisplayNft>?
    
    func setupViews() {
        title = lang("Hidden NFTs")
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
        collectionView.clipsToBounds = false
        collectionView.delaysContentTouches = false

        let hiddenByUserRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, indexPath, itemIdentifier in
            guard let self else { return }
            let displayNft: DisplayNft? = displayNfts?[itemIdentifier] ?? NftStore.getNft(accountId: AccountStore.currentAccountId, nftId: itemIdentifier)
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    if let displayNft {
                        HiddenByUserCell(displayNft: displayNft, isHighlighted: state.isHighlighted, action: { isHiddenByUser in
                            if let accountId = AccountStore.accountId {
                                NftStore.setHiddenByUser(accountId: accountId, nftId: displayNft.id, isHidden: isHiddenByUser)
                            }
                        })
                    }
                }
                .background(Color.air.groupedItem)
                .margins(.all, 0)
            }
        }
        let likelyScamRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, indexPath, itemIdentifier in
            guard let self else { return }
            let displayNft: DisplayNft? = displayNfts?[itemIdentifier] ?? NftStore.getNft(accountId: AccountStore.currentAccountId, nftId: itemIdentifier)
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    if let displayNft {
                        LikelyScamCell(displayNft: displayNft, isHighlighted: state.isHighlighted, action: { isUnhiddenByUser in
                            if let accountId = AccountStore.accountId {
                                NftStore.setHiddenByUser(accountId: accountId, nftId: displayNft.id, isHidden: !isUnhiddenByUser)
                            }
                        })
                    }
                }
                .background(Color.air.groupedItem)
                .margins(.all, 0)
            }
        }
        let sectionHeader = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] cell, _, indexPath in
            guard let section = self?.dataSource.sectionIdentifier(for: indexPath.section) else { return }
            var content = UIListContentConfiguration.groupedHeader()
            content.text = section.localizedTitle
            cell.contentConfiguration = content
        }
        let sectionFooter = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(elementKind: UICollectionView.elementKindSectionFooter) { [weak self] cell, _, indexPath in
            guard self?.dataSource.sectionIdentifier(for: indexPath.section) == .likelyScam else {
                cell.contentConfiguration = nil
                return
            }
            var content = UIListContentConfiguration.groupedFooter()
            content.text = lang("$settings_nft_probably_scam_description")
            cell.contentConfiguration = content
        }
        dataSource = .init(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .hiddenByUser(let nftId):
                collectionView.dequeueConfiguredReusableCell(using: hiddenByUserRegistration, for: indexPath, item: nftId)
            case .likelyScam(let nftId):
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
    
    func makeLayout() -> UICollectionViewCompositionalLayout {
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
        if let nfts = NftStore.getAccountNfts(accountId: AccountStore.currentAccountId) {
            self.displayNfts = nfts
        } else {
            self.displayNfts = nil
        }
        
        applySnapshot(makeSnapshot(), animated: true)
    }
    
    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Row> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        
        if let displayNfts {
            
            let hiddenByUser = displayNfts
                .filter { _, displayNft in
                    displayNft.isHiddenByUser
                }
                .keys
                .map { Row.hiddenByUser($0) }
            if !hiddenByUser.isEmpty {
                snapshot.appendSections([.hiddenByUser])
                snapshot.appendItems(hiddenByUser)
            }
            
            let likelyScam = displayNfts
                .filter { _, displayNft in
                    displayNft.nft.isScam == true
                }
                .keys
                .map { Row.likelyScam($0) }
            if !likelyScam.isEmpty {
                snapshot.appendSections([.likelyScam])
                snapshot.appendItems(likelyScam)
            }
        }
        return snapshot
    }
    
    func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Row>, animated: Bool) {
        dataSource.apply(snapshot, animatingDifferences: animated)
    }
}


extension HiddenNftsVC: UICollectionViewDelegate {

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let nftId = dataSource.itemIdentifier(for: indexPath)?.stringValue, let nft = displayNfts?[nftId]?.nft {
            let assetVC = NftDetailsVC(accountId: AccountStore.currentAccountId, nft: nft, listContext: .none)
            navigationController?.pushViewController(assetVC, animated: true)
        }
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
    }
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    }
}

extension HiddenNftsVC: WalletCoreData.EventsObserver {
    public nonisolated func walletCore(event: WalletCore.WalletCoreData.Event) {
        Task { @MainActor in
            switch event {
            default:
                break
            }
        }
    }
}
