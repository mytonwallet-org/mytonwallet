//
//  AssetsTabVC.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/24/24.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

public class AssetsTabVC: WViewController, WalletCoreData.EventsObserver {
    public enum Tab: String {
        case tokens
        case nfts
    }
    
    private let accountIdProvider: AccountIdProvider

    private var segmentedController: WSegmentedController!
    private let defaultTabIndex: Int
    private var nftsVCManager: NftsVCManager?

    public init(accountSource: AccountSource, defaultTabIndex: Int) {
        self.accountIdProvider = AccountIdProvider(source: accountSource)
        self.defaultTabIndex = defaultTabIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        default:
            break
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        WalletCoreData.add(eventObserver: self)
    }
    
    func setupViews() {
        if let sheet = self.sheetPresentationController {
            sheet.configureFullScreen(true)
            sheet.configureAllowsInteractiveDismiss(true)
            if IOS_26_MODE_ENABLED {
                sheet.prefersGrabberVisible = true
            }
        }
        
        let tokensVC = WalletTokensVC(accountSource: accountIdProvider.source, mode: .expanded)
        addChild(tokensVC)
        tokensVC.didMove(toParent: self)

        nftsVCManager = NftsVCManager(tabsViewModel: WalletAssetsViewModel(accountSource:  accountIdProvider.source))
        let nftsVC = NftsVC(accountSource: accountIdProvider.source, manager: nftsVCManager, layoutMode: .regular, filter: .none)
        addChild(nftsVC)
        nftsVC.didMove(toParent: self)

        segmentedController = WSegmentedController(
            items: [
                SegmentedControlItem(
                    id: Tab.tokens.rawValue,
                    title: lang("Assets"),
                    viewController: tokensVC
                ),
                SegmentedControlItem(
                    id: Tab.nfts.rawValue,
                    title: lang("Collectibles"),
                    viewController: nftsVC
                ),
           ],
            defaultItemId: defaultTabIndex == 1 ? Tab.nfts.rawValue : Tab.tokens.rawValue,
            barHeight: 0,
            goUnderNavBar: true,
            animationSpeed: .slow
        )
        segmentedController.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentedController)
        NSLayoutConstraint.activate([
            segmentedController.topAnchor.constraint(equalTo: view.topAnchor),
            segmentedController.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor),
            segmentedController.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor),
            segmentedController.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        segmentedController.separator.isHidden = true
        segmentedController.blurView.isHidden = true
        
        updateState()
        configureNavigationItemWithTransparentBackground()
        addCustomNavigationBarBackground()
        
        let segmentedControl = segmentedController.segmentedControl!
        segmentedControl.removeFromSuperview()
        navigationItem.titleView = segmentedControl
        segmentedControl.widthAnchor.constraint(equalToConstant: 200).isActive = true
        
        view.backgroundColor = .air.pickerBackground
        
        nftsVCManager?.editingNavigator.onStateChange = { [weak self] _, _ in
            self?.updateState()
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let sheet = self.sheetPresentationController {
            sheet.configureAllowsInteractiveDismiss(true)
        }
    }
    
    private func updateState() {
        updateNavigationAppearance()
        
        guard let navigator = nftsVCManager?.editingNavigator else { return }
        let state = navigator.state
        if state.editingState == .selection {
            navigator.installToolbar(into: view)
        }
        
        navigationController?.allowBackSwipeToDismiss(state.editingState == nil)
        navigationController?.isModalInPresentation = state.editingState != nil
    }
            
    private func updateNavigationAppearance() {
        if let navigator = nftsVCManager?.editingNavigator, let editingState = navigator.state.editingState {
            segmentedController.segmentedControl?.isHidden = true
            segmentedController.scrollView.isScrollEnabled = false
            
            navigationItem.rightBarButtonItem = navigator.commitEditingBarButtonItem
            switch editingState {
            case .reordering:
                navigationItem.leftBarButtonItem = navigator.cancelEditingBarButtonItem
            case .selection:
                navigationItem.leftBarButtonItem = navigator.selectAllBarButtonItem
            }
        } else {
            segmentedController.scrollView.isScrollEnabled = true
            segmentedController.segmentedControl?.isHidden = false
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItem = nil
            addCloseNavigationItemIfNeeded()
        }
    }
    
    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }
}
