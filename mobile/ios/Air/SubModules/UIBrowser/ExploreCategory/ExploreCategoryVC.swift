//
//  ExploreVC.swift
//  UIBrowser
//
//  Created by Sina on 6/25/24.
//

import Combine
import Kingfisher
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

final class ExploreCategoryVC: WViewController {
    private let exploreVM: ExploreVM
    private let categoryId: Int

    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: ExploreCategoryVC.makeLayout())
    private let dataSource: UICollectionViewDiffableDataSource<Section, Item>

    private let viewOutput = ViewOutput()

    private let backgroundColor: UIColor = .air.background
    private let backgroundColorSUI: Color = .air.background

    private var cancelBag = Set<AnyCancellable>()

    init(exploreVM: ExploreVM, categoryId: Int) {
        self.exploreVM = exploreVM
        self.categoryId = categoryId
        dataSource = Self.makeDataSource(collectionView: collectionView,
                                         categoryId: categoryId,
                                         exploreVM: exploreVM,
                                         viewOutput: viewOutput,
                                         backgroundColorSUI: backgroundColorSUI)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Overriden

    override var hideNavigationBar: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        initialSetup()

        applySnapshot(animated: false)
        exploreVM.refresh() // for what? all data exist when screen opened

        cancelBag.formUnion([
            viewOutput.dappItemTap.sink(withUnretained: self) { uSelf, site in uSelf.openDapp(site: site) },
        ])
    }
    
    override func updateMaxContentWidthIfNeeded() {} // superclass imp breaks layout, override with empty imp
    override func updateBottomBarBlurConstraint() {} // superclass imp breaks layout, override with empty imp
    
    override func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(.zero, animated: animated)
    }

    // MARK: - Initial Setup

    private func initialSetup() {
        navigationItem.title = exploreVM.exploreCategories[categoryId]?.displayName ?? ""
        
        view.backgroundColor = backgroundColor
        view.addStretchedToSafeArea(subview: collectionView,
                                    top: \.topAnchor,
                                    insets: UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20))
        
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.delaysContentTouches = false
        collectionView.clipsToBounds = false
        
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

    private static func makeDataSource(collectionView: UICollectionView,
                                       categoryId: Int,
                                       exploreVM: ExploreVM,
                                       viewOutput: ViewOutput,
                                       backgroundColorSUI: Color) -> UICollectionViewDiffableDataSource<Section, Item> {
        // Register cell
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            cell.backgroundColor = nil
            switch item {
            case .dapp(let siteId):
                if let site = exploreVM.exploreSites[siteId] {
                    cell.configurationUpdateHandler = { cell, _ in
                        cell.contentConfiguration = UIHostingConfiguration {
                            ExploreCategoryRow(site: site, openAction: {
                                viewOutput.dappItemTap.send(site)
                            })
                        }
                        .margins(.all, 0)
                        // Disable the default highlight effect on cell selection, while still allowing didSelectItemAt to trigger
                        .background { backgroundColorSUI }
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
    private struct ViewOutput {
        let dappItemTap = PassthroughSubject<ApiSite, Never>()
    }

    enum Section: Equatable, Hashable {
        case main
    }

    enum Item: Equatable, Hashable {
        case dapp(url: String)
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    let vc: ExploreCategoryVC = {
        let vc = ExploreVC()
        vc.exploreVM.updateExploreSites(ApiSite.sampleExploreSites)
        vc.exploreVM.updateDapps(dapps: [ApiDapp.sample])
        let cat = ExploreCategoryVC(exploreVM: vc.exploreVM, categoryId: 1)
        cat.view.backgroundColor = .black.withAlphaComponent(0.1)
        return cat
    }()
    vc
}
#endif
