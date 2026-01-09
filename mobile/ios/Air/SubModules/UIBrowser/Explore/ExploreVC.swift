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

let maxWidth: CGFloat = 600
var effectiveScreenWidth: CGFloat { min(screenWidth, maxWidth) }
var featuredItemWidth: CGFloat { effectiveScreenWidth - 20 * 2 }

public class ExploreVC: WViewController {

    var exploreVM: ExploreVM = ExploreVM()
    private(set) var collectionView: UICollectionView?
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>?
    
    private var previousOffset: CGFloat = 0

    var searchString: String = ""
    var onSelectAny: () -> () = { }
    
    public var scrollingView: UIScrollView? {
        return collectionView
    }
    
    enum Section: Equatable, Hashable {
        case connected
        case trending
        case all
        case searchResults
        
        var localizedTitle: String {
            switch self {
            case .connected:
                lang("Connected")
            case .trending:
                lang("Trending")
            case .all:
                lang("Popular Apps")
            case .searchResults:
                ""
            }
        }
    }
    enum Item: Equatable, Hashable {
        case connected(String)
        case connectedSettings
        case trendingDapp(String)
        case dapp(String)
        case expandCategory(_ categoryId: Int, _ itemIds: [String])
        case searchResult(String)
    }

    private var source: CGRect?

    var preferLargeIcons: Bool { exploreVM.connectedDapps.count > 3 }

    private var usingLargeIcons: Bool = false

    public init() {
        super.init(nibName: nil, bundle: nil)
        exploreVM.delegate = self
        Task {
            try? await Task.sleep(for: .seconds(4))
            if !self.isViewLoaded {
                // preload
                loadExploreSites()
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        exploreVM.refresh()
    }
    
    public func loadExploreSites() {
        exploreVM.loadExploreSites()
    }
    
    struct Constants {
        static let trendingHeader = "trendingHeader"
        static let popularAppsHeader = "popularAppsHeader"
        static let appFolderHeader = "appFolderHeader"
        static let appFolderBackground = "appFolderBackground"
    }
    
    private func setupViews() {
        view.translatesAutoresizingMaskIntoConstraints = false
        
        // configure collection view
        
        let layout = makeLayout()
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView = collectionView
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "trending")
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "exploreSite")
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "expandCategory")
        
