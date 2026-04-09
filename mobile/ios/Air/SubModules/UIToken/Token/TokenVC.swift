//
//  TokenVC.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/1/24.
//

import UIKit
import UIActivityList
import UIComponents
import WalletCore
import WalletContext

private let log = Log("TokenVC")

@MainActor
public class TokenVC: ActivityListViewController, Sendable, WSensitiveDataProtocol {

    private var tokenVM: TokenVM!

    @AccountContext private var account: MAccount
    private let token: ApiToken
    private let isInModal: Bool
    private var accountContext: AccountContext { $account }

    private var headerBlurView: WBlurView!
    private let bottomSeparatorView = UIView()

    public init(accountSource: AccountSource, token: ApiToken, isInModal: Bool) async {
        self._account = AccountContext(source: accountSource)
        self.token = token
        self.isInModal = isInModal
        super.init(nibName: nil, bundle: nil)
        configureCustomSections()
        let accountId = $account.accountId
        self.activityViewModel = await ActivityListViewModel(accountId: accountId, token: token, customSectionIDs: customSectionIDs, delegate: self)
        tokenVM = TokenVM(accountId: accountId,
                                           selectedToken: token,
                                           tokenVMDelegate: self)
        tokenVM.refreshTransactions()
    }
    
    public override var hideBottomBar: Bool {
        false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var navigationTitleView: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.text = token.name
        label.textAlignment = .center
        label.alpha = 0
        return label
    }()

    private lazy var expandableContentView = TokenExpandableContentView(
        accountContext: accountContext,
        isInModal: isInModal
    )
    private let chartCustomSectionID = "chart"
    private var chartCustomSectionCellRegistration: UICollectionView.CellRegistration<TokenChartCell, Row>!
    private var chartCustomSectionDescriptor: CustomSectionDescriptor!

    private func updateHeaderHeight() {
        reconfigureHeaderPlaceholder(animated: false)
    }

    public override var headerPlaceholderHeight: CGFloat {
        expandableContentView.expandedHeight + 32
    }

    private var tokenChartCell: TokenChartCell? = nil
    private var chartCustomSectionHeight: CGFloat {
        return 56 + (tokenChartCell?.height ??
            (AppStorageHelper.isTokenChartExpanded ? TokenExpandableChartView.expandedHeight : TokenExpandableChartView.collapsedHeight)
        )
    }
    public override var customSections: [CustomSectionDescriptor] { [chartCustomSectionDescriptor] }
    private func configureChartCustomSection(cell: TokenChartCell) {
        tokenChartCell = cell
        cell.setup(onHeightChange: { [weak self] in
            self?.updateHeaderHeight()
        })
        cell.configure(token: token,
                       historyData: tokenVM.historyData) { [weak self] period in
            guard let self else { return }
            tokenVM.selectedPeriod = period
        }
    }
    private func configureCustomSections() {
        chartCustomSectionCellRegistration = UICollectionView.CellRegistration<TokenChartCell, Row> { [unowned self] cell, _, _ in
            cell.backgroundColor = .clear
            configureChartCustomSection(cell: cell)
        }
        chartCustomSectionDescriptor = CustomSectionDescriptor(id: chartCustomSectionID) { [unowned self] collectionView, indexPath in
            collectionView.dequeueConfiguredReusableCell(using: chartCustomSectionCellRegistration, for: indexPath, item: .custom(chartCustomSectionID))
        }
    }

    public override func loadView() {
        super.loadView()
        setupViews()
    }

    private func setupViews() {
        navigationItem.titleView = navigationTitleView
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: makeMenu())
        if !IOS_26_MODE_ENABLED {
            configureNavigationItemWithTransparentBackground()
        }
        
        navigationController?.setNavigationBarHidden(false, animated: false)

        super.setupTableViews(tableViewBottomConstraint: 0)
        UIView.performWithoutAnimation {
            applySnapshot(makeSnapshot(), animatingDifferences: false)
            updateSkeletonState()
        }

