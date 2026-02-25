//
//  WalletAssetsView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/15/24.
//

import UIKit
import SwiftUI
import UIComponents
import WalletContext

final class WalletAssetsView: WTouchPassView, WThemedView {
    var bottomConstraint: NSLayoutConstraint!

    let walletTokensVC: WalletTokensVC
    let walletCollectiblesView: NftsVC

    lazy var contentVcs: [any WSegmentedControllerContent] = [
        walletTokensVC,
        walletCollectiblesView
    ]
    lazy var contentItems: [SegmentedControlItem] = [
        SegmentedControlItem(
            id: "tokens_placeholder",
            title: lang("Assets"),
            viewController: walletTokensVC
        ),
        SegmentedControlItem(
            id: "nfts_placeholder",
            title: lang("Collectibles"),
            viewController: walletCollectiblesView
        ),
    ]

    var onScrollingOffsetChanged: ((CGFloat) -> Void)?
    var scrollProgress: CGFloat = 0

    init(walletTokensVC: WalletTokensVC, walletCollectiblesView: NftsVC, onScrollingOffsetChanged: ((CGFloat) -> Void)?) {
        self.walletTokensVC = walletTokensVC
        self.walletCollectiblesView = walletCollectiblesView
        self.onScrollingOffsetChanged = onScrollingOffsetChanged
        super.init(frame: .zero)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    lazy var segmentedController = WSegmentedController(
        items: contentItems,
        goUnderNavBar: false,
        animationSpeed: .medium,
        delegate: self
    )
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        segmentedController.translatesAutoresizingMaskIntoConstraints = false
        segmentedController.blurView.isHidden = true
        segmentedController.separator.isHidden = true
        addSubview(segmentedController)
        bottomConstraint = segmentedController.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            segmentedController.leftAnchor.constraint(equalTo: leftAnchor),
            segmentedController.rightAnchor.constraint(equalTo: rightAnchor),
            segmentedController.topAnchor.constraint(equalTo: topAnchor),
            bottomConstraint,
        ])
        segmentedController.delegate?.segmentedController(scrollOffsetChangedTo: 0)
        
        updateTheme()
    }
    
    func updateTheme() {
        backgroundColor = WTheme.accentButton.background
    }
    
    var selectedIndex: Int {
        get { segmentedController.selectedIndex ?? 0 }
        set {
            segmentedController.scrollView.contentOffset = CGPoint(x: CGFloat(newValue) * segmentedController.scrollView.frame.width, y: 0)
            segmentedController.scrollView.delegate?.scrollViewDidScroll?(segmentedController.scrollView)
        }
    }
}

extension WalletAssetsView: WSegmentedController.Delegate {
    func segmentedController(scrollOffsetChangedTo progress: CGFloat) {
        self.scrollProgress = progress
        onScrollingOffsetChanged?(progress)
    }
}
