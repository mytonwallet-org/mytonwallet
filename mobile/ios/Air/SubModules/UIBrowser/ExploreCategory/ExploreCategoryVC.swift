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
    let rectToShowFrom: CGRect?

    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: ExploreCategoryVC.makeLayout())
    private let dataSource: UICollectionViewDiffableDataSource<Section, Item>

    private let viewOutput = ViewOutput()

    private let backgroundColor: UIColor = .air.background
    private let backgroundColorSUI: Color = .air.background

    private var cancelBag = Set<AnyCancellable>()

    init(exploreVM: ExploreVM, categoryId: Int, rectToShowFrom: CGRect?) {
        self.exploreVM = exploreVM
        self.categoryId = categoryId
        self.rectToShowFrom = rectToShowFrom
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

    // MARK: - Initial Setup

    private func initialSetup() {
        addCloseNavigationItemIfNeeded()

        view.backgroundColor = backgroundColor
        view.addStretchedToBounds(subview: collectionView, insets: UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20))

        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.delaysContentTouches = false
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.clipsToBounds = false

        collectionView.contentInset = UIEdgeInsets(top: -16, left: 0, bottom: 0, right: 0)
        if let navigationBarHeight = navigationController?.navigationBar.frame.height {
            collectionView.contentInset.top -= navigationBarHeight
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(closeScreen))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }

    override func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(.zero, animated: animated)
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .grouped)
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
        let categoryId = categoryId
        // Register cell
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            cell.backgroundColor = nil
            switch item {
            case .header:
                let categoryName = exploreVM.exploreCategories[categoryId]?.displayName ?? ""
                cell.contentConfiguration = UIHostingConfiguration {
                    Self.screenHeaderView(categoryName: categoryName)
                }
                .margins(.all, 0)
                .background { backgroundColorSUI }

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
            snapshot.appendItems([.header])
            snapshot.appendItems(exploreSites.map { .dapp($0.url) })
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
        let id = dataSource.itemIdentifier(for: indexPath)
        switch id {
        case .dapp(let id):
            guard let exploreSite = exploreVM.exploreSites[id] else { return }
            openDapp(site: exploreSite)

        case .header, .none:
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
            if let homeVC = presentingViewController, let window = view.window {
                let snapshot = window.snapshotView(afterScreenUpdates: false)!
                homeVC.view.addSubview(snapshot)
                UIView.animate(withDuration: 0.4, delay: 0.4) {
                    snapshot.alpha = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    snapshot.removeFromSuperview()
                }
            }
            self.presentingViewController?.dismiss(animated: false) {
                AppActions.openInBrowser(url, title: site.name, injectTonConnect: true)
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
    fileprivate static func screenHeaderView(categoryName: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(lang("Explore")).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(uiColor: UIColor(hex: "#8A8A8E")))
                    .padding(.bottom, 3)
                Text(categoryName).font(.system(size: 28, weight: .bold))
            }

            Spacer()
        }
        .padding(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
    }

    private struct ViewOutput {
        let dappItemTap = PassthroughSubject<ApiSite, Never>()
    }

    enum Section: Equatable, Hashable {
        case main
    }

    enum Item: Equatable, Hashable {
        case header
        case dapp(String)
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    let vc: ExploreCategoryVC = {
        let vc = ExploreVC()
        vc.exploreVM.updateExploreSites(ApiSite.sampleExploreSites)
        vc.exploreVM.updateDapps(dapps: [ApiDapp.sample])
        let cat = ExploreCategoryVC(exploreVM: vc.exploreVM, categoryId: 1, rectToShowFrom: nil)
        cat.view.backgroundColor = .black.withAlphaComponent(0.1)
        return cat
    }()
    vc
}
#endif
