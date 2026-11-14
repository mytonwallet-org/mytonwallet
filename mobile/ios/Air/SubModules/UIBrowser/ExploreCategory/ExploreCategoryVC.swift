//
//  ExploreCategoryVC.swift
//  UIBrowser
//
//  Created by Sina on 6/25/24.
//

import UIComponents
import UIKit
import WalletContext
import WalletCore

final class ExploreCategoryVC: WViewController {
    private let exploreVM: ExploreVM
    private let categoryId: Int

    private let collectionView = ExploreCategoryCollectionView(frame: .zero, collectionViewLayout: ExploreCategoryVC.makeLayout())
    private lazy var dataSource = makeDataSource()

    init(exploreVM: ExploreVM, categoryId: Int) {
        self.exploreVM = exploreVM
        self.categoryId = categoryId
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Overriden

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()

        applySnapshot(animated: false)
        exploreVM.refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        exploreVM.setActive(true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        exploreVM.setActive(false)
    }
    
    override func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(CGPoint(x: -collectionView.adjustedContentInset.left,
                                               y: -collectionView.adjustedContentInset.top), animated: animated)
    }

    // MARK: - Initial Setup

    private func setupViews() {
        navigationItem.title = exploreVM.exploreCategories[categoryId]?.displayName ?? ""
        
        view.backgroundColor = .air.background
        view.addStretchedToBounds(subview: collectionView)
        setContentScrollView(collectionView)
        
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.delaysContentTouches = false
        collectionView.canCancelContentTouches = true
        collectionView.backgroundColor = .air.background
        collectionView.accessibilityIdentifier = "explore_category_list"
        collectionView.showsVerticalScrollIndicator = false
        
        collectionView.contentInsetAdjustmentBehavior = .automatic
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(closeScreen))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.headerMode = .none
        config.backgroundColor = .clear
        config.showsSeparators = false
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        return layout
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        let cellRegistration = UICollectionView.CellRegistration<ExploreCategoryCell, Item> { [weak self] cell, _, item in
            guard let self else { return }
            switch item {
            case .dapp(let siteId):
                if let site = exploreVM.exploreSites[siteId] {
                    cell.configure(site: site) { [weak self] in
                        self?.openDapp(site: site)
                    }
                }
            }
        }

        let dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
            collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }

        return dataSource
    }

    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        var exploreSites = exploreVM.exploreSites.values.filter { $0.categoryId == categoryId }
        if ConfigStore.shared.shouldRestrictSites {
            exploreSites = exploreSites.filter { !$0.canBeRestricted }
        }

        if !exploreSites.isEmpty {
            snapshot.appendSections([.main])
            snapshot.appendItems(exploreSites.map { .dapp(url: $0.url) })
        }

        return snapshot
    }
}

// MARK: - Actions

extension ExploreCategoryVC {
    private func applySnapshot(animated: Bool) {
        let snapshot = makeSnapshot()
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    @objc private func closeScreen() {
        presentingViewController?.dismiss(animated: true)
    }
}

extension ExploreCategoryVC: ExploreVMDelegate {
    func didUpdateViewModelData() {
        applySnapshot(animated: true)
    }
}

extension ExploreCategoryVC: UICollectionViewDelegate {
    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = dataSource.itemIdentifier(for: indexPath)
        switch item {
        case .dapp(let url):
            guard let exploreSite = exploreVM.exploreSites[url] else { return }
            openDapp(site: exploreSite)

        case .none:
            break
        }
    }

    private func openDapp(site: ApiSite) {
        guard let url = URL(string: site.url) else { return }
        if site.shouldOpenExternally {
            UIApplication.shared.open(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.presentingViewController?.dismiss(animated: true)
            }
        } else {
            AppActions.openInBrowser(url, title: site.name, injectDappConnect: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                self.navigationController?.popToRootViewController(animated: true)
            }
        }
    }
}

extension ExploreCategoryVC: UIGestureRecognizerDelegate {
    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        collectionView.hitTest(touch.location(in: collectionView), with: nil) === collectionView
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldRequireFailureOf _: UIGestureRecognizer) -> Bool {
        true
    }
}

extension ExploreCategoryVC {
    enum Section: Equatable, Hashable {
        case main
    }

    enum Item: Equatable, Hashable {
        case dapp(url: String)
    }
}

private final class ExploreCategoryCollectionView: UICollectionView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        view is UIButton || super.touchesShouldCancel(in: view)
    }
}