        collectionView.register(UICollectionViewCell.self, forSupplementaryViewOfKind: Constants.trendingHeader, withReuseIdentifier: Constants.trendingHeader)
        collectionView.register(UICollectionViewCell.self, forSupplementaryViewOfKind: Constants.popularAppsHeader, withReuseIdentifier: Constants.popularAppsHeader)
        collectionView.register(UICollectionViewCell.self, forSupplementaryViewOfKind: Constants.appFolderHeader, withReuseIdentifier: Constants.appFolderHeader)
        collectionView.register(UICollectionViewCell.self, forSupplementaryViewOfKind: Constants.appFolderBackground, withReuseIdentifier: Constants.appFolderBackground)
        
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.delaysContentTouches = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        edgesForExtendedLayout = .bottom
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            collectionView.widthAnchor.constraint(equalTo: view.widthAnchor).withPriority(.defaultHigh),
            collectionView.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
        ])
        collectionView.contentInset.top = 0
        collectionView.contentInset.bottom = 70 + 21 + 16
        collectionView.verticalScrollIndicatorInsets.top = 0
        collectionView.verticalScrollIndicatorInsets.bottom = 70

        dataSource = makeDataSource(collectionView: collectionView)
        applySnapshot(animated: false)
        
        updateTheme()
    }
    
    func makeDataSource(collectionView: UICollectionView) -> UICollectionViewDiffableDataSource<Section, Item> {
        
        let connnected = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, indexPath, itemIdentifier in
            if let self, let dapp = exploreVM.connectedDapps[itemIdentifier] {
                cell.configurationUpdateHandler = { cell, state in
                    cell.contentConfiguration = UIHostingConfiguration {
                        if self.preferLargeIcons {
                            ConnectedDappCellLarge(dapp: dapp, isHighlighted: state.isHighlighted)
                        } else {
                            ConnectedDappCell(dapp: dapp, isHighlighted: state.isHighlighted)
                        }
                    }
                    .margins(.all, 0)
                }
            }
        }
        let connnectedSettings = UICollectionView.CellRegistration<UICollectionViewCell, ()> { [weak self] cell, indexPath, itemIdentifier in
            cell.configurationUpdateHandler = { cell, state in
                guard let self else { return }
                cell.contentConfiguration = UIHostingConfiguration {
                    if self.preferLargeIcons {
                        ConnectedSettingsCellLarge(isHighlighted: state.isHighlighted)
                    } else {
                        ConnectedSettingsCell(isHighlighted: state.isHighlighted)
                    }
                }
                .margins(.all, 0)
            }
        }
        let trendingDapp = UICollectionView.CellRegistration<UICollectionViewCell, String> {
            [weak self] cell,
            indexPath,
            itemIdentifier in
            guard let site = self?.exploreVM.exploreSites[itemIdentifier] else { return }
            cell.configurationUpdateHandler = {
                [weak self] cell,
                state in
                cell.contentConfiguration = UIHostingConfiguration {
                    FeaturedDappCell(
                        item: site,
                        isHighlighted: state.isHighlighted,
                        openAction: { [weak self] in self?.openDapp(id: itemIdentifier)
                        }
                    )
                    .frame(width: featuredItemWidth)
                }
                .margins(.all, 0)
                .minSize(width: featuredItemWidth, height: nil)
            }
        }
        let dapp = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, indexPath, itemIdentifier in
            guard let self, let site = exploreVM.exploreSites[itemIdentifier] else { return }
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    DappCell(item: site, isHighlighted: state.isHighlighted)
                }
                .margins(.all, 8)
            }
        }
        let expandCategory = UICollectionView.CellRegistration<UICollectionViewCell, [String]> { [weak self] cell, indexPath, itemIds in
            guard let self else { return }
            let items = itemIds.compactMap({ self.exploreVM.exploreSites[$0] })
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    MoreItemsCell(items: items, isHighlighted: state.isHighlighted)
                }
                .margins(.all, 8)
            }
        }
        let searchResult = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, indexPath, itemIdentifier in
            guard let self, let site = exploreVM.exploreSites[itemIdentifier] else { return }
            cell.configurationUpdateHandler = { cell, state in
                cell.contentConfiguration = UIHostingConfiguration {
                    ExploreCategoryRow(site: site, openAction: { [weak self] in self?.openDapp(id: itemIdentifier) })
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
            cell.backgroundConfiguration?.cornerRadius = 16
        }
        let dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .connected(let dappId):
                collectionView.dequeueConfiguredReusableCell(using: connnected, for: indexPath, item: dappId)
            case .connectedSettings:
                collectionView.dequeueConfiguredReusableCell(using: connnectedSettings, for: indexPath, item: ())
            case .trendingDapp(let siteId):
                collectionView.dequeueConfiguredReusableCell(using: trendingDapp, for: indexPath, item: siteId)
            case .dapp(let siteId):
                collectionView.dequeueConfiguredReusableCell(using: dapp, for: indexPath, item: siteId)
            case .expandCategory(_, let itemIds):
                collectionView.dequeueConfiguredReusableCell(using: expandCategory, for: indexPath, item: itemIds)
            case .searchResult(let siteId):
                collectionView.dequeueConfiguredReusableCell(using: searchResult, for: indexPath, item: siteId)
            }
        }
        
        let trendingHeader = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(elementKind: Constants.trendingHeader) { [weak self] cell, _, indexPath in
            if let id = dataSource.sectionIdentifier(for: indexPath.section) {
                let title = if id == .trending {
                    if let featuredTitle = self?.exploreVM.featuredTitle, !featuredTitle.isEmpty {
                        lang(featuredTitle)
                    } else {
                        lang("Trending")
                    }
                } else {
                    id.localizedTitle
                }
                cell.contentConfiguration = UIHostingConfiguration {
                    TrendingHeader(title: title)
                }
                .margins(.top, indexPath.section == 0 ? 16 : 28)
                .margins(.bottom, 4)
                .margins(.horizontal, 4)
            }
        }
        let popularAppsHeader = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(elementKind: Constants.popularAppsHeader) { cell, _, indexPath in
            if let id = dataSource.sectionIdentifier(for: indexPath.section) {
                let title = id.localizedTitle
                cell.contentConfiguration = UIHostingConfiguration {
                    PopularAppsHeader(title: title)
                }
                .margins(.top, 26)
                .margins(.bottom, 24)
            }
        }
        let appFolderHeader = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(elementKind: Constants.appFolderHeader) { [weak self] cell, _, indexPath in
            guard let self, let cat = exploreVM.exploreCategories[indexPath.item + 1] else { return }
            cell.contentConfiguration = UIHostingConfiguration {
                AppFolderHeader(cat: cat)
            }
            .margins(.all, 0)
        }
        let appFolderBackground = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(elementKind: Constants.appFolderBackground) { cell, _, indexPath in
            cell.contentConfiguration = UIHostingConfiguration {
                AppFolderBackground()
            }
            .margins(.all, 0)
        }
        dataSource.supplementaryViewProvider = { collectionView, elementKind, indexPath in
            switch elementKind {
            case Constants.trendingHeader:
                collectionView.dequeueConfiguredReusableSupplementary(using: trendingHeader, for: indexPath)
            case Constants.popularAppsHeader:
                collectionView.dequeueConfiguredReusableSupplementary(using: popularAppsHeader, for: indexPath)
            case Constants.appFolderHeader:
                collectionView.dequeueConfiguredReusableSupplementary(using: appFolderHeader, for: indexPath)
            case Constants.appFolderBackground:
                collectionView.dequeueConfiguredReusableSupplementary(using: appFolderBackground, for: indexPath)
            default:
                nil
            }
        }
        return dataSource
    }
    
    func makeLayout() -> UICollectionViewCompositionalLayout {
        
        let groupSize = floor((effectiveScreenWidth - 16 * 2 - 12) / 2)
        
        let connectedSection: NSCollectionLayoutSection
        do {
            let horizontalInset: CGFloat = 20
            if preferLargeIcons {
                let interItemSpacing: CGFloat = 12
                let minItemWidth: CGFloat = 60
                let availableWidth = effectiveScreenWidth - horizontalInset * 2
                let columns = max(1, Int(floor((availableWidth + interItemSpacing) / (minItemWidth + interItemSpacing))))
                let itemFraction = CGFloat(1.0) / CGFloat(columns)

                let item = NSCollectionLayoutItem(
                    layoutSize: .init(.fractionalWidth(itemFraction), .estimated(92))
                )
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(.fractionalWidth(1.0), .estimated(92)),
                    repeatingSubitem: item,
                    count: columns
                )
                group.interItemSpacing = .fixed(interItemSpacing)

                connectedSection = NSCollectionLayoutSection(group: group)
                connectedSection.contentInsets = .init(top: 16, leading: horizontalInset, bottom: 0, trailing: horizontalInset)
                connectedSection.interGroupSpacing = 11
            } else {
                let item = NSCollectionLayoutItem(
                    layoutSize: .init(.estimated(100), .absolute(36))
                )
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(.estimated(100), .absolute(36)),
                    subitems: [item]
                )
                connectedSection = NSCollectionLayoutSection(group: group)
                connectedSection.orthogonalScrollingBehavior = .continuous
                connectedSection.contentInsets = .init(top: 16, leading: horizontalInset, bottom: 8, trailing: horizontalInset)
                connectedSection.interGroupSpacing = 8
            }
        }
        
        let trendingSection: NSCollectionLayoutSection
        do {
            let item = NSCollectionLayoutItem(
                layoutSize: .init(.estimated(192), .estimated(192))
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(.absolute(featuredItemWidth), .estimated(192)),
                subitems: [item]
            )
            trendingSection = NSCollectionLayoutSection(group: group)
            trendingSection.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
            if #available(iOS 17.0, *) {
                trendingSection.orthogonalScrollingProperties.decelerationRate = .fast
            }
            trendingSection.contentInsets = .init(top: 8, leading: 20, bottom: 8, trailing: 20)
            trendingSection.interGroupSpacing = 12
            
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: .init(.fractionalWidth(1.0), .estimated(22)),
                elementKind: Constants.trendingHeader,
                alignment: .top
            )
            trendingSection.boundarySupplementaryItems = [header]
        }
        
        let mainSection: NSCollectionLayoutSection
        do {
            let item = NSCollectionLayoutItem(
                layoutSize: .init(.fractionalWidth(0.5), .fractionalHeight(1.0))
            )
            
            let horizontalPair = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(.fractionalWidth(1.0), .fractionalHeight(0.5)),
                repeatingSubitem: item,
                count: 2
            )
            horizontalPair.interItemSpacing = .fixed(0) // each item has 8 pt margins, so this results in efffective 16 pt spacing
            
            let twoByTwo = NSCollectionLayoutGroup.vertical(
                layoutSize: .init(.fractionalWidth(0.5), .fractionalWidth(0.5)),
                repeatingSubitem: horizontalPair,
                count: 2
            )
            twoByTwo.contentInsets = .zero
            twoByTwo.interItemSpacing = .fixed(0)
            twoByTwo.contentInsets = .init(top: 8, leading: 8, bottom: 8, trailing: 8)
            
            let folderBackground = NSCollectionLayoutSupplementaryItem(
                layoutSize: .init(.absolute(groupSize), .absolute(groupSize)),
                elementKind: Constants.appFolderBackground,
                containerAnchor: .init(edges: [.top, .leading]),
                itemAnchor: .init(edges: [.top, .leading])
            )
            folderBackground.zIndex = -1
            
            let folderLabel = NSCollectionLayoutSupplementaryItem(
                layoutSize: .init(.absolute(groupSize), .absolute(44)),
                elementKind: Constants.appFolderHeader,
                containerAnchor: .init(edges: [.bottom]),
                itemAnchor: .init(edges: [.top])
            )
            folderLabel.zIndex = -1
            
            twoByTwo.supplementaryItems = [folderBackground, folderLabel]
            
            let row = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(.fractionalWidth(1.0), .estimated(groupSize)),
                repeatingSubitem: twoByTwo,
                count: 2
            )
            row.interItemSpacing = .fixed(12)
            
            mainSection = NSCollectionLayoutSection(group: row)
            mainSection.contentInsets = .init(top: 0, leading: 16, bottom: 8, trailing: 16)
            mainSection.interGroupSpacing = 41
            
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: .init(.fractionalWidth(1), .estimated(44)),
                elementKind: Constants.popularAppsHeader,
                alignment: .top
            )
            mainSection.boundarySupplementaryItems = [header]
        }
        
        let searchResultsSection: (any NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection = { env in
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            config.headerMode = .none
            config.backgroundColor = .clear
            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            } else {
                config.separatorConfiguration.color = WTheme.separator
            }
            let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: env)
            section.contentInsets.top = 8
            return section
        }

        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] idx, env in
            if let id = self?.dataSource?.sectionIdentifier(for: idx) {
                switch id {
                case .connected:
                    return connectedSection
                case .trending:
                    return trendingSection
                case .all:
                    return mainSection
                case .searchResults:
                    return searchResultsSection(env)
                }
            }
            return nil
        })
        return layout
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.background
        collectionView?.backgroundColor = WTheme.background
        collectionView?.reloadData()
    }

    public override func scrollToTop(animated: Bool) {
        if let collectionView {
            collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
        }
    }

    func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        let exploreSites = exploreVM.exploreSites
        let exploreCategories = exploreVM.exploreCategories
        let searchString = self.searchString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if searchString.isEmpty {
            let connectedDapps = exploreVM.connectedDapps
            if !connectedDapps.isEmpty {
                snapshot.appendSections([.connected])
                snapshot.appendItems(connectedDapps.map { (key, value) in Item.connected(key) })
                snapshot.appendItems([.connectedSettings])
                
                snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .connected))
            }
            
            let trendingSites = exploreSites.values.filter { $0.isFeatured == true }
            if !trendingSites.isEmpty {
                snapshot.appendSections([.trending])
                snapshot.appendItems(trendingSites.map { .trendingDapp($0.url) })
            }
            
            if !exploreSites.isEmpty {
                snapshot.appendSections([.all])
                for category in exploreCategories.values {
                    let categorySites = exploreSites.values.filter { $0.categoryId == category.id }
                    if categorySites.count <= 4 {
                        snapshot.appendItems(categorySites.map { .dapp($0.url) })
                    } else {
                        snapshot.appendItems(categorySites.prefix(3).map { .dapp($0.url) })
                        
                        let more = categorySites.dropFirst(3).map { $0.url }
                        snapshot.appendItems([.expandCategory(category.id, more)])
                    }
                }
            }
        } else {
            snapshot.appendSections([.searchResults])
            snapshot.appendItems(
                exploreSites.values
                    .filter { $0.matches(searchString) }
                    .map { Item.searchResult($0.url) }
            )
        }

        return snapshot
    }
    
    func applySnapshot(animated: Bool) {
        let preferLargeIcons = self.preferLargeIcons
        if preferLargeIcons != self.usingLargeIcons {
            self.usingLargeIcons = preferLargeIcons
            collectionView?.setCollectionViewLayout(makeLayout(), animated: false)
        }

        let snapshot = makeSnapshot()
        dataSource?.apply(snapshot, animatingDifferences: animated)
    }
}

