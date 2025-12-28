//
//  TokenVC.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/1/24.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("TokenVC")

@MainActor
public class TokenVC: ActivitiesTableViewController, Sendable, WSensitiveDataProtocol {

    private var tokenVM: TokenVM!

    private var accountId: String
    private let token: ApiToken
    private let isInModal: Bool

    var _activityViewModel: ActivityViewModel?
    public override var activityViewModel: ActivityViewModel? { self._activityViewModel }

    var windowSafeAreaGuide = UILayoutGuide()
    var windowSafeAreaGuideContraint: NSLayoutConstraint!
    var emptyWalletViewTopConstraint: NSLayoutConstraint!

    public init(accountId: String, token: ApiToken, isInModal: Bool) async {
        self.accountId = accountId
        self.token = token
        self.isInModal = isInModal
        super.init(nibName: nil, bundle: nil)
        self._activityViewModel = await ActivityViewModel(accountId: accountId, token: token, delegate: self)
        tokenVM = TokenVM(accountId: AccountStore.account?.id ?? "",
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

    private lazy var expandableContentView = TokenExpandableContentView(
        isInModal: isInModal,
        parentProcessorQueue: processorQueue,
        onHeightChange: { [weak self] in
            self?.updateHeaderHeight()
        }
    )

    private func updateHeaderHeight() {
        reconfigureHeaderPlaceholder(animated: false)
        emptyWalletViewTopConstraint.constant = firstRowPlaceholderHeight - 48
    }

    public override var headerPlaceholderHeight: CGFloat {
        return expandableContentView.expandedHeight + view.safeAreaInsets.top - 40
    }

    private var tokenChartCell: TokenChartCell? = nil
    public override var firstRowPlaceholderHeight: CGFloat {
        return 56 + (tokenChartCell?.height ??
            (AppStorageHelper.isTokenChartExpanded ? TokenExpandableChartView.expandedHeight : TokenExpandableChartView.collapsedHeight)
        )
    }
    public override var firstRow: UITableViewCell.Type? { TokenChartCell.self }
    public override func configureFirstRow(cell: UITableViewCell) {
        guard let cell = cell as? TokenChartCell else { return }
        tokenChartCell = cell
        cell.setup(parentProcessorQueue: processorQueue, onHeightChange: { [weak self] in
            self?.updateHeaderHeight()
        })
        cell.configure(token: token,
                       historyData: tokenVM.historyData) { [weak self] period in
            guard let self else { return }
            tokenVM.selectedPeriod = period
        }
    }

    private lazy var expandableNavigationView: ExpandableNavigationView = {

        let image = UIImage(named: "More22", in: AirBundle, with: nil)
        let moreButton = WNavigationBarButton(icon: image, tintColor: WTheme.tint, onPress: nil, menu: makeMenu(), showsMenuAsPrimaryAction: true)

        let navigationBar = WNavigationBar(
            navHeight: isInModal ? 46 : 40,
            topOffset: (isInModal ? 0 : -6) + S.headerTopAdjustment,
            title: token.name,
            trailingItem: moreButton,
            addBackButton: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
        let expandableNavigationView = ExpandableNavigationView(navigationBar: navigationBar,
                                                                expandableContent: expandableContentView)
        return expandableNavigationView
    }()

    public override func loadView() {
        super.loadView()
        setupViews()
    }

    private func setupViews() {

        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            // set title to get blurred background
            navigationItem.attributedTitle = AttributedString(token.name, attributes: AttributeContainer([.foregroundColor: UIColor.clear]))
            navigationItem.trailingItemGroups = [
                UIBarButtonItemGroup(
                    barButtonItems: [
                        UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: makeMenu())
                    ],
                    representativeItem: nil
                )
            ]
        } else {
            navigationController?.setNavigationBarHidden(true, animated: false)
        }

        view.addLayoutGuide(windowSafeAreaGuide)
        windowSafeAreaGuideContraint = windowSafeAreaGuide.topAnchor.constraint(equalTo: view.topAnchor, constant: 0)

        super.setupTableViews(tableViewBottomConstraint: 0)
        UIView.performWithoutAnimation {
            applySnapshot(makeSnapshot(), animated: false)
            applySkeletonSnapshot(makeSkeletonSnapshot(), animated: false)
            updateSkeletonState()
        }

        view.addSubview(expandableNavigationView)
        emptyWalletViewTopConstraint = emptyWalletView.topAnchor.constraint(equalTo: expandableNavigationView.bottomAnchor,
                                                                            constant: firstRowPlaceholderHeight - 48)
        NSLayoutConstraint.activate([
            windowSafeAreaGuideContraint,

            expandableNavigationView.topAnchor.constraint(equalTo: view.topAnchor),
            expandableNavigationView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            expandableNavigationView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            emptyWalletViewTopConstraint
        ])

        if !isInModal {
            addBottomBarBlur()
        }

        updateTheme()

        updateSensitiveData()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
    }

    public override func viewIsAppearing(_ animated: Bool) {
        if let navbarHeight = navigationController?.navigationBar.frame.height {
            if IOS_26_MODE_ENABLED {
                additionalSafeAreaInsets.top = -navbarHeight + (isInModal ? -5 : 1)
            }
        }
        tableView.contentInset.bottom = view.safeAreaInsets.bottom + 16
        updateSkeletonViewMask()
    }

    public override func updateTheme() {
        view.backgroundColor = isInModal ? WTheme.sheetBackground : WTheme.groupedBackground
    }

    public func updateSensitiveData() {
        expandableContentView.balanceContainer.updateSensitiveData()
    }

    public override func updateSkeletonViewMask() {
        var skeletonViews = [UIView]()
        for cell in skeletonTableView.visibleCells {
            if let transactionCell = cell as? ActivityCell {
                skeletonViews.append(transactionCell.contentView)
            }
        }
        for view in skeletonTableView.subviews {
            if let headerCell = view as? ActivityDateCell, let skeletonView = headerCell.skeletonView {
                skeletonViews.append(skeletonView)
            }
        }
        skeletonView.applyMask(with: skeletonViews)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if tableView.contentSize.height > tableView.frame.height {
            let requiredInset = tableView.frame.height + TokenExpandableContentView.requiredScrollOffset - tableView.contentSize.height
            tableView.contentInset.bottom = max(view.safeAreaInsets.bottom + 16, requiredInset)
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        expandableNavigationView.update(scrollOffset: scrollView.contentOffset.y)
    }

    public func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                          withVelocity velocity: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let realTargetY = targetContentOffset.pointee.y
        // snap to views
        if realTargetY > 0 && tableView.contentSize.height > tableView.frame.height {
            if realTargetY < expandableContentView.actionsOffset + 30 {
                let isGoingDown = realTargetY > scrollView.contentOffset.y
                let isStopped = realTargetY == scrollView.contentOffset.y
                if isGoingDown || (isStopped && realTargetY >= expandableContentView.actionsOffset / 2) {
                    targetContentOffset.pointee.y = expandableContentView.actionsOffset - 4 // matching home screen
                } else {
                    targetContentOffset.pointee.y = 0
                }
            } else if realTargetY < expandableContentView.actionsOffset + actionsRowHeight {
                targetContentOffset.pointee.y = expandableContentView.actionsOffset + actionsRowHeight
            }
        }
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
        reconfigureFirstRowCell()
    }
    func stateChanged() {
        expandableContentView.configure(token: token)
        reconfigureFirstRowCell()
    }
    func accountChanged() {
        guard let newAccountId = AccountStore.accountId else { return }
        Task {
            self.accountId = newAccountId
            self._activityViewModel = await ActivityViewModel(accountId: newAccountId, token: token, delegate: self)
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


extension TokenVC: ActivityViewModelDelegate {
    public func activityViewModelChanged() {
        super.transactionsUpdated(accountChanged: false, isUpdateEvent: false)
    }
}

