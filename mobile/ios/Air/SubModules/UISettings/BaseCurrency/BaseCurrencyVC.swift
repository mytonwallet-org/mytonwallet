//
//  BaseCurrencyVC.swift
//  UISettings
//
//  Created by Sina on 7/5/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

public class BaseCurrencyVC: SettingsBaseVC, UICollectionViewDelegate {

    private let currencies: [MBaseCurrency] = MBaseCurrency.allCases
    private let isModal: Bool

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, MBaseCurrency>?

    private enum Section: Hashable {
        case main
    }

    public init(isModal: Bool) {
        self.isModal = isModal
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
        view.backgroundColor = isModal ? WTheme.sheetBackground : WTheme.groupedBackground

        navigationItem.title = lang("Base Currency")

        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.headerTopPadding = 24
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

        let cellRegistration = BaseCurrencyCell.makeRegistration(currentCurrency: TokenStore.baseCurrency)

        let dataSource = UICollectionViewDiffableDataSource<Section, MBaseCurrency>(collectionView: collectionView) { collectionView, indexPath, currency in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: currency)
        }
        self.dataSource = dataSource
        dataSource.apply(makeSnapshot(), animatingDifferences: false)
    }

    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, MBaseCurrency> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, MBaseCurrency>()
        snapshot.appendSections([.main])
        snapshot.appendItems(currencies)
        return snapshot
    }

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        if let currency = dataSource?.itemIdentifier(for: indexPath), currency != TokenStore.baseCurrency {
            return true
        }
        return false
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let currency = dataSource?.itemIdentifier(for: indexPath) {
            Task {
                try? await TokenStore.setBaseCurrency(currency: currency)
            }
            navigationController?.popViewController(animated: true)
        }
    }

    public override func viewWillLayoutSubviews() {
        UIView.performWithoutAnimation {
            collectionView.frame = view.bounds
        }
        super.viewWillLayoutSubviews()
    }
}

#if DEBUG
@available(iOS 26, *)
#Preview {
    let vc = BaseCurrencyVC(isModal: false)
    UINavigationController(rootViewController: vc)
}
#endif