extension ExploreVC: UICollectionViewDelegate {
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource?.itemIdentifier(for: indexPath) else { return }
        view.window?.endEditing(true)
        onSelectAny()
        switch id {
        case .connected(let id):
            if let connected = exploreVM.connectedDapps[id], let url = URL(string: connected.url) {
                AppActions.openInBrowser(url)
            }
            
        case .connectedSettings:
            AppActions.showConnectedDapps(push: false)

        case .trendingDapp(let id), .dapp(let id):
            openDapp(id: id)

        case .expandCategory(let catId, _):
            let vc = ExploreCategoryVC(exploreVM: exploreVM, categoryId: catId)
            vc.modalPresentationStyle = .custom
            vc.transitioningDelegate = self
            present(vc, animated: true)
            
        case .searchResult(let siteId):
            openDapp(id: siteId)
        }
    }
    
    func openDapp(id: String) {
        view.window?.endEditing(true)
        onSelectAny()
        guard let exploreSite = exploreVM.exploreSites[id], let url = URL(string: exploreSite.url) else {
            return
        }
        if exploreSite.shouldOpenExternally {
            UIApplication.shared.open(url)
        } else {
            AppActions.openInBrowser(url)
        }
    }
}

extension ExploreVC: ExploreVMDelegate {
    func exploreSitsUpdated() {
        applySnapshot(animated: true)
    }
}


