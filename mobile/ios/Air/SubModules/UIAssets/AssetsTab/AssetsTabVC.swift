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

    // MARK: - View Model and UI Components
    private var segmentedController: WSegmentedController!
    private let defaultTabIndex: Int

    public init(defaultTabIndex: Int) {
        self.defaultTabIndex = defaultTabIndex
        super.init(nibName: nil, bundle: nil)
    }

    var moreButton: UIButton?

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .nftsChanged(let accountId):
            if accountId == AccountStore.accountId {
                moreButton?.menu = NftStore.makeNftCollectionsMenu(accountId: accountId)
            }
        default:
            break
        }
    }

    // MARK: - Load and SetupView Functions
    public override func loadView() {
        super.loadView()
        setupViews()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        // listen for keyboard
        WKeyboardObserver.observeKeyboard(delegate: self)
    }

    public override var hideNavigationBar: Bool {
        !IOS_26_MODE_ENABLED
    }

    // MARK: - Setup browser views
    private var bottomViewBottomConstraint: NSLayoutConstraint!
    func setupViews() {
        let tokensVC = WalletTokensVC(compactMode: false)
        let nftsVC = NftsVC(compactMode: false, filter: .none, topInset: IOS_26_MODE_ENABLED ? 0 : 56)
        addChild(tokensVC)
        addChild(nftsVC)

        segmentedController = WSegmentedController(
            viewControllers: [tokensVC.tokensView, nftsVC],
            items: [
               .init(index: 0, id: "tokens", content: AnyView(Text(lang("Assets")))),
               .init(index: 1, id: "nfts", content: AnyView(Text(lang("Collectibles")))),
           ],
            defaultIndex: defaultTabIndex,
            barHeight: 56,
            animationSpeed: .slow,
            constraintToTopSafeArea: !IOS_26_MODE_ENABLED,
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

        let navigationBar = WNavigationBar(constraintToTopSafeArea: !IOS_26_MODE_ENABLED, closeIcon: true)
        navigationBar.blurView.isHidden = true
        navigationBar.shouldPassTouches = true
        view.addSubview(navigationBar)
        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.topAnchor),
            navigationBar.leftAnchor.constraint(equalTo: view.leftAnchor),
            navigationBar.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])

        let moreButton = UIButton(type: .custom)
        self.moreButton = moreButton
        moreButton.setImage(UIImage(systemName: "ellipsis.circle.fill"), for: .normal)
        moreButton.showsMenuAsPrimaryAction = true
        if let accountId = AccountStore.accountId {
            moreButton.menu = NftStore.makeNftCollectionsMenu(accountId: accountId)
        }
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(moreButton)
        NSLayoutConstraint.activate([
            moreButton.leadingAnchor.constraint(equalTo: segmentedController.newSegmentedControl.trailingAnchor, constant: -8),
            moreButton.centerYAnchor.constraint(equalTo: segmentedController.newSegmentedControl.centerYAnchor),
        ])
        moreButton.alpha = 0

        updateTheme()
    }

    public override func updateTheme() {
        view.backgroundColor = WTheme.pickerBackground
        segmentedController?.updateTheme()
    }

    public override func scrollToTop(animated: Bool) {
        segmentedController?.scrollToTop(animated: animated)
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateTheme()
    }

    public func switchToTokensTab() {
        segmentedController?.switchTo(tabIndex: 0)
    }

    func openContextMenu() {
        if let accountId = AccountStore.accountId {
            moreButton?.menu = NftStore.makeNftCollectionsMenu(accountId: accountId)
            if #available(iOS 17.4, *) {
                moreButton?.performPrimaryAction()
            } else {
                moreButton?.sendActions(for: .touchUpInside)
            }
        }
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

extension AssetsTabVC: WKeyboardObserverDelegate {
    public func keyboardWillShow(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: info.animationDuration) { [self] in
            bottomViewBottomConstraint?.constant = -info.height + (tabBarController?.tabBar.frame.height ?? 0)
            view.layoutIfNeeded()
        }
    }

    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: info.animationDuration) { [self] in
            bottomViewBottomConstraint?.constant = 0
            view.layoutIfNeeded()
        }
    }
}

