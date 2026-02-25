//
//  ConnectedAppsVC.swift
//  UISettings
//
//  Created by Sina on 8/30/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI

public class ConnectedAppsVC: SettingsBaseVC, UICollectionViewDelegate {
    private enum Section: Hashable {
        case main
    }
    
    private enum Item: Hashable {
        case disconnectAll
        case dapp(ApiDapp)
    }
    
    private var dapps: [ApiDapp]?
    private let isModal: Bool
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    
    public init(isModal: Bool) {
        self.isModal = isModal
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        super.loadView()
        setupViews()
        configureDataSource()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        WalletCoreData.add(eventObserver: self)
        loadDapps()
    }
    
    private func setupViews() {
        title = lang("Connected Apps")
        
        addNavigationBar(
            title: title,
            closeIcon: isModal,
            addBackButton: isModal ? nil : { [weak self] in self?.navigationController?.popViewController(animated: true) }
        )
        
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerMode = .supplementary
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.trailingSwipeActions(for: indexPath)
        }
        configuration.backgroundColor = isModal ? WTheme.sheetBackground : WTheme.groupedBackground
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.delaysContentTouches = false
        collectionView.contentInset.top = navigationBarHeight
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        if let gestureRecognizer = collectionView.gestureRecognizers?.first(where: { $0.description.starts(with: "<_UISwipeActionPanGestureRecognizer") }) {
            (navigationController as? WNavigationController)?.fullWidthBackGestureRecognizerRequireToFail(gestureRecognizer)
        }
        
        bringNavigationBarToFront()
        updateTheme()
    }
    
    private func configureDataSource() {
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(elementKind: UICollectionView.elementKindSectionHeader) { supplementaryView, _, _ in
            var content = UIListContentConfiguration.groupedHeader()
            content.text = lang("Logged in with %app_name%", arg1: APP_NAME)
            supplementaryView.contentConfiguration = content
        }
        
        let disconnectAllHeight: CGFloat = IOS_26_MODE_ENABLED ? 52 : 44
        let disconnectAllRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Void> { cell, _, _ in
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    DisconnectAllCellContent()
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted)
                }
                .margins(.horizontal, 16)
                .margins(.vertical, 0)
                .minSize(height: disconnectAllHeight)
            }
        }
        
        let dappRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ApiDapp> { cell, _, dapp in
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    DappCellContent(dapp: dapp)
                }
                .background {
                    CellBackgroundHighlight(isHighlighted: state.isHighlighted, isSwiped: state.isSwiped)
                }
                .margins(.horizontal, 16)
                .margins(.vertical, 10)
            }
        }
        
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .disconnectAll:
                return collectionView.dequeueConfiguredReusableCell(using: disconnectAllRegistration, for: indexPath, item: ())
            case .dapp(let dapp):
                return collectionView.dequeueConfiguredReusableCell(using: dappRegistration, for: indexPath, item: dapp)
            }
        }
        
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }
    
    private func trailingSwipeActions(for indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case .dapp(let dapp) = item else { return nil }
        let deleteAction = UIContextualAction(style: .destructive, title: lang("Disconnect")) { [weak self] _, _, callback in
            self?.dapps?.removeAll(where: { $0 == dapp })
            self?.applySnapshot(animated: true)
            Task { @MainActor in
                do {
                    try await DappsStore.deleteDapp(dapp: dapp)
                    callback(true)
                } catch {
                    callback(false)
                }
            }
        }
        deleteAction.image = UIImage(systemName: "minus.circle.fill")
        let configuration = UISwipeActionsConfiguration(actions: [deleteAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }
    
    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        
        if let dapps, !dapps.isEmpty {
            snapshot.appendSections([.main])
            snapshot.appendItems([.disconnectAll], toSection: .main)
            snapshot.appendItems(dapps.map { .dapp($0) }, toSection: .main)
        }
        
        dataSource.apply(snapshot, animatingDifferences: animated)
        updateEmptyAssetsView()
    }
    
    public override func updateTheme() {
        view.backgroundColor = isModal ? WTheme.sheetBackground : WTheme.groupedBackground
        collectionView?.backgroundColor = isModal ? WTheme.sheetBackground : WTheme.groupedBackground
    }

    public override func scrollToTop(animated: Bool) {
        collectionView?.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }
    
    private var emptyDappsView: HeaderView?
    
    private func updateEmptyAssetsView() {
        guard let dapps else {
            emptyDappsView?.removeFromSuperview()
            emptyDappsView = nil
            return
        }
        if dapps.isEmpty {
            if emptyDappsView == nil {
                emptyDappsView = HeaderView(
                    animationName: "NoResults",
                    animationPlaybackMode: .loop,
                    title: lang("You have no apps connected to this wallet."),
                    description: nil,
                    compactMode: true
                )
                emptyDappsView!.lblTitle.font = .systemFont(ofSize: 17, weight: .medium)
                emptyDappsView?.alpha = 0
                view.addSubview(emptyDappsView!)
                NSLayoutConstraint.activate([
                    emptyDappsView!.widthAnchor.constraint(equalToConstant: 200),
                    emptyDappsView!.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    emptyDappsView!.centerYAnchor.constraint(equalTo: view.centerYAnchor)
                ])
            }
            UIView.animate(withDuration: 0.3) {
                self.emptyDappsView?.alpha = 1
            }
        } else {
            UIView.animate(withDuration: 0.3) {
                self.emptyDappsView?.alpha = 0
            } completion: { _ in
                self.emptyDappsView?.removeFromSuperview()
                self.emptyDappsView = nil
            }
        }
    }
    
    private func loadDapps() {
        Task {
            do {
                guard let accountId = AccountStore.accountId else { return }
                let dapps = try await Api.getDapps(accountId: accountId)
                self.dapps = dapps
                applySnapshot(animated: false)
            } catch {
                try? await Task.sleep(for: .seconds(3))
                loadDapps()
            }
        }
    }
    
    private func disconnectAllPressed() {
        showAlert(
            title: lang("Disconnect Dapps"),
            text: lang("Are you sure you want to disconnect all websites?"),
            button: lang("Disconnect"),
            buttonStyle: .destructive,
            buttonPressed: { [weak self] in
                self?.deleteAllDapps()
            },
            secondaryButton: lang("Cancel")
        )
    }
    
    private func deleteAllDapps() {
        guard let accountId = AccountStore.accountId else { return }
        Task {
            do {
                try await DappsStore.deleteAllDapps(accountId: accountId)
            } catch {
                self.showAlert(error: error)
            }
        }
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateNavigationBarProgressiveBlur(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .disconnectAll:
            disconnectAllPressed()
        case .dapp:
            break
        }
    }
}

extension ConnectedAppsVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCore.WalletCoreData.Event) {
        switch event {
        case .dappsCountUpdated:
            loadDapps()
        default:
            break
        }
    }
}

private struct DisconnectAllCellContent: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised")
                .font(.system(size: 22))
                .frame(width: 40)
            Text(lang("Disconnect All Dapps"))
                .font(.system(size: 17))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.air.error)
    }
}

private struct DappCellContent: View {
    let dapp: ApiDapp
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DappIcon(iconUrl: dapp.iconUrl)
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(dapp.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.air.primaryLabel)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if dapp.isUrlEnsured != true {
                        DappOriginWarning()
                    }
                    Text(dapp.displayUrl)
                        .foregroundStyle(Color.air.secondaryLabel)
                        .lineLimit(1)
                }
                .font(.system(size: 14))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