        view.addSubview(expandableContentView)
        NSLayoutConstraint.activate([
            expandableContentView.topAnchor.constraint(equalTo: view.topAnchor),
            expandableContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            expandableContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        headerBlurView = WBlurView()
        headerBlurView.alpha = 0
        headerBlurView.isUserInteractionEnabled = false
        view.addSubview(headerBlurView)
        NSLayoutConstraint.activate([
            headerBlurView.topAnchor.constraint(equalTo: view.topAnchor),
            headerBlurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBlurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBlurView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        ])

        bottomSeparatorView.translatesAutoresizingMaskIntoConstraints = false
        bottomSeparatorView.isUserInteractionEnabled = false
        bottomSeparatorView.backgroundColor = UIColor { .air.separator.withAlphaComponent($0.userInterfaceStyle == .dark ? 0.8 : 0.2) }
        bottomSeparatorView.alpha = 0
        view.addSubview(bottomSeparatorView)
        NSLayoutConstraint.activate([
            bottomSeparatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomSeparatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomSeparatorView.bottomAnchor.constraint(equalTo: headerBlurView.bottomAnchor),
            bottomSeparatorView.heightAnchor.constraint(equalToConstant: 0.333),
        ])

        if IOS_26_MODE_ENABLED {
            headerBlurView.isHidden = true
            bottomSeparatorView.isHidden = true
        }

        view.backgroundColor = isInModal ? .air.sheetBackground : .air.groupedBackground
        navigationTitleView.textColor = UIColor.label

        updateSensitiveData()
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        updateSafeAreaInsets()
        updateSkeletonViewMask()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateSafeAreaInsets()
    }

    private func updateSafeAreaInsets() {
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom + 16
        guard headerBlurView != nil else { return }
        scrollViewDidScroll(collectionView)
    }

    public func updateSensitiveData() {
        expandableContentView.updateSensitiveData()
    }

    public override func updateSkeletonViewMask() {
        var skeletonViews = [UIView]()
        for cell in collectionView.visibleCells {
            if let transactionCell = cell as? ActivityCell {
                skeletonViews.append(transactionCell.contentView)
            }
        }
        for view in collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader) {
            if let headerCell = view as? ActivityDateCell, let skeletonView = headerCell.skeletonView {
                skeletonViews.append(skeletonView)
            }
        }
        skeletonView.applyMask(with: skeletonViews)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if collectionView.contentSize.height > collectionView.frame.height {
            let requiredInset = collectionView.frame.height + TokenExpandableContentView.requiredScrollOffset - collectionView.contentSize.height
            collectionView.contentInset.bottom = max(view.safeAreaInsets.bottom + 16, requiredInset)
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let scrollOffset = scrollOffset(for: scrollView)
        expandableContentView.update(scrollOffset: scrollOffset)
        updateNavigationBarChrome(scrollOffset: scrollOffset)
    }

    public func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                          withVelocity velocity: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let automaticTopInset = scrollView.adjustedContentInset.top - scrollView.contentInset.top
        let realTargetY = targetContentOffset.pointee.y + automaticTopInset
        let currentScrollOffset = scrollOffset(for: scrollView)
        // snap to views
        if realTargetY > 0 && collectionView.contentSize.height > collectionView.frame.height {
            if realTargetY < expandableContentView.actionsOffset + 30 {
                let isGoingDown = realTargetY > currentScrollOffset
                let isStopped = realTargetY == currentScrollOffset
                if isGoingDown || (isStopped && realTargetY >= expandableContentView.actionsOffset / 2) {
                    targetContentOffset.pointee.y = expandableContentView.actionsOffset - automaticTopInset - 4 // matching home screen
                } else {
                    targetContentOffset.pointee.y = -automaticTopInset
                }
            } else if realTargetY < expandableContentView.actionsOffset + actionsRowHeight {
                targetContentOffset.pointee.y = expandableContentView.actionsOffset + actionsRowHeight - automaticTopInset
            }
        }
    }

    private func scrollOffset(for scrollView: UIScrollView) -> CGFloat {
        scrollView.contentOffset.y + scrollView.adjustedContentInset.top - scrollView.contentInset.top
    }

    private func updateNavigationBarChrome(scrollOffset: CGFloat) {
        let progress = min(1, max(0, (scrollOffset - 260) / 16))
        headerBlurView.alpha = progress
        bottomSeparatorView.alpha = progress
        navigationTitleView.alpha = min(1, max(0, (30 - scrollOffset) / 14 + 1))
    }

    private func makeMenu() -> UIMenu {

        let openUrl: (URL) -> () = { url in
            AppActions.openInBrowser(url)
        }
        let token = self.token

        let openInExplorer = UIAction(title: lang("Open in Explorer"), image: UIImage(named: "SendGlobe", in: AirBundle, with: nil)) { _ in
            openUrl(ExplorerHelper.tokenUrl(token: token))
        }
        let explorerSection = UIMenu(options: .displayInline, children: [openInExplorer])

        let websiteActions = ExplorerHelper.websitesForToken(token).map { website in
            UIAction(title: website.title) { _ in
                openUrl(website.address)
            }
        }
        let websiteSection = UIMenu(options: .displayInline, children: websiteActions)

        return UIMenu(children: [explorerSection, websiteSection])
    }
}

extension TokenVC: TokenVMDelegate {
    func dataUpdated(isUpdateEvent: Bool) {
        super.transactionsUpdated(accountChanged: false, isUpdateEvent: isUpdateEvent)
    }
    func priceDataUpdated() {
        expandableContentView.configure(token: token)
        reconfigureCustomSection(id: chartCustomSectionID)
    }
    func stateChanged() {
        expandableContentView.configure(token: token)
        reconfigureCustomSection(id: chartCustomSectionID)
    }
    func accountChanged() {
        guard accountContext.source == .current else { return }
        let newAccountId = accountContext.accountId
        Task {
            self.activityViewModel = await ActivityListViewModel(accountId: newAccountId, token: token, customSectionIDs: customSectionIDs, delegate: self)
            self.tokenVM = TokenVM(accountId: newAccountId, selectedToken: token, tokenVMDelegate: self)
            self.tokenVM.refreshTransactions()
        }
    }
}

extension TokenVC: TabItemTappedProtocol {
    public func tabItemTapped() -> Bool {
        return false
    }
}


extension TokenVC: ActivityListViewModelDelegate {
    public func activityViewModelChanged() {
        super.transactionsUpdated(accountChanged: false, isUpdateEvent: false)
    }
}
