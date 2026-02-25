//
//  LanguageVC.swift
//  UISettings
//
//  Created by Sina on 7/5/24.
//

import Foundation
import UIKit
import UIComponents
import WalletContext
import WalletCore
import SwiftUI

public class LanguageVC: SettingsBaseVC, UICollectionViewDelegate {
    
    let languages = Language.supportedLanguages
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, String>?
    
    enum Section: Hashable {
        case main
    }
    
    public init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    private func setupViews() {
        
        view.backgroundColor = WTheme.groupedBackground
        
        navigationItem.title = lang("Language")
        
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.headerTopPadding = 24
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = WTheme.sheetBackground
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
        
        let cellRegistration = LanguageCell.makeRegistration(languages: languages)
        
        let dataSource = UICollectionViewDiffableDataSource<Section, String>(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: itemIdentifier)
        }
        self.dataSource = dataSource
        dataSource.apply(makeSnapshot(), animatingDifferences: false)
    }

    func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, String> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.main])
        snapshot.appendItems(languages.map(\.id))
        return snapshot
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        if let id = dataSource?.itemIdentifier(for: indexPath), id != LocalizationSupport.shared.langCode {
            return true
        }
        return false
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let id = dataSource?.itemIdentifier(for: indexPath) {
            LocalizationSupport.shared.setLanguageCode(id)
            AccountStore.refreshEnabledNotificationSubscriptions()
            // do we need this?
            UserDefaults.standard.set([id], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
            WalletContextManager.delegate?.restartApp()
        }
    }
    
    public override func viewWillLayoutSubviews() {
        // prevent unwanted animation on iOS 26
        UIView.performWithoutAnimation {
            collectionView.frame = view.bounds
        }
        super.viewWillLayoutSubviews()
    }
}


@available(iOS 26, *)
#Preview {
    let vc = LanguageVC()
    UINavigationController(rootViewController: vc)
}
