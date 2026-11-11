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
import ContextMenuKit

let headerHeight: CGFloat = 360

public class ReceiveVC: WViewController {
    
    private let selectedChain: ApiChain?
    private let buyingToken: String?
    
    private var model: SegmentedControlModel!
    private var segmentedControl: WSegmentedControl!
    private var pager: WPagerViewController?
    private let headerTransition = ReceiveHeaderTransitionModel()
    private var hostingController: UIHostingController<ReceiveHeaderView>!
    private var headerHeightConstraint: NSLayoutConstraint!
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

        model = SegmentedControlModel(
            items: chainItems,
            primaryColor: .white,
            secondaryColor: .white,
            capsuleColor: .white.withAlphaComponent(0.16),
            style: .colorHeader
        )
        segmentedControl = WSegmentedControl(model: model, isGlassInteractive: true)
        model.onSelect = { [weak self] item in self?.selectChain(item.id) }
        configureChainMenu()
        replaceChainPages(items: chainItems, selectedId: initialChainId)

        self.hostingController = addHostingController(makeHeader()) { hv in
            self.headerHeightConstraint = hv.heightAnchor.constraint(equalToConstant: headerHeight)
            NSLayoutConstraint.activate([
                hv.topAnchor.constraint(equalTo: self.view.topAnchor),
                hv.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                hv.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                self.headerHeightConstraint
            ])
        }
        hostingController.disableSafeArea()
        hostingController.view.clipsToBounds = true
        
        if let pager { view.bringSubviewToFront(pager.view) }