// MARK: - Explore category presentation

extension ExploreVC: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return CattegoryDappsPresentationController(presentedViewController: presented, presenting: presenting)
    }
    
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        var sourceFrame = CGRect()
        if let vc = source as? ExploreVC, let idx = vc.collectionView?.indexPathsForSelectedItems?.first, let cell = collectionView?.cellForItem(at: idx) {
            sourceFrame = view.convert(cell.bounds, from: cell)
        }
        self.source = sourceFrame
        return CategoryDappsAnimator(sourceFrame: sourceFrame, dismissing: false)
    }
    
    public func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        var sourceFrame = CGRect()
        if let source {
            sourceFrame = source
        }
        
        return CategoryDappsAnimator(sourceFrame: sourceFrame, dismissing: true)
    }
}


final class CattegoryDappsPresentationController: UIPresentationController {
    
    private var blurView: WBlurView?
    
    override func presentationTransitionWillBegin() {
        let blurView = WBlurView()
        self.blurView = blurView
        self.containerView?.addSubview(blurView)
        blurView.alpha = 0
        let window: UIView = presentingViewController.view.window ?? presentingViewController.view
        blurView.frame = window.bounds
        presentingViewController.transitionCoordinator?.animate(alongsideTransition: { ctx in
            blurView.alpha = 1
        })
    }
    
