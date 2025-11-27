//
//  HomeVC+SetupViews.swift
//  UIHome
//
//  Created by Sina on 7/12/24.
//

import UIKit
import UIComponents
import WalletContext
import WalletCore
import SwiftUI
import Perception

extension HomeVC {
    // MARK: - Setup home views
    func setupViews() {
        view.backgroundColor = WTheme.groupedItem

        headerTouchTarget.translatesAutoresizingMaskIntoConstraints = false
        headerTouchTarget.text = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        headerTouchTarget.textColor = .clear
        headerTouchTarget.isUserInteractionEnabled = true
        headerTouchTarget.accessibilityElementsHidden = true
        navigationItem.titleView = headerTouchTarget
        
        navigationItem.leadingItemGroups = [
            UIBarButtonItemGroup(
                barButtonItems: [
                    UIBarButtonItem(title: lang("Scan"), image: .airBundle("HomeScan24"), target: self, action: #selector(scanPressed))
                ],
                representativeItem: nil
            )
        ]
        navigationItem.trailingItemGroups = [
            UIBarButtonItemGroup(barButtonItems: [lockItem, hideItem], representativeItem: nil)
        ]
        navigationController?.setNavigationBarHidden(false, animated: false)
        if !IOS_26_MODE_ENABLED {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.backgroundEffect = nil
            navigationItem.standardAppearance = appearance
            navigationItem.scrollEdgeAppearance = appearance
        }
        
        view.addLayoutGuide(windowSafeAreaGuide)
        windowSafeAreaGuideContraint = windowSafeAreaGuide.topAnchor.constraint(equalTo: view.topAnchor, constant: 0)
        windowSafeAreaGuideContraint.isActive = true
        
        super.setupTableViews(tableViewBottomConstraint: homeBottomInset)

        // header container view (used to make animating views on start, possible)
        headerContainerView = WTouchPassView()
        headerContainerView.accessibilityIdentifier = "headerContainerView"
        headerContainerView.shouldAcceptTouchesOutside = true
        headerContainerView.translatesAutoresizingMaskIntoConstraints = false
        headerContainerView.layer.masksToBounds = true
        view.addSubview(headerContainerView)
        NSLayoutConstraint.activate([
            headerContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerContainerView.leftAnchor.constraint(equalTo: view.leftAnchor),
            headerContainerView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])

        // balance header view
        balanceHeaderVC = BalanceHeaderVC(delegate: self)
        addChild(balanceHeaderVC)
        balanceHeaderView.alpha = 0
        headerContainerView.addSubview(balanceHeaderView)
        balanceHeaderVC.didMove(toParent: self)
        NSLayoutConstraint.activate([
            balanceHeaderView.topAnchor.constraint(equalTo: windowSafeAreaGuide.topAnchor),
            balanceHeaderView.leftAnchor.constraint(equalTo: view.leftAnchor),
            balanceHeaderView.rightAnchor.constraint(equalTo: view.rightAnchor),
            balanceHeaderView.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor).withPriority(.defaultHigh)
        ])
        
        headerBlurView = WBlurView()
        headerContainerView.insertSubview(headerBlurView, at: 0)
        NSLayoutConstraint.activate([
            headerBlurView.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor),
            headerBlurView.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor),
            headerBlurView.topAnchor.constraint(equalTo: headerContainerView.topAnchor),
            headerBlurView.bottomAnchor.constraint(equalTo: windowSafeAreaGuide.topAnchor, constant: BalanceHeaderView.minHeight)
        ])

        headerBlurView.alpha = 0

        bottomSeparatorView = UIView()
        bottomSeparatorView.translatesAutoresizingMaskIntoConstraints = false
        bottomSeparatorView.isUserInteractionEnabled = false
        bottomSeparatorView.backgroundColor = UIColor { WTheme.separator.withAlphaComponent($0.userInterfaceStyle == .dark ? 0.8 : 0.2) }
        bottomSeparatorView.alpha = 0
        view.addSubview(bottomSeparatorView)
        NSLayoutConstraint.activate([
            bottomSeparatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            bottomSeparatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),
            bottomSeparatorView.heightAnchor.constraint(equalToConstant: 0.333),
            bottomSeparatorView.bottomAnchor.constraint(equalTo: headerBlurView.bottomAnchor),
        ])
        
        if IOS_26_MODE_ENABLED {
            headerBlurView.isHidden = true
            bottomSeparatorView.isHidden = true
        }
        
        if #available(iOS 26, *) {
            skeletonTableView.topEdgeEffect.isHidden = true
        }
        
        navigationBarProgressiveBlurDelta = 16
        
        // activate swipe back for presenting views on navigation controller (with hidden navigation bar)
        setInteractiveRecognizer()

        addChild(actionsVC)
        let actionsContainerView = actionsVC.actionsContainerView
        let actionsView = actionsVC.actionsView
        tableView.addSubview(actionsContainerView)
        actionsTopConstraint = actionsContainerView.topAnchor.constraint(equalTo: tableView.contentLayoutGuide.topAnchor, constant: headerHeightWithoutAssets).withPriority(.init(950))
        NSLayoutConstraint.activate([
            actionsContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            actionsContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            actionsTopConstraint,
            
            actionsContainerView.heightAnchor.constraint(equalToConstant: actionsRowHeight),
            actionsView.topAnchor.constraint(greaterThanOrEqualTo: windowSafeAreaGuide.topAnchor,
                                             constant: 50).withPriority(.init(900)) // will be broken when assets push it from below and out of frame; button height constrain has priority = 800
        ])
        actionsVC.didMove(toParent: self)
        
        addChild(walletAssetsVC)
        let assetsView = walletAssetsVC.view!
        tableView.addSubview(assetsView)
        assetsHeightConstraint = assetsView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            assetsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            assetsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            assetsView.topAnchor.constraint(equalTo: actionsView.bottomAnchor, constant: 16),
            assetsView.topAnchor.constraint(equalTo: balanceHeaderView.bottomAnchor, constant: 16).withPriority(.init(949)),

            assetsHeightConstraint,
        ])
        walletAssetsVC.didMove(toParent: self)
        
        let spacing: CGFloat = IOS_26_MODE_ENABLED ? -124 : -100
        NSLayoutConstraint.activate([
            balanceHeaderView.updateStatusView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor,
                                                constant: spacing)
        ])
        balanceHeaderView.updateStatusView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // show `loading` or `wallet created` view if needed, based on situation
        emptyWalletView.set(state: .hidden, animated: false)

        addBottomBarBlur()
        
        // fix gesture recognizer over BHV
        tableView.superview?.addGestureRecognizer(tableView.panGestureRecognizer)

        NSLayoutConstraint.activate([
            emptyWalletView.topAnchor.constraint(equalTo: walletAssetsVC.view.bottomAnchor, constant: 8)
        ])
        
        isInitializingCache = false
        applySnapshot(makeSnapshot(), animated: false)
        applySkeletonSnapshot(makeSkeletonSnapshot(), animated: false)
        updateSkeletonState()        

        updateTheme()
        
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerContainer)
        NSLayoutConstraint.activate([
            headerContainer.heightAnchor.constraint(equalToConstant: 500),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerContainer.bottomAnchor.constraint(equalTo: balanceHeaderView.bottomAnchor).withPriority(.defaultHigh),
            headerContainer.bottomAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor),
        ])
        
        let hostingController = UIHostingController(rootView: HomeHeader(homeHeaderViewModel: headerViewModel), ignoreSafeArea: true)
        self.headerHostingController = hostingController
        addChild(hostingController)
        headerContainer.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            hostingController.view.bottomAnchor.constraint(greaterThanOrEqualTo: headerContainer.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
        hostingController.view.backgroundColor = .clear
        
        headerViewModel.onSelect = { [weak self] in
            guard let self else { return }
            interactivelySwitchAccountTo(accountId: $0)
        }
        
        walletAssetsVC.delegate = self
    }
    
    func appearedForFirstTime() {
        Task {
            if let accountId = AccountStore.accountId {
                await changeAccountTo(accountId: accountId, isNew: false)
            }
        }

        emptyWalletView.alpha = 0
        balanceHeaderView.alpha = 0
        tableView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.emptyWalletView.alpha = 1
            self.balanceHeaderView.alpha = 1
            self.tableView.alpha = 1
        }
    }

    private func setInteractiveRecognizer() {
        guard let controller = navigationController else { return }
        popRecognizer = InteractivePopRecognizer(controller: controller)
        controller.interactivePopGestureRecognizer?.delegate = popRecognizer
    }
}
