
import UIKit
import WalletCore
import WalletContext
import UIComponents
import Dependencies
import SwiftUI
import Perception

public class ChooseWalletVC: WViewController, UICollectionViewDelegate {
    
    public let host: String
    public let allowViewAccounts: Bool
    public let onSelect: (String) -> Void
    
    @Dependency(\.accountStore) private var accountStore
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, String>?
    
    enum Section: Hashable {
        case main
    }
    
    public init(host: String, allowViewAccounts: Bool, onSelect: @escaping (String) -> Void) {
        self.host = host
        self.allowViewAccounts = allowViewAccounts
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    public override var hideNavigationBar: Bool { false }
    
    private func setupViews() {
        
        navigationItem.title = lang("Choose Wallet")
        addCloseNavigationItemIfNeeded()
        configureSheetWithOpaqueBackground(color: WTheme.sheetBackground)
        
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = WTheme.sheetBackground
        collectionView.delegate = self
        collectionView.delaysContentTouches = false
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(elementKind: UICollectionView.elementKindSectionHeader) { [host] supplementaryView, _, _ in
            var content = UIListContentConfiguration.groupedHeader()
            content.text = lang("Wallet to use on %host%", arg1: host)
            content.textProperties.color = WTheme.secondaryLabel
            supplementaryView.contentConfiguration = content
        }
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [allowViewAccounts] cell, _, accountId in
            let accountContext = AccountContext(accountId: accountId)
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    WithPerceptionTracking {
                        let isDisabled = allowViewAccounts ? false : accountContext.account.isView
                        AccountListCell(accountContext: accountContext, isReordering: state.isEditing, showCurrentAccountHighlight: true)
                            .allowsHitTesting(!isDisabled)
                            .opacity(isDisabled ? 0.4 : 1)
                    }
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted)
                }
                .margins(.horizontal, 12)
                .margins(.vertical, 10)
            }
        }
        
        let dataSource = UICollectionViewDiffableDataSource<Section, String>(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemIdentifier)
        }
        self.dataSource = dataSource
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
        dataSource.apply(makeSnapshot(), animatingDifferences: false)
    }
    
    func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, String> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(Array(accountStore.orderedAccountIds))
        return snapshot
    }
    
    public func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        isAccountSelectable(indexPath: indexPath)
    }
    
    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        isAccountSelectable(indexPath: indexPath)
    }
    
    private func isAccountSelectable(indexPath: IndexPath) -> Bool {
        if allowViewAccounts {
            return true
        }
        if let accountId = dataSource?.itemIdentifier(for: indexPath) {
            return !accountStore.get(accountId: accountId).isView
        }
        return false
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let accountId = dataSource?.itemIdentifier(for: indexPath) {
            onSelect(accountId)
            presentingViewController?.dismiss(animated: true)
        }
    }
}