    override func presentationTransitionDidEnd(_ completed: Bool) {
    }
    
    override func dismissalTransitionWillBegin() {
        if let blurView {
            presentingViewController.transitionCoordinator?.animate(alongsideTransition: { ctx in
                blurView.alpha = 0
            })
        }
    }
}


final class CategoryDappsAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    
    let sourceFrame: CGRect
    let dismissing: Bool
    
    init(sourceFrame: CGRect, dismissing: Bool) {
        self.sourceFrame = sourceFrame
        self.dismissing = dismissing
    }
    
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        return dismissing ? 0.375 : 0.4
    }
    
    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        if !dismissing {
            guard let to = transitionContext.viewController(forKey: .to) else { transitionContext.completeTransition(false); return }
            transitionContext.containerView.addSubview(to.view)
            to.view.alpha = 0.0
            to.view.center = sourceFrame.center
            to.view.bounds = CGRect(x: 0, y: 0, width: transitionContext.finalFrame(for: to).width, height: transitionContext.finalFrame(for: to).height)
            to.view.transform = .identity.scaledBy(x: 0.2, y: 0.2)
            UIView.animate(withDuration: self.transitionDuration(using: transitionContext), delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.1) {
                to.view.alpha = 1
                to.view.transform = .identity
                to.view.center = transitionContext.finalFrame(for: to).center
            } completion: { ok in
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            }
        } else {
            guard let from = transitionContext.viewController(forKey: .from) else { transitionContext.completeTransition(false); return }
            UIView.animate(withDuration: self.transitionDuration(using: transitionContext), delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) {
                from.view.alpha = 0.0
                from.view.center = self.sourceFrame.center
                from.view.transform = .identity.scaledBy(x: 0.2, y: 0.2)
            } completion: { ok in
                transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            }
        }
    }
}


