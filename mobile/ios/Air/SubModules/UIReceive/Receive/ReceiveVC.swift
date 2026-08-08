//
//  ReceiveVC.swift
//  UIHome
//
//  Created by Sina on 4/22/23.
//

import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception

let headerHeight: CGFloat = 360

public class ReceiveVC: WViewController {
    
    private let selectedChain: ApiChain?
    private let isAccountSwitchingAllowed: Bool
    
    private var segmentedController: WSegmentedController!
    private var hostingController: UIHostingController<ReceiveHeaderView>!
    private var previousNavigationBarStyle: UIUserInterfaceStyle = .unspecified
    private var displayedAccountId: String?
    private lazy var accountSwitcher = AccountSwitcher(configuration: .init(accountSupport: .receive)) { [weak self] accountId in
        self?.selectAccount(accountId: accountId)
    }
    
    @AccountContext private var account: MAccount

    public init(accountContext: AccountContext, chain: ApiChain? = nil) {
        self._account = accountContext
        self.selectedChain = chain
        self.isAccountSwitchingAllowed = accountContext.source == .current
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    private func setupViews() {
        let chainItems = makeChainItems()

        segmentedController = WSegmentedController(
            items: chainItems,
            defaultItemId: selectedChain?.rawValue,
            barHeight: 0,
            goUnderNavBar: true,
            animationSpeed: .slow,
            primaryTextColor: .white,
            secondaryTextColor: .white,
            capsuleFillColor: .white.withAlphaComponent(0.16),
            style: .colorHeader
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

        self.hostingController = addHostingController(makeHeader()) { hv in
            NSLayoutConstraint.activate([
                hv.topAnchor.constraint(equalTo: self.view.topAnchor),
                hv.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                hv.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                hv.heightAnchor.constraint(equalToConstant: headerHeight)
            ])
        }
        hostingController.disableSafeArea()
        hostingController.view.clipsToBounds = true
        
        view.bringSubviewToFront(segmentedController)
        
        configureNavigationItemWithTransparentBackground()
        setNavigationControlsAppearance()
        
        if #available(iOS 26, *) {
            addCloseNavigationItemIfNeeded()
        } else {
            let image = UIImage(systemName: "xmark")
            let item = UIBarButtonItem(image: image, primaryAction: UIAction { _ in
                topViewController()?.dismiss(animated: true)
            })
            item.tintColor = .white.withAlphaComponent(0.75)
            navigationItem.rightBarButtonItem = item
        }
        updateNavigationItems()
        if let selectedChain {
            DispatchQueue.main.async { [self] in
                applyInitialChainSelection(selectedChain)
            }
        }

        displayedAccountId = account.id
        observe { [weak self] in
            guard let self else { return }
            let accountId = account.id
            updateAccountSwitcher()
            guard displayedAccountId != accountId else { return }
            displayedAccountId = accountId
            segmentedController.replace(items: makeChainItems())
            updateChainSelector()
            DispatchQueue.main.async { [weak self] in
                self?.keepUserInterfaceStyleForChildPages()
            }
        }

        updateTheme()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previousNavigationBarStyle = navigationController?.navigationBar.overrideUserInterfaceStyle ?? .unspecified
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .unspecified
        navigationController?.navigationBar.overrideUserInterfaceStyle = previousNavigationBarStyle
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        keepUserInterfaceStyleForChildPages()
    }
    
    /// Overrides user interface style to dark to turn off whitish tint for navigation controls (segmented tabs + close button)
    private func setNavigationControlsAppearance() {
        segmentedController.overrideUserInterfaceStyle = .dark
        keepUserInterfaceStyleForChildPages()
    }
    
    /// Restores system-wide user interface style overridden in `setNavigationControlsAppearance `
    private func keepUserInterfaceStyleForChildPages() {
        segmentedController.model.items.forEach {
             $0.viewController.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle
        }
    }

    private func applyInitialChainSelection(_ chain: ApiChain) {
        guard let index = segmentedController.model.getItemIndexById(itemId: chain.rawValue) else { return }
        segmentedController.setSelectedIndex(to: index, animated: false)
    }

    private func updateNavigationItems() {
        updateAccountSwitcher()
        updateChainSelector()
    }

    private func updateAccountSwitcher() {
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

    private func updateChainSelector() {
        let isMultichain = segmentedController.model.items.count > 1
        segmentedController.scrollView.isScrollEnabled = isMultichain
        segmentedController.segmentedControl.isHidden = !isMultichain
        if isMultichain {
            segmentedController.segmentedControl.embed(in: navigationItem)
        } else {
            segmentedController.segmentedControl.removeFromSuperview()
            navigationItem.titleView = HostingView {
                NavigationHeader {
                    Text(lang("Add Crypto"))
                        .textStyle(.bodyStrong)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func selectAccount(accountId: String) {
        Task {
            do {
                try await AccountStore.activateAccount(accountId: accountId)
                $account.accountId = accountId
            } catch {
                AppActions.showError(error: error)
            }
        }
    }

    private func makeChainItems() -> [SegmentedControlItem] {
        let visibleChains = _account.displayedChains
        let visibleChainSet = Set(visibleChains.map(\.0))
        let allChains = visibleChains + _account.orderedChains.filter { chain, _ in
            !visibleChainSet.contains(chain)
        }

        return allChains.map { (chain, _) in
            SegmentedControlItem(
                id: chain.rawValue,
                title: chain.title,
                viewController: ReceiveTableVC(account: _account, chain: chain),
            )
        }
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }
    
    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }
            
    private func makeHeader() -> ReceiveHeaderView {
        ReceiveHeaderView(viewModel: segmentedController.model, accountContext: _account)
    }
}

#if DEBUG
@available(iOS 26, *)
#Preview {
    previewSheet(ReceiveVC(accountContext: AccountContext(source: .current)))
}
#endif
