//
//  SettingsVC.swift
//  UISettings
//
//  Created by Sina on 6/26/24.
//

import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Dependencies
import Perception

private let log = Log("SettingsVC")

@MainActor
public class SettingsVC: SettingsBaseVC, Sendable, WalletCoreData.EventsObserver, UICollectionViewDelegate {
    
    typealias Section = SettingsSection.Section
    typealias Row = SettingsItem.Identifier
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!
    private var settingsHeaderView: SettingsHeaderView!
    private var pauseReloadData: Bool = false
    private var isExpandedSplitLayout: Bool {
        splitViewController?.isCollapsed == false
    }
        
    @Dependency(\.accountStore.currentAccountId) private var currentAccountId
    @Dependency(\.accountStore.orderedAccountIds) private var orderedAccountIds
    
    public override var hideNavigationBar: Bool {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            false
        } else {
            true
        }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
        WalletCoreData.add(eventObserver: self)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pauseReloadData = false
        configHeader()
        reloadData(animated: false)
    }
    
    // MARK: - Setup settings
    func setupViews() {
        view.backgroundColor = WTheme.groupedBackground
        
        settingsHeaderView = SettingsHeaderView()
        
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            addNavigationBar()
            // set title to get blurred background
            navigationItem.attributedTitle = AttributedString(lang("Settings"), attributes: AttributeContainer([.foregroundColor: UIColor.clear]))
            navigationItem.leftItemsSupplementBackButton = true
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: lang("Receive"),
                image: UIImage.airBundle("QRIcon").withRenderingMode(.alwaysTemplate),
                primaryAction: UIAction { [weak self] _ in self?.showReceiveWithQR() }
            )
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: lang("More"),
                image: UIImage(systemName: "ellipsis")?.withRenderingMode(.alwaysTemplate),
                menu: makeMoreMenu()
            )
            navigationItem.titleView = settingsHeaderView.headerTouchTarget
        } else {
            additionalSafeAreaInsets = UIEdgeInsets(top: settingsHeaderView.layoutGeometry.legacyNavBarHeight, left: 0, bottom: 0, right: 0)
        }
        
        var _configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        _configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            if case .account(let accountId) = self?.dataSource.itemIdentifier(for: indexPath) {
                let deleteAction = UIContextualAction(style: .destructive, title: lang("Remove Wallet")) { _, _, callback in
                    self?.signoutPressed(removingAccountId: accountId, callback: callback)
                }
                let actions = UISwipeActionsConfiguration(actions: [deleteAction])
                actions.performsFirstActionWithFullSwipe = true
                return actions
            }
            return nil
        }
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
        } else {
            _configuration.separatorConfiguration.color = WTheme.separator
        }
        _configuration.separatorConfiguration.bottomSeparatorInsets.leading = 62
        _configuration.headerMode = .none
        
        let topSectionInset = settingsHeaderView.layoutGeometry.topSectionInset
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] sectionIdx, env in
            var configuration = _configuration
            configuration.footerMode = sectionIdx + 1 == self?.collectionView.numberOfSections ? .supplementary : .none
            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: env)
            section.contentInsets.top = sectionIdx == 0 ? topSectionInset : 0
            section.contentInsets.bottom = 16
            return section
        })
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(SettingsItemCell.self, forCellWithReuseIdentifier: "settingsItem")
        collectionView.register(FooterView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: UICollectionView.elementKindSectionFooter)
        collectionView.delegate = self
        collectionView.delaysContentTouches = false
        collectionView.allowsSelection = true
        collectionView.contentInset.top = settingsHeaderView.layoutGeometry.scrollTopContentInset
        collectionView.backgroundColor = WTheme.groupedBackground

        let listCellRegistration = AccountListCell.makeRegistration()
        
        dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: collectionView) { [weak self] (tableView, indexPath, itemIdentifier) -> UICollectionViewCell? in
            guard let self else { fatalError() }
            let settingsItem = itemIdentifier.content
            switch itemIdentifier {
            case .account(accountId: let accountId):
                return tableView.dequeueConfiguredReusableCell(using: listCellRegistration, for: indexPath, item: accountId)
            default:
                guard let cell = tableView.dequeueReusableCell(withReuseIdentifier: "settingsItem", for: indexPath) as? SettingsItemCell else { return nil }
                cell.configure(
                    with: settingsItem,
                    value: value(for: settingsItem)
                )
                return cell
            }
        }
        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            switch kind {
            case UICollectionView.elementKindSectionFooter:
                let cell = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! FooterView
                cell.bounds = CGRect(x: 0, y: 0, width: collectionView.contentSize.width, height: 46)
                let g = UITapGestureRecognizer(target: self, action: #selector(SettingsVC.onVersionMultipleTap(_:)))
                g.numberOfTapsRequired = 5
                cell.addGestureRecognizer(g)
                return cell
            default:
                return nil
            }
        }
        dataSource.apply(makeSnapshot(), animatingDifferences: false)
        
        // Add table view
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Add header view
        view.addSubview(settingsHeaderView)
        settingsHeaderView.setupViews(moreMenu: makeMoreMenu())
        settingsHeaderView.delegate = self
        NSLayoutConstraint.activate([
            settingsHeaderView.topAnchor.constraint(equalTo: view.topAnchor),
            settingsHeaderView.leftAnchor.constraint(equalTo: view.leftAnchor),
            settingsHeaderView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
                
        addBottomBarBlur()
        
        collectionView.reloadData()
    }
        
    public override func scrollToTop(animated: Bool) {
        collectionView?.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }
    
    private func selected(item: SettingsItem.Identifier) {
        switch item {
        case .editWalletName:
            AppActions.showRenameAccount(accountId: AccountStore.accountId!)
            
        case .account(let accountId):
            pauseReloadData = true // prevent showing new data while switching away from settings tab
            Task {
                do {
                    _ = try await AccountStore.activateAccount(accountId: accountId)
                    AppActions.showHome(popToRoot: true)
                } catch {
                    fatalError("failed to activate account: \(accountId)")
                }
            }
        case .walletSettings:
            AppActions.showWalletSettings()
        case .addAccount:
            AppActions.showAddWallet(network: .mainnet, showCreateWallet: true, showSwitchToOtherVersion: true)
        case .notifications:
            navigationController?.pushViewController(NotificationsSettingsVC(), animated: true)
        case .appearance:
            navigationController?.pushViewController(AppearanceSettingsVC(), animated: true)
        case .assetsAndActivity:
            navigationController?.pushViewController(AssetsAndActivityVC(), animated: true)
        case .connectedApps:
            navigationController?.pushViewController(ConnectedAppsVC(isModal: false), animated: true)
        case .language:
            navigationController?.pushViewController(LanguageVC(), animated: true)
        case .security:
            Task { @MainActor in
                if let password = await UnlockVC.presentAuthAsync(on: self) {
                    self.navigationController?.pushViewController(SecurityVC(password: password), animated: true)
                }
            }
        case .walletVersions:
            navigationController?.pushViewController(WalletVersionsVC(), animated: true)
        case .tips:
            AppActions.openTipsChannel()
        case .helpCenter:
            let title = lang("Help Center")
            let url = Language.current == .ru ? HELP_CENTER_URL_RU : HELP_CENTER_URL
            navigationController?.pushPlainWebView(title: title, url: URL(string: url)!)
        case .support:
            UIApplication.shared.open(URL(string: "https://t.me/\(SUPPORT_USERNAME)")!)
        case .about:
            let vc = AboutVC(showLegalSection: true)
            navigationController?.pushViewController(vc, animated: true)
        case .useResponsibly:
            navigationController?.pushViewController(UseResponsiblyVC(), animated: true)
        }
    }
    
    private func signoutPressed(removingAccountId: String, callback: @escaping (Bool) -> ()) {
        let isCurrentAccount = removingAccountId == AccountStore.accountId
        let removingAccount = AccountStore.accountsById[removingAccountId] ?? DUMMY_ACCOUNT
        showDeleteAccountAlert(
            accountToDelete: removingAccount,
            isCurrentAccount: isCurrentAccount,
            onSuccess: { [weak self] in
                if isCurrentAccount {
                    self?.tabBarController?.selectedIndex = 0
                }
                callback(true)
            },
            onCancel: { [weak self] in
                self?.reloadData(animated: true)
                callback(false)
            },
            onFailure: { [weak self] error in
                log.fault("delete account error: \(error)")
                self?.showAlert(error: error)
                callback(false)
            }
        )
    }
    
    @objc func onVersionMultipleTap(_ gesture: UIGestureRecognizer) {
        if gesture.state == .ended {
            (UIApplication.shared.delegate as? MtwAppDelegateProtocol)?.showDebugView()
        }
    }
    
    private func showReceiveWithQR() {
        AppActions.showReceive(chain: nil, title: lang("Your Address"))
    }
    
    private func removeWalllet() {
        if let accountId = AccountStore.accountId {
            signoutPressed(removingAccountId: accountId, callback: { _ in })
        }
    }
    
    private func makeMoreMenu() -> UIMenu {
        var items: [UIMenuElement] = []
        
        items += UIAction(title: lang("Remove Wallet"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.removeWalllet()
        }
                    
        return UIMenu(title: "", children: items)
    }
    
    // MARK: Data source
    
    func makeSnapshot() -> NSDiffableDataSourceSnapshot<SettingsVC.Section, SettingsVC.Row> {
        var snapshot = NSDiffableDataSourceSnapshot<SettingsVC.Section, SettingsVC.Row>()
        snapshot.appendSections([.header])
        snapshot.appendItems([.editWalletName])
        
        if !isExpandedSplitLayout {
            snapshot.appendSections([.accounts])
            let currentAccountId = self.currentAccountId
            let otherAccounts = AccountStore.orderedAccountIds
                .filter { $0 != currentAccountId }
            if otherAccounts.count <= 6 {
                snapshot.appendItems(otherAccounts.map(SettingsItem.Identifier.account))
            } else {
                snapshot.appendItems(otherAccounts.prefix(5).map(SettingsItem.Identifier.account))
                snapshot.appendItems([.walletSettings])
            }
            
            snapshot.appendItems([.addAccount])
        }
        
        // General section
        snapshot.appendSections([.general])
        snapshot.appendItems([.appearance])
        if AuthSupport.accountsSupportAppLock {
            snapshot.appendItems([.security])
        }
        snapshot.appendItems([.assetsAndActivity])
        if let count = AccountStore.walletVersionsData?.versions.count, count > 0 {
            snapshot.appendItems([.walletVersions])
        }
        if let count = DappsStore.dappsCount, count > 0 {
            snapshot.appendItems([.connectedApps])
        }
        snapshot.appendItems([.notifications])
        snapshot.appendItems([.language])

        // Questions and answers
        snapshot.appendSections([.questionAndAnswers])
        if ConfigStore.shared.config?.supportAccountsCount ?? 1 > 0 {
            snapshot.appendItems([.support])
        }
        snapshot.appendItems([.helpCenter])
        snapshot.appendItems([.tips])
        snapshot.appendItems([.useResponsibly])

        // About
        snapshot.appendSections([.about])
        snapshot.appendItems([.about])
                
        return snapshot
    }
    
    func value(for item: SettingsItem) -> String? {
        if let value = item.value {
            // item already has a cached value on the item model
            return value
        }
        switch item.id {
        case .language:
            return Language.current.nativeName
        case .walletVersions:
            return AccountStore.walletVersionsData?.currentVersion
        case .connectedApps:
            return DappsStore.dappsCount != nil ? "\(DappsStore.dappsCount!)" : ""
        case .support:
            return "@\(SUPPORT_USERNAME)"
        default:
            return nil
        }
    }

    // MARK: - Collection view delegate
    
    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        true
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let id = dataSource.itemIdentifier(for: indexPath) {
            log.info("didSelectItemAt \(indexPath, .public) -> \(id, .public)")
            selected(item: id)
        }
        collectionView.deselectItem(at: indexPath, animated: true)
    }
    
    // scroll delegation
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if collectionView.contentSize.height + view.safeAreaInsets.vertical > collectionView.frame.height {
            let requiredInset: CGFloat = max(16.0, collectionView.frame.height + 56.0 - collectionView.contentSize.height - view.safeAreaInsets.vertical)
            collectionView.contentInset.bottom = requiredInset
        }
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        settingsHeaderView.update(scrollOffset: scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
    }
    
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                          withVelocity velocity: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let topInset = collectionView.adjustedContentInset.top
        let realTargetY = targetContentOffset.pointee.y + topInset
        let lg = settingsHeaderView.layoutGeometry
        let fullScrollRange = lg.fullScrollRange
        
        // snap to views
        if realTargetY > 0 && collectionView.contentSize.height + view.safeAreaInsets.vertical > collectionView.frame.height {
            if realTargetY < fullScrollRange {
                var isGoingDown = targetContentOffset.pointee.y > scrollView.contentOffset.y
                if abs(velocity.y) < 5 {
                    isGoingDown = realTargetY < fullScrollRange * lg.collapseThreshold
                }
                if isGoingDown {
                    targetContentOffset.pointee.y = -topInset
                } else {
                    targetContentOffset.pointee.y = fullScrollRange - topInset
                }
            }
        }
    }

    // MARK: - Observer
    
    public nonisolated func walletCore(event: WalletCoreData.Event) {
        DispatchQueue.main.async { [self] in
            switch event {
            case .accountChanged:
                pauseReloadData = true // prevent showing new data while switching away from settings tab
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
                    pauseReloadData = false
                    reloadData(animated: false)
                    configHeader()
                    navigationController?.popToRootViewController(animated: false)
                }

            case .accountNameChanged:
                configHeader()

            case .balanceChanged:
                updateHeaderBalance()

            case .notActiveAccountBalanceChanged:
                reloadData(animated: true)

            case .baseCurrencyChanged(to: _), .tokensChanged:
                updateHeaderBalance()
                reloadData(animated: true)
                
            case .stakingAccountData(let data):
                if data.accountId == AccountStore.accountId {
                    updateHeaderBalance()
                    reloadData(animated: true)
                }

            case .walletVersionsDataReceived:
                reloadData(animated: true)

            case .dappsCountUpdated:
                reloadData(animated: true)

            default:
                break
            }
        }
    }
    
    private func configHeader() {
        if !pauseReloadData {
            settingsHeaderView?.config()
        }
    }
    
    private func updateHeaderBalance() {
        if !pauseReloadData {
            settingsHeaderView?.updateBalance()
        }
    }
    
    private func reloadData(animated: Bool) {
        if animated {
            if !pauseReloadData {
                dataSource.apply(makeSnapshot(), animatingDifferences: animated)
            }
        } else {
            UIView.performWithoutAnimation {
                var snapshot = makeSnapshot()
                snapshot.reconfigureItems(snapshot.itemIdentifiers)
                dataSource.apply(snapshot, animatingDifferences: false)
            }
        }
    }
}

 extension SettingsVC: @MainActor SettingsHeaderViewDelegate {
    func settingsHeaderViewDidTapQRCodeButton() {
        showReceiveWithQR()
    }
}
