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
    private let buyingToken: String?
    
    private var segmentedController: WSegmentedController!
    private var hostingController: UIHostingController<ReceiveHeaderView>!
    private var previousNavigationBarStyle: UIUserInterfaceStyle = .unspecified
    private var displayedAccount: MAccount?
    private var isSwitchingAccount = false
    private lazy var accountSwitcher = AccountSwitcher(configuration: .init(accountSupport: .receive)) { [weak self] accountId in
        self?.selectAccount(accountId: accountId)
    }
    private lazy var accountSwitcherBarButtonItem: UIBarButtonItem = {
        if #available(iOS 27, *) {
            return accountSwitcher.barButtonItem
        } else if #available(iOS 26, *) {
            accountSwitcher.button.chevronTintColor = .white
            return makeClearGlassBarButtonItem(content: accountSwitcher.button, horizontalInset: 4)
        } else {
            return accountSwitcher.barButtonItem
        }
    }()
    
    @AccountContext private var account: MAccount

    public init(accountContext: AccountContext, chain: ApiChain? = nil, buyingToken: String? = nil) {
        self._account = AccountContext(accountId: accountContext.account.id)
        self.selectedChain = chain
        self.buyingToken = buyingToken
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
        let initialChainId = chainItems.first(where: { $0.id == selectedChain?.rawValue })?.id

        segmentedController = WSegmentedController(
            items: chainItems,
            defaultItemId: initialChainId,
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
        
        if #available(iOS 27, *) {
            addCloseNavigationItemIfNeeded()
        } else if #available(iOS 26, *) {
            if isPresentationModal {
                let button = UIButton(type: .system)
                let image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
                button.setImage(image, for: .normal)
                button.tintColor = .white
                button.accessibilityLabel = lang("Close")
                button.widthAnchor.constraint(equalToConstant: 44).isActive = true
                button.addAction(UIAction { [weak self] _ in
                    self?.dismiss(animated: true)
                }, for: .touchUpInside)
                navigationItem.rightBarButtonItem = makeClearGlassBarButtonItem(content: button)
            }
        } else {
            let image = UIImage(systemName: "xmark")
            let item = UIBarButtonItem(image: image, primaryAction: UIAction { _ in
                topViewController()?.dismiss(animated: true)
            })
            item.tintColor = .white.withAlphaComponent(0.75)
            navigationItem.rightBarButtonItem = item
        }
        updateNavigationItems()
        displayedAccount = account
        observe { [weak self] in
            guard let self else { return }
            updateAccountSwitcher()
            guard displayedAccount != account else { return }
            displayedAccount = account
            segmentedController.replace(items: makeChainItems())
            updateChainSelector()
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
        navigationController?.navigationBar.overrideUserInterfaceStyle = previousNavigationBarStyle
    }
    
    /// Overrides user interface style to dark to turn off whitish tint for navigation controls (segmented tabs + close button)
    private func setNavigationControlsAppearance() {
        segmentedController.segmentedControl.overrideUserInterfaceStyle = .dark
    }

    private func updateNavigationItems() {
        updateAccountSwitcher()
        updateChainSelector()
    }

    private func updateAccountSwitcher() {
        accountSwitcher.update(selectedAccountId: account.id, isEnabled: !isSwitchingAccount)
        let items = accountSwitcher.hasAlternativeAccounts(selectedAccountId: account.id)
            ? [accountSwitcherBarButtonItem]
            : nil
        navigationItem.setLeftBarButtonItems(items, animated: true)
    }

    @available(iOS 26, *)
    private func makeClearGlassBarButtonItem(content: UIView, horizontalInset: CGFloat = 0) -> UIBarButtonItem {
        // Match the chain selector's clear glass on iOS 26 instead of UIKit's pale shared background.
        let container = UIView()
        let background = HostingView {
            Color.clear.glassEffect(.clear, in: .capsule)
        }
        background.isUserInteractionEnabled = false
        container.addSubview(background)
        container.addSubview(content)
        background.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 44),
            background.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            background.topAnchor.constraint(equalTo: container.topAnchor),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalInset),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        let item = UIBarButtonItem(customView: container)
        item.hidesSharedBackground = true
        return item
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
        guard accountId != account.id, !isSwitchingAccount else { return }
        isSwitchingAccount = true
        updateAccountSwitcher()
        Task {
            defer {
                isSwitchingAccount = false
                updateAccountSwitcher()
            }
            do {
                try await AccountStore.activateAccount(accountId: accountId)
                $account.accountId = accountId
            } catch {
                AppActions.showError(error: error)
            }
        }
    }

    private func makeChainItems() -> [SegmentedControlItem] {
        getSupportedChains().compactMap { chain in
            guard account.supports(chain: chain) else { return nil }
            return SegmentedControlItem(
                id: chain.rawValue,
                title: chain.title,
                viewController: ReceiveTableVC(account: _account, chain: chain, preferredBuyingToken: buyingToken),
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
