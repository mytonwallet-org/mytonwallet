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

extension HomeVC {
    // MARK: - Setup home views
    func setupViews() {
        view.backgroundColor = WTheme.groupedItem

        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            // set title to get blurred background
            navigationItem.attributedTitle = AttributedString(lang("Home"), attributes: AttributeContainer([.foregroundColor: UIColor.clear]))
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
        } else {
            navigationController?.setNavigationBarHidden(true, animated: false)
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

        // reversed bottom corner radius for balance header view!
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
        
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            headerBlurView.isHidden = true
            bottomSeparatorView.isHidden = true
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
            
            actionsContainerView.heightAnchor.constraint(equalToConstant: 60),
            actionsView.topAnchor.constraint(greaterThanOrEqualTo: windowSafeAreaGuide.topAnchor, constant: 50).withPriority(.init(900)) // will be broken when assets push it from below and out of frame; button height constrain has priority = 800
        ])
        actionsVC.didMove(toParent: self)
        
        addChild(walletAssetsVC)
        let assetsView = walletAssetsVC.view!
        tableView.addSubview(assetsView)
        assetsHeightConstraint = assetsView.heightAnchor.constraint(equalToConstant: 0)
        assetsHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            assetsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            assetsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            assetsView.topAnchor.constraint(equalTo: actionsView.bottomAnchor, constant: 16),
            assetsView.topAnchor.constraint(equalTo: balanceHeaderView.bottomAnchor, constant: 16).withPriority(.init(949)),

            assetsHeightConstraint,
        ])
        walletAssetsVC.didMove(toParent: self)
        
        setupNavButtons()
        let spacing: CGFloat
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            spacing = 30
        } else {
            spacing = 4
        }
        NSLayoutConstraint.activate([
            lockButton.leadingAnchor.constraint(greaterThanOrEqualTo: balanceHeaderView.updateStatusView.trailingAnchor,
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
        
        walletAssetsVC.delegate = self
    }
    
    func setupNavButtons() {
        scanButton = WBaseButton(type: .system)
        scanButton.translatesAutoresizingMaskIntoConstraints = false
        scanButton.setImage(.airBundle("HomeScan24"), for: .normal)
        scanButton.addTarget(self, action: #selector(scanPressed), for: .touchUpInside)
        view.addSubview(scanButton)
        
        lockButton = WBaseButton(type: .system)
        lockButton.translatesAutoresizingMaskIntoConstraints = false
        lockButton.setImage(.airBundle("HomeLock24"), for: .normal)
        lockButton.addTarget(self, action: #selector(lockPressed), for: .touchUpInside)
        view.addSubview(lockButton)
        
        hideButton = WBaseButton(type: .system)
        hideButton.translatesAutoresizingMaskIntoConstraints = false
        hideButton.setImage(.airBundle("HomeHide24"), for: .normal)
        hideButton.addTarget(self, action: #selector(hidePressed), for: .touchUpInside)
        view.addSubview(hideButton)

        NSLayoutConstraint.activate([
            scanButton.topAnchor.constraint(equalTo: windowSafeAreaGuide.topAnchor, constant: -5),
            scanButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6), // 16 - 10
            scanButton.widthAnchor.constraint(equalToConstant: 44),
            scanButton.heightAnchor.constraint(equalToConstant: 44),
            
            lockButton.topAnchor.constraint(equalTo: windowSafeAreaGuide.topAnchor, constant: -5),
            lockButton.trailingAnchor.constraint(equalTo: hideButton.leadingAnchor, constant: 6), // -(14 - 2*10)
            lockButton.widthAnchor.constraint(equalToConstant: 44),
            lockButton.heightAnchor.constraint(equalToConstant: 44),
            
            hideButton.topAnchor.constraint(equalTo: windowSafeAreaGuide.topAnchor, constant: -5),
            hideButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            hideButton.widthAnchor.constraint(equalToConstant: 44),
            hideButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            scanButton.isHidden = true
            lockButton.isHidden = true
            hideButton.isHidden = true
        }
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
