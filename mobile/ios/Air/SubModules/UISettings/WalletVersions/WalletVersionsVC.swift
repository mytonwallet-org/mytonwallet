//
//  WalletVersionsVC.swift
//  UISettings
//
//  Created by Sina on 7/14/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI

public class WalletVersionsVC: SettingsBaseVC, UICollectionViewDelegate {

    private enum Section: Hashable {
        case currentVersion
        case otherVersions

        var headerTitle: String {
            switch self {
            case .currentVersion:
                lang("Current Wallet Version")
            case .otherVersions:
                lang("Tokens on Other Versions")
            }
        }
    }

    private enum Item: Hashable {
        case currentWallet
        case otherVersion(String)
    }

    private let isModal: Bool
    private var collectionView: UICollectionView!
    private var walletVersionsData: MWalletVersionsData?
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    public init(isModal: Bool = false) {
        self.isModal = isModal
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        configureDataSource()
        applySnapshot()
    }

    private func setupViews() {
        title = lang("TON Wallet Versions")
        walletVersionsData = AccountStore.walletVersionsData
        view.backgroundColor = isModal ? WTheme.sheetBackground : WTheme.groupedBackground

        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.headerMode = .supplementary
        configuration.footerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.delaysContentTouches = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        addNavigationBar(
            navHeight: 40,
            topOffset: -5,
            title: title,
            addBackButton: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        )
        collectionView.contentInset.top = navigationBarHeight
        collectionView.verticalScrollIndicatorInsets.top = navigationBarHeight
        collectionView.contentOffset.y = -navigationBarHeight
    }

    private func configureDataSource() {
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] cell, _, indexPath in
            guard let section = self?.dataSource.sectionIdentifier(for: indexPath.section) else { return }
            var content = UIListContentConfiguration.groupedHeader()
            content.text = section.headerTitle
            cell.contentConfiguration = content
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] cell, _, indexPath in
            guard let self, let section = dataSource.sectionIdentifier(for: indexPath.section) else { return }
            if section == .otherVersions || (section == .currentVersion && walletVersionsData?.versions.isEmpty != false) {
                cell.contentConfiguration = UIHostingConfiguration {
                    WalletVersionsFooter()
                }
                .margins(.horizontal, 20)
                .margins(.vertical, 8)
            }
        }

        let currentVersionRegistration = WalletVersionCell.makeCurrentVersionRegistration(
            walletVersionsData: walletVersionsData,
            account: AccountStore.account
        )

        let otherVersionRegistration = WalletVersionCell.makeOtherVersionRegistration(
            versions: walletVersionsData?.versions ?? []
        )

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .currentWallet:
                collectionView.dequeueConfiguredReusableCell(using: currentVersionRegistration, for: indexPath, item: ())
            case .otherVersion(let versionId):
                collectionView.dequeueConfiguredReusableCell(using: otherVersionRegistration, for: indexPath, item: versionId)
            }
        }

        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            switch kind {
            case UICollectionView.elementKindSectionHeader:
                collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
            case UICollectionView.elementKindSectionFooter:
                collectionView.dequeueConfiguredReusableSupplementary(using: footerRegistration, for: indexPath)
            default:
                nil
            }
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

        snapshot.appendSections([.currentVersion])
        snapshot.appendItems([.currentWallet], toSection: .currentVersion)

        if let versions = walletVersionsData?.versions, !versions.isEmpty {
            snapshot.appendSections([.otherVersions])
            snapshot.appendItems(versions.map { .otherVersion($0.version) }, toSection: .otherVersions)
        }

        dataSource.apply(snapshot, animatingDifferences: false)
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        switch item {
        case .currentWallet:
            return false
        case .otherVersion:
            return true
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .currentWallet:
            navigationController?.popViewController(animated: true)
        case .otherVersion(let versionId):
            guard let version = walletVersionsData?.versions.first(where: { $0.version == versionId }),
                  let accountId = AccountStore.accountId,
                  let apiVersion = ApiTonWalletVersion(rawValue: version.version) else { return }
            Task { @MainActor in
                do {
                    _ = try await AccountStore.importNewWalletVersion(accountId: accountId, version: apiVersion)
                    navigationController?.popViewController(animated: false)
                } catch {
                    showAlert(error: error)
                }
            }
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        navigationBar?.showSeparator = scrollView.contentOffset.y + scrollView.contentInset.top + view.safeAreaInsets.top > 0
    }

    public override func viewWillLayoutSubviews() {
        UIView.performWithoutAnimation {
            collectionView.frame = view.bounds
        }
        super.viewWillLayoutSubviews()
    }

    public override func scrollToTop(animated: Bool) {
        collectionView?.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }
}

private struct WalletVersionsFooter: View {
    var body: some View {
        let hintText = Language.current == .en
            ? lang("You have tokens on other versions of your wallet. You can import them from here.") + "\n\nRead more about types of wallet contracts on ton.org"
            : lang("You have tokens on other versions of your wallet. You can import them from here.")

        Text(makeAttributedHint(hintText))
            .font(.system(size: 13))
            .foregroundStyle(Color.air.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                AppActions.openInBrowser(url, title: nil, injectDappConnect: false)
                return .handled
            })
    }

    private func makeAttributedHint(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let range = attributed.range(of: "ton.org") {
            attributed[range].foregroundColor = Color.air.tint
            attributed[range].link = URL(string: "https://ton.org")
        }
        return attributed
    }
}

#if DEBUG
@available(iOS 26, *)
#Preview {
    let vc = WalletVersionsVC(isModal: false)
    UINavigationController(rootViewController: vc)
}
#endif
