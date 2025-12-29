//
//  WalletTokensView.swift
//  UIHome
//
//  Created by Sina on 3/25/24.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("WalletTokensView")


@MainActor public protocol WalletTokensViewDelegate: AnyObject {
    func didSelect(slug: String?)
    func goToStakedPage(slug: String)
    func goToTokens()
}


public class WalletTokensView: UITableView, WSegmentedControllerContent, WThemedView {

    private enum Section {
        case main
        case seeAll
    }
    private enum Item: Equatable,Hashable {
        case token(String, Bool)
        case placeholder(Int)
        case seeAll
    }

    private let compactMode: Bool
    private weak var walletTokensViewDelegate: WalletTokensViewDelegate? = nil
    private var animatedAmounts = true
    private let processorQueue = DispatchQueue(label: "org.mytonwallet.app.wallet_tokens_background_processor",
                                       attributes: .concurrent)
    
    private var walletTokens: [MTokenBalance]? = nil
    private var allTokensCount = 0
    private var placeholderCount = 4
    
    var accountId: String = ""
    
    private var _dataSource: UITableViewDiffableDataSource<Section, Item>!
    
    private let queue = DispatchQueue(label: "WalletTokensView", qos: .userInitiated)
    
    private var shouldShowSeeAll: Bool {
        if let walletTokens {
            return allTokensCount > walletTokens.count
        }
        return false
    }
    
    public init(compactMode: Bool, delegate: WalletTokensViewDelegate?) {
        self.compactMode = compactMode
        self.walletTokensViewDelegate = delegate
        super.init(frame: .zero, style: .plain)
        setupViews()
    }
    
    public required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        delegate = self
        if compactMode {
            bounces = false
            isScrollEnabled = false
        }
        separatorStyle = .none
        register(compactMode ? WalletTokenCell.self : AssetsWalletTokenCell.self, forCellReuseIdentifier: "WalletToken")
        register(ActivityCell.self, forCellReuseIdentifier: "Placeholder")
        register(WalletSeeAllCell.self, forCellReuseIdentifier: "SeeAll")
        delaysContentTouches = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .scrollableAxes
        
        _dataSource = makeDataSource()
        _dataSource.defaultRowAnimation = .fade
        applySnapshot(makeSnapshot(), animated: false, animatingDifferences: false)
    }

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, Item> {
        let dataSource = UITableViewDiffableDataSource<Section, Item>(tableView: self) { [unowned self] tableView, indexPath, item in
            switch item {
            case .token(let slug, let isStaked):
                let cell =  tableView.dequeueReusableCell(withIdentifier: "WalletToken", for: indexPath) as! WalletTokenCell
                guard let walletToken = walletTokens?.first(where: { $0.tokenSlug == slug && $0.isStaking == isStaked }) else {
                    log.fault("inconsistent state")
                    return cell
                }
                let badgeContent = getBadgeContent(accountId: accountId, slug: slug, isStaking: isStaked)
                
                let walletTokensCount = walletTokens?.count ?? 0
                cell.configure(with: walletToken,
                               isLast: indexPath.row == walletTokensCount - 1,
                               animated: animatedAmounts,
                               badgeContent: badgeContent,
                               onSelect: { [weak self] in
                    guard let self else { return }
                    let slug = walletToken.tokenSlug
                    if slug == STAKED_TON_SLUG || slug == STAKED_MYCOIN_SLUG || slug == TON_TSUSDE_SLUG || walletToken.isStaking {
                        walletTokensViewDelegate?.goToStakedPage(slug: slug)
                    } else {
                        walletTokensViewDelegate?.didSelect(slug: slug)
                    }
                })
                return cell
            
            case .placeholder:
                let cell = tableView.dequeueReusableCell(withIdentifier: "Placeholder", for: indexPath) as! ActivityCell
                cell.configureSkeleton()
                return cell
            
            case .seeAll:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SeeAll", for: indexPath) as! WalletSeeAllCell
                cell.configure(delegate: self)
                return cell
            }
        }
        return dataSource
    }

    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        if let walletTokens {
            snapshot.appendItems(walletTokens.map { .token($0.tokenSlug, $0.isStaking) })
        } else {
            snapshot.appendItems((0..<placeholderCount).map(Item.placeholder))
        }
        if shouldShowSeeAll {
            snapshot.appendSections([.seeAll])
            snapshot.appendItems([.seeAll])
        }
        return snapshot
    }

    private func applySnapshot(_ snapshot: NSDiffableDataSourceSnapshot<Section, Item>, animated: Bool, animatingDifferences: Bool) {
        var snapshot = snapshot
        snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .main))
        queue.async {
//            self._dataSource.apply(snapshot, animatingDifferences: animated && animatingDifferences)
            self._dataSource.apply(snapshot, animatingDifferences: false)
        }
    }
    
    internal func set(walletTokens newWalletTokens: [MTokenBalance]?, allTokensCount: Int, placeholderCount: Int, animated: Bool = true) {
        let animatingDifferences = self.walletTokens != nil
        self.walletTokens = newWalletTokens
        self.allTokensCount = allTokensCount
        self.placeholderCount = placeholderCount
        applySnapshot(makeSnapshot(), animated: animated, animatingDifferences: animatingDifferences)
    }
    
    func reloadStakeCells(animated: Bool) {
        for cell in visibleCells {
            if let cell = cell as? WalletTokenCell, let walletToken = cell.walletToken {
                let badgeContent = getBadgeContent(accountId: accountId, slug: walletToken.tokenSlug, isStaking: walletToken.isStaking)
                cell.configureBadge(badgeContent: badgeContent)
            }
        }
    }
    
    internal func reconfigureAllRows(animated: Bool) {
        var snapshot = _dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .main))
        queue.async {
            self._dataSource.apply(snapshot, animatingDifferences: animated)
        }
    }
    
    // MARK: - WSegmentedControllerVC
    public var onScroll: ((CGFloat) -> Void)?
    public var onScrollStart: (() -> Void)?
    public var onScrollEnd: (() -> Void)?
    
    public var view: UIView! {
        self
    }
    
    public var title: String? = lang("Assets")
    
    public func scrollToTop(animated: Bool) { }
    
    public var calculatedHeight: CGFloat {
        let itemCount = CGFloat((walletTokens?.count ?? 0) + placeholderCount)
        guard itemCount > 0 else {
            return 0
        }
        return itemCount * WalletTokenCell.defaultHeight + (shouldShowSeeAll ? WalletSeeAllCell.defaultHeight : 0)
    }

    public var scrollingView: UIScrollView? {
        return self
    }
    
    public override func insertRows(at indexPaths: [IndexPath], with animation: UITableView.RowAnimation) {
        super.insertRows(at: indexPaths, with: .fade)
    }
    
    public override func deleteRows(at indexPaths: [IndexPath], with animation: UITableView.RowAnimation) {
        super.deleteRows(at: indexPaths, with: .fade)
    }
}

extension WalletTokensView: UITableViewDelegate {
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case 0:
            WalletTokenCell.defaultHeight
        default:
            WalletSeeAllCell.defaultHeight
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?(scrollView.contentOffset.y + scrollView.contentInset.top)
    }
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        onScrollStart?()
    }
    
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        onScrollEnd?()
    }

    
    public func updateTheme() {
    }
}

extension WalletTokensView: WalletSeeAllCell.Delegate {
    func didSelectSeeAll() {
        walletTokensViewDelegate?.goToTokens()
    }
}