// MARK: - Collection view supplementary views


fileprivate struct TrendingHeader: View {
    
    var title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

fileprivate struct PopularAppsHeader: View {
    
    var title: String
    
    var body: some View {
        let line = RoundedRectangle(cornerRadius: 0.75, style: .circular)
            .fill()
            .foregroundStyle(Color.airBundle("FolderFillColor"))
            .frame(width: 64, height: 1.5)
            .offset(y: 2)

        HStack(spacing: 12) {
            line
            Text(title)
                .font(.system(size: 20, weight: .bold))
            line
        }
        .fixedSize()
    }
}

fileprivate struct AppFolderHeader: View {
    
    var cat: ApiSiteCategory
    
    var body: some View {
        Text(cat.displayName)
            .font(.system(size: 13, weight: .medium))
            .offset(x: 8, y: 8)
    }
}

fileprivate struct AppFolderBackground: View {
    
    var body: some View {
        Color.airBundle("FolderFillColor")
            .clipShape(.rect(cornerRadius: 32))
    }
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    let vc: ExploreVC = {
        let vc = ExploreVC()
        vc.exploreVM.updateExploreSites(ApiSite.sampleExploreSites)
        vc.exploreVM.updateDapps(dapps: Array(ApiDapp.sampleList.prefix(5)))
        return vc
    }()
    vc
}
#endif
