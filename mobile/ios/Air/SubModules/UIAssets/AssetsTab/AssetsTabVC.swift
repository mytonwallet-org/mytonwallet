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

public class AssetsTabVC: WViewController, WSegmentedController.Delegate, WalletCoreData.EventsObserver {

    public enum Tab: String {
        case tokens
        case nfts
    }
    
    private let accountIdProvider: AccountIdProvider
    
    var accountId: String { accountIdProvider.accountId }
    
    private var segmentedController: WSegmentedController!
    private let defaultTabIndex: Int

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
            sheet.setValue(true, forKey: "wantsFullScreen")
            sheet.setValue(true, forKey: "allowsInteractiveDismissWhenFullScreen")
            sheet.prefersGrabberVisible = true
        }
                
        let tokensVC = WalletTokensVC(accountSource: accountIdProvider.source, compactMode: false)
        let nftsVC = NftsVC(accountSource: accountIdProvider.source, compactMode: false, filter: .none, topInset: 0)
        addChild(tokensVC)
        addChild(nftsVC)
        tokensVC.didMove(toParent: self)
        nftsVC.didMove(toParent: self)

        segmentedController = WSegmentedController(
            items: [
                SegmentedControlItem(
                    id: Tab.tokens.rawValue,
                    title: lang("Assets"),
                    viewController: tokensVC.tokensView
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
            animationSpeed: .slow,
            delegate: self
        )
        segmentedController(scrollOffsetChangedTo: 0)
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
        
        addCloseNavigationItemIfNeeded()
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
            sheet.setValue(true, forKey: "allowsInteractiveDismissWhenFullScreen")
        }
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.pickerBackground
        segmentedController?.updateTheme()
    }

    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }

    // MARK: - Segmented controller delegate

    public func segmentedController(scrollOffsetChangedTo progress: CGFloat) {
        (children.last as? NftsVC)?.updateIsVisible(progress > 0.3)
    }

    public func segmentedControllerDidStartDragging() {
    }

    public func segmentedControllerDidEndScrolling() {
    }
}