        if IS_GRAM_WALLET {
            let diamondTouchView = TelegramReceiveDiamondTouchView()
            diamondTouchView.sourceView = hostingController.view
            diamondTouchView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(diamondTouchView)
            NSLayoutConstraint.activate([
                diamondTouchView.topAnchor.constraint(equalTo: view.topAnchor),
                diamondTouchView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                diamondTouchView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                diamondTouchView.heightAnchor.constraint(equalTo: hostingController.view.heightAnchor),
            ])
        }
        
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
            let selectedId = selectedChainId
            replaceChainPages(items: makeChainItems(), selectedId: selectedId)
            updateChainSelector()
        }

        updateTheme()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previousNavigationBarStyle = navigationController?.navigationBar.overrideUserInterfaceStyle ?? .unspecified
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Keep at least 40% of short sheets available for the address and actions
        let height = min(headerHeight, view.bounds.height * 0.6)
        headerHeightConstraint.constant = height
        if hostingController.rootView.availableHeight != height {
            hostingController.rootView.availableHeight = height
        }
        for item in model.items {
            (item.viewController as? ReceiveTableVC)?.setHeaderHeight(height)
        }
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        setNavigationControlsAppearance()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = previousNavigationBarStyle
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if isViewLoaded, traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            setNavigationControlsAppearance()
        }
    }

    /// Match the dark navigation buttons while keeping the menu's appearance independent.
    private func setNavigationControlsAppearance() {
        guard let segmentedControl else { return }
        segmentedControl.overrideUserInterfaceStyle = .dark
        segmentedControl.glassUserInterfaceStyle = .dark
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
        let isMultichain = model.items.count > 1
        pager?.isPagingEnabled = isMultichain
        segmentedControl.isHidden = !isMultichain
        if isMultichain {
            segmentedControl.embed(in: navigationItem)
        } else {
            segmentedControl.removeFromSuperview()
            let header = NavigationHeader2()
            let title = NavigationHeader2.makeTitleLabel(lang("Add Crypto"), fixedColor: true)
            title.textColor = .white
            header.accessibilityElementsHidden = false
            header.accessibilityLabel = title.text
            header.setContentView(title)
            navigationItem.titleView = header
        }
    }

    private func configureChainMenu() {
        segmentedControl.longPressContextMenuAccessibilityLabel = lang("All Chains")
        segmentedControl.longPressContextMenuProvider = SegmentedControlContextMenuProvider { [weak self] in
            self?.makeChainMenuConfiguration() ?? ContextMenuConfiguration(rootPage: ContextMenuPage(items: []))
        }
    }

    private func makeChainMenuConfiguration() -> ContextMenuConfiguration {
        let accountId = account.id
        let selectedId = selectedChainId
        let items = model.items.compactMap { item -> ContextMenuItem? in
            guard let chain = ApiChain(rawValue: item.id), let chainInfo = account.getChainInfo(chain: chain) else {
                return nil
            }
            let subtitle = if let domain = chainInfo.domain {
                "\(domain) \(formatStartEndAddress(chainInfo.address, prefix: 0, suffix: 6))"
            } else {
                formatStartEndAddress(chainInfo.address, prefix: 6, suffix: 6)
            }
            return .custom(.swiftUI(
                id: chain.rawValue,
                preferredWidth: 294,
                sizing: .fixed(height: 60),
                interaction: .selectable(handler: { [weak self] in
                    guard let self, self.account.id == accountId, !self.isSwitchingAccount else { return }
                    let isSelected = self.selectedChainId == chain.rawValue
                    self.selectChain(chain.rawValue)
                    if isSelected { self.segmentedControl.centerSelectedItem(animated: true) }
                })
            ) { _ in
                ReceiveChainMenuRow(chain: chain, subtitle: subtitle, isSelected: item.id == selectedId)
            })
        }
        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .none,
            userInterfaceStyle: view.traitCollection.userInterfaceStyle,
            popoverUsesSourceViewBounds: true,
            popoverDisablesInteractiveDismissal: true,
            popoverBackgroundMaterial: .systemMaterial,
            style: ContextMenuStyle(minWidth: 294, maxWidth: 294, sourceSpacing: 0)
        )
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

    private func replaceChainPages(items: [SegmentedControlItem], selectedId: String?) {
        let pageViewIndex = pager.flatMap { view.subviews.firstIndex(of: $0.view) }
        if let pager {
            pager.onProgressChanged = nil
            pager.onSelectionChanged = nil
            pager.finishPaging()
            pager.willMove(toParent: nil)
            pager.view.removeFromSuperview()
            pager.removeFromParent()
            self.pager = nil
        }
        model.setItems(items)
        segmentedControl.endSelectionScroll()
        guard !items.isEmpty else {
            headerTransition.selection = nil
            return
        }
        let index = items.firstIndex { $0.id == selectedId } ?? 0
        model.selection = .init(item1: items[index].id)
        headerTransition.settle(on: items[index].id)
        let pager = WPagerViewController(pages: items.map { item in
            .init(id: item.id, makeViewController: { item.viewController })
        }, selectedIndex: index, preloadsPages: true)
        self.pager = pager
        pager.onProgressChanged = { [weak self] progress in
            guard let self else { return }
            segmentedControl.setPagingProgress(progress.logicalOffset)
            headerTransition.selection = .init(
                source: items[progress.source].id,
                destination: items[progress.destination].id,
                fraction: progress.fraction
            )
        }
        pager.onSelectionChanged = { [weak self] index in
            guard let self else { return }
            segmentedControl.setPagingProgress(CGFloat(index))
            segmentedControl.endSelectionScroll()
            headerTransition.settle(on: items[index].id)
        }
        addChild(pager)
        view.addStretchedToBounds(subview: pager.view)
        if let pageViewIndex { view.insertSubview(pager.view, at: pageViewIndex) }
        pager.didMove(toParent: self)
    }

    private func selectChain(_ id: String) {
        guard let index = model.getItemIndexById(itemId: id), let pager else { return }
        if index != pager.selectedIndex {
            segmentedControl.beginSelectionScroll(toItemId: id)
        }
        pager.select(index: index, animated: true)
    }

    private var selectedChainId: String? {
        guard let index = pager?.selectedIndex, model.items.indices.contains(index) else { return nil }
        return model.items[index].id
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }
    
    public override func scrollToTop(animated: Bool) {
        guard let model, let index = pager?.selectedIndex, model.items.indices.contains(index) else { return }
        model.items[index].viewController.scrollToTop(animated: animated)
    }
            
    private func makeHeader() -> ReceiveHeaderView {
        ReceiveHeaderView(viewModel: model, accountContext: _account, transition: headerTransition)
    }
}

private struct ReceiveChainMenuRow: View {
    let chain: ApiChain
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(uiImage: chain.image)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(chain.title)
                    .textStyle(.body)
                    .foregroundStyle(Color.air.primaryLabel)
                    .lineLimit(1)
                Text(subtitle)
                    .textStyle(.footnote, content: .technical)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "checkmark")
                .textStyle(.body)
                .foregroundStyle(Color.air.primaryLabel)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#if DEBUG
@available(iOS 26, *)
#Preview {
    previewSheet(ReceiveVC(accountContext: AccountContext(source: .current)))
}
#endif
