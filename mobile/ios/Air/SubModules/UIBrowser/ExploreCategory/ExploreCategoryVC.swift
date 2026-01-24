//
//  ExploreVC.swift
//  UIBrowser
//
//  Created by Sina on 6/25/24.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Kingfisher


class ExploreCategoryVC: WViewController {
    
    var exploreVM: ExploreVM
    var categoryId: Int
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var gestureRecognizer: UIGestureRecognizer!
    private var shadowView: UIView!
    
    enum Section: Equatable, Hashable {
        case main
    }
    enum Item: Equatable, Hashable {
        case dapp(String)
    }

    public override var hideNavigationBar: Bool { true }

    init(exploreVM: ExploreVM, categoryId: Int) {
        self.exploreVM = exploreVM
        self.categoryId = categoryId
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Load and SetupView Functions
    override func loadView() {
        super.loadView()
        setupViews()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        exploreVM.refresh()
    }
    enum Constants {
        static let background = "background"
        static let groupHeader = "groupHeader"
        static let sectionHeader = "sectionHeader"
    }

    
    private func setupViews() {
        title = lang("Explore")
        navigationBar?.isHidden = true
        
        // Configure collection view with list layout
        let layout = makeLayout()
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.delaysContentTouches = false
        
        edgesForExtendedLayout = .bottom
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])

        gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(onTap))
        view.addGestureRecognizer(gestureRecognizer)
        gestureRecognizer.delegate = self
        
        shadowView = UIView()
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.backgroundColor = .white
        shadowView.layer.shadowColor = UIColor.black.withAlphaComponent(0.1).cgColor
        shadowView.layer.shadowRadius = 32
        shadowView.layer.shadowOpacity = 1
        shadowView.layer.cornerRadius = S.homeInsetSectionCornerRadius
        collectionView.insertSubview(shadowView, at: 0)
        
        dataSource = makeDataSource()
        applySnapshot(animated: false)
        
        DispatchQueue.main.async { [self] in
            let visibleCells = collectionView.visibleCells
            if let first = visibleCells.first {
                let frame = visibleCells
                    .map(\.frame)
                    .reduce(first.frame) { $0.union($1) }
                shadowView.frame = frame.insetBy(dx: 4, dy: 4)
                collectionView.sendSubviewToBack(shadowView)
            }
        }
        
        updateTheme()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.contentInset.top = max((collectionView.bounds.height - CGFloat(dataSource.snapshot().numberOfItems) * 80 - 170) / 2, 0)
    }
    
    override func updateTheme() {
        view.backgroundColor = .clear
        collectionView.backgroundColor = .clear
    }

    override func scrollToTop(animated: Bool) {
        collectionView?.setContentOffset(CGPoint(x: 0, y: -collectionView.contentInset.top), animated: animated)
    }

    func makeLayout() -> UICollectionViewCompositionalLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .supplementary
        config.backgroundColor = .clear
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
        } else {
            config.separatorConfiguration.color = WTheme.separator
        }
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        return layout
    }
    
    func makeDataSource() -> UICollectionViewDiffableDataSource<Section, Item> {
        // Register cell
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [weak self] cell, indexPath, item in
            guard let self = self else { return }
            
            switch item {
            case .dapp(let siteId):
                if let site = self.exploreVM.exploreSites[siteId] {
                    cell.configurationUpdateHandler = { cell, state in
                        cell.contentConfiguration = UIHostingConfiguration {
                            ExploreCategoryRow(site: site, openAction: { [weak self] in self?.handleOpen(site: site) })
                        }
                        .background {
                            ZStack {
                                Color(WTheme.groupedItem)
                                Color.clear
                                    .highlightBackground(state.isHighlighted)
                            }
                        }
                        .minSize(height: 80)
                    }
                    cell.backgroundConfiguration?.cornerRadius = S.homeInsetSectionCornerRadius
                }
            }
        }
        
        let categoryId = self.categoryId
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] headerView, elementKind, indexPath in
            headerView.contentConfiguration = UIHostingConfiguration {
                Text(self?.exploreVM.exploreCategories[categoryId]?.displayName ?? "")
                    .font(.system(size: 23, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        Button(action: { [weak self] in self?.onTap() }) {
                            ZStack {
                                Color.white.opacity(1)
                                Image(uiImage: .airBundle("XMark"))
                                    .renderingMode(.template)
                                    .foregroundStyle(Color(WTheme.secondaryLabel))
                            }
                            .frame(width: 30, height: 30)
                            .clipShape(.circle)
                            .contentShape(.circle)
                        }
                    }
            }.margins(.bottom, 20)
        }
        
        let dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) {
            collectionView, indexPath, item in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
        
        dataSource.supplementaryViewProvider = { collectionView, elementKind, indexPath in
            return collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
        
        return dataSource
    }
    
    func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        var exploreSites = exploreVM.exploreSites.values.filter { $0.categoryId == categoryId }
        if ConfigStore.shared.shouldRestrictSites {
            exploreSites = exploreSites.filter { !$0.canBeRestricted }
        }
        
        if !exploreSites.isEmpty {
            snapshot.appendSections([.main])
            snapshot.appendItems(exploreSites.map { .dapp($0.url) })
        }

        return snapshot
    }
    
    func applySnapshot(animated: Bool) {
        let snapshot = makeSnapshot()
        dataSource.apply(snapshot, animatingDifferences: animated)
    }
    
    @objc func onTap() {
        presentingViewController?.dismiss(animated: true)
    }

}
    
extension ExploreCategoryVC: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let id = dataSource.itemIdentifier(for: indexPath)
        switch id {
        case .dapp(let id):
            guard let exploreSite = exploreVM.exploreSites[id] else {
                return
            }
            handleOpen(site: exploreSite)
            
        case .none:
            break
        }
        collectionView.deselectItem(at: indexPath, animated: true)
    }
    
    func handleOpen(site: ApiSite) {
        guard let url = URL(string: site.url) else { return }
        if site.shouldOpenExternally {
            UIApplication.shared.open(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.presentingViewController?.dismiss(animated: true)
            }
        } else {
            if let homeVC = presentingViewController, let window = self.view.window {
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
                AppActions.openInBrowser(url)
            }
        }
    }
}

extension ExploreCategoryVC: ExploreVMDelegate {
    func exploreSitsUpdated() {
        applySnapshot(animated: true)
    }
}

extension ExploreCategoryVC: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return collectionView.hitTest(touch.location(in: collectionView), with: nil) === collectionView
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

fileprivate extension NSCollectionLayoutSize {
    convenience init(_ width: NSCollectionLayoutDimension, _ height: NSCollectionLayoutDimension) {
        self.init(widthDimension: width, heightDimension: height)
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
