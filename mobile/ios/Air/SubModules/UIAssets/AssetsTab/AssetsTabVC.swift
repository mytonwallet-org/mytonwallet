//
//  AssetsTabVC.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/24/24.
//

import UIKit
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

public class AssetsTabVC: WViewController, WalletCoreData.EventsObserver, NftsViewControllerDelegate, WSegmentedControllerDelegate {
    public enum Tab: String {
        case tokens
        case nfts
    }
    
    private let accountIdProvider: AccountIdProvider
    
    var accountId: String { accountIdProvider.accountId }
    
    private var segmentedController: WSegmentedController!
    private let defaultTabIndex: Int
    private var nftsVC: NftsVC!

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
        nftsVC = NftsVC(accountSource: accountIdProvider.source, mode: .embedded, filter: .none)
        addChild(tokensVC)
        addChild(nftsVC)
        tokensVC.didMove(toParent: self)
        nftsVC.didMove(toParent: self)
        nftsVC.delegate = self

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
            segmentedController.leftAnchor.constraint(equalTo: view.leftAnchor),
            segmentedController.rightAnchor.constraint(equalTo: view.rightAnchor),
            segmentedController.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        segmentedController.separator.isHidden = true
        segmentedController.blurView.isHidden = true
        segmentedController.delegate = self
        
        updateNavigationAppearance()
        configureNavigationItemWithTransparentBackground()
        addCustomNavigationBarBackground()
        
        let segmentedControl = segmentedController.segmentedControl!
        segmentedControl.removeFromSuperview()
        navigationItem.titleView = segmentedControl
        segmentedControl.widthAnchor.constraint(equalToConstant: 200).isActive = true
        
        updateTheme()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let sheet = self.sheetPresentationController {
            sheet.configureAllowsInteractiveDismiss(true)
        }
    }
    
    private func stopReordering(isCanceled: Bool) {
        nftsVC.stopReordering(isCanceled: isCanceled)
        updateNavigationAppearance()
        updateReorderingBehavior()
    }
    
    private func updateReorderingBehavior(){
        navigationController?.allowBackSwipeToDismiss(!nftsVC.isReordering)
        navigationController?.isModalInPresentation = nftsVC.isReordering
    }
    
    private func updateNavigationAppearance() {
        if nftsVC.isReordering {
            segmentedController.segmentedControl?.isHidden = true
            segmentedController.scrollView.isScrollEnabled = false
            let doneItem = UIBarButtonItem.doneButtonItem { [weak self] in self?.stopReordering(isCanceled: false) }
            navigationItem.trailingItemGroups = [doneItem.asSingleItemGroup()]
            navigationItem.leftBarButtonItem = .cancelTextButtonItem { [weak self] in self?.stopReordering(isCanceled: true)}
        } else {
            segmentedController.scrollView.isScrollEnabled = true
            segmentedController.segmentedControl?.isHidden = false
            addCloseNavigationItemIfNeeded()
            navigationItem.leftBarButtonItem = nil
        }
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.pickerBackground
        segmentedController?.updateTheme()
    }

    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }

    // MARK: - NftsViewControllerDelegate
        
    public func nftsViewControllerDidChangeReorderingState(_ vc: NftsVC) {
        updateNavigationAppearance()
        updateReorderingBehavior()
    }
    
    // MARK: - WSegmentedControllerDelegate
    
    public func segmentedControllerDidEndScrolling() {
        // workaround for:
        // on iPad open AssetsTabVC to tokens, swipe to nfts. sidebar obscures nfts
        if segmentedController.segmentedControl.model.selectedItem?.id == Tab.nfts.rawValue {
            UIView.animate(withDuration: 0.3) {
                self.nftsVC.view.setNeedsLayout()
            }
        }
    }
}
