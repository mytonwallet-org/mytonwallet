
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

public enum EarnInitialAction: Sendable {
    case unstake
}


@MainActor
public class EarnRootVC: WViewController, WSegmentedController.Delegate, Sendable {

    private struct PendingSelection: Equatable {
        var accountId: String
        var itemId: String
    }
    
    public let tokenSlug: String?
    private var initialAction: EarnInitialAction?
    private var isReadyForInitialAction = false
    private let isAccountSwitchingAllowed: Bool
    private var displayedAccountId: String?
    private var pendingSelection: PendingSelection?
    
    private var tonVC: EarnVC!
    private var mycoinVC: EarnVC!
    private var ethenaVC: EarnVC!
    private lazy var accountSwitcher = AccountSwitcher(configuration: .init(accountSupport: .earn)) { [weak self] accountId in
        self?.selectAccount(accountId: accountId)
    }

    @AccountContext private var account: MAccount
    
    private var segmentedController: WSegmentedController!
    
    private lazy var _allSegmentedControlItems: [String: SegmentedControlItem] = [
        TONCOIN_SLUG: SegmentedControlItem(
            id: TONCOIN_SLUG,
            title: ApiToken.TONCOIN.symbol,
            viewController: tonVC,
        ),
        MYCOIN_SLUG: SegmentedControlItem(
            id: MYCOIN_SLUG,
            title: "MY",
            viewController: mycoinVC,
        ),
        TON_USDE_SLUG: SegmentedControlItem(
            id: TON_USDE_SLUG,
            title: "USDe",
            viewController: ethenaVC,
        ),
    ]
    private var segmentedControlItems: [SegmentedControlItem] {
        var items: [SegmentedControlItem] = []
        let stakingState = $account.stakingData
        
        items += _allSegmentedControlItems[TONCOIN_SLUG]!
        if stakingState?.hasMycoinStakeOrRewards == true {
            items += _allSegmentedControlItems[MYCOIN_SLUG]!
        }
        if stakingState?.ethenaState != nil {
            items += _allSegmentedControlItems[TON_USDE_SLUG]!
        }
        return items
    }
    
    public init(accountContext: AccountContext, tokenSlug: String?, initialAction: EarnInitialAction? = nil) {
        self._account = accountContext
        self.tokenSlug = StakingConfig.config(forTokenSlug: tokenSlug)?.baseTokenSlug ?? tokenSlug ?? TONCOIN_SLUG
        self.initialAction = initialAction
        self.isAccountSwitchingAllowed = accountContext.source == .current
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        displayedAccountId = account.id
        observe { [weak self] in
            guard let self else { return }
            let accountId = account.id
            updateLeftNavigationItem()
            guard displayedAccountId != accountId else { return }
            displayedAccountId = accountId
            updateWithStakingState()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isReadyForInitialAction = true
        performInitialActionIfPossible()
    }
    
    private func setupViews() {
        tonVC = EarnVC(earnVM: EarnVM(config: .ton, accountContext: _account))
        mycoinVC = EarnVC(earnVM: EarnVM(config: .mycoin, accountContext: _account))
        ethenaVC = EarnVC(earnVM: EarnVM(config: .ethena, accountContext: _account))

        addChild(tonVC)
        addChild(mycoinVC)
        addChild(ethenaVC)
                
        segmentedController = WSegmentedController(
            items: segmentedControlItems,
            defaultItemId: tokenSlug,
            barHeight: 0,
            goUnderNavBar: true,
            animationSpeed: .slow,
            capsuleFillColor: .air.darkCapsule,
            style: .header,
            delegate: self
        )
        
        segmentedController.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedController)
        NSLayoutConstraint.activate([
            segmentedController.topAnchor.constraint(equalTo: view.topAnchor),
            segmentedController.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmentedController.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            segmentedController.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        segmentedController.backgroundColor = .clear
        segmentedController.blurView.isHidden = true
        segmentedController.separator.isHidden = true
        
        view.bringSubviewToFront(segmentedController)
        
        updateWithStakingState()
        
        DispatchQueue.main.async { [self] in
            selectRequestedToken(allowFallback: true)
        }

        segmentedController.segmentedControl?.embed(in: navigationItem)
        addCloseNavigationItemIfNeeded()
        addCustomNavigationBarBackground(color: .air.sheetBackground)

        view.backgroundColor = .air.sheetBackground

        WalletCoreData.add(eventObserver: self)
    }

    private func updateWithStakingState() {
        let items = self.segmentedControlItems
        segmentedController.scrollView.isScrollEnabled = items.count > 1
        segmentedController.segmentedControl?.isHidden = items.count < 2
        segmentedController.replace(items: items)
        restorePendingSelectionIfPossible(items: items)
        if initialAction != nil {
            DispatchQueue.main.async { [self] in
                performInitialActionIfPossible()
            }
        }
    }

    private func restorePendingSelectionIfPossible(items: [SegmentedControlItem]) {
        guard let pendingSelection, pendingSelection.accountId == account.id else { return }
        guard let index = items.firstIndex(where: { $0.id == pendingSelection.itemId }) else {
            if $account.stakingData != nil {
                self.pendingSelection = nil
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingSelection == pendingSelection, account.id == pendingSelection.accountId else { return }
            segmentedController.setSelectedIndex(to: index, animated: false)
            self.pendingSelection = nil
        }
    }

    private func updateLeftNavigationItem() {
        guard isAccountSwitchingAllowed else {
            navigationItem.setLeftBarButtonItems(nil, animated: true)
            return
        }

        accountSwitcher.update(selectedAccountId: account.id)
        let items = accountSwitcher.hasAlternativeAccounts(selectedAccountId: account.id)
            ? [accountSwitcher.barButtonItem]
            : nil
        navigationItem.setLeftBarButtonItems(items, animated: true)
    }

    private func selectAccount(accountId: String) {
        if let selectedItemId = segmentedController.model.selectedItem?.id {
            pendingSelection = PendingSelection(accountId: accountId, itemId: selectedItemId)
        }
        Task {
            do {
                try await AccountStore.activateAccount(accountId: accountId)
                $account.accountId = accountId
            } catch {
                if pendingSelection?.accountId == accountId {
                    pendingSelection = nil
                }
                AppActions.showError(error: error)
            }
        }
    }

    @discardableResult
    private func selectRequestedToken(allowFallback: Bool) -> EarnVC? {
        let currentItems = segmentedControlItems
        let requestedIndex = currentItems.firstIndex { $0.id == tokenSlug }
        let index = requestedIndex ?? (allowFallback ? 0 : nil)
        guard let index else { return nil }
        segmentedController.setSelectedIndex(to: index, animated: false)
        guard requestedIndex != nil else { return nil }
        return currentItems[index].viewController as? EarnVC
    }

    private func performInitialActionIfPossible() {
        guard isReadyForInitialAction, let initialAction else { return }
        guard let earnVC = selectRequestedToken(allowFallback: false) else { return }
        switch initialAction {
        case .unstake:
            if earnVC.openUnstakeFlow(animated: true) {
                self.initialAction = nil
            }
        }
    }
        
    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }
}

extension EarnRootVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged:
            if $account.source == .current {
                updateWithStakingState()
            }
        case .stakingAccountData(let data):
            if data.accountId == $account.accountId {
                updateWithStakingState()
            }
        default:
            break
        }
    }
}
