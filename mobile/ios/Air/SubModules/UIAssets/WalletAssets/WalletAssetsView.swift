//
//  WalletAssetsView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/15/24.
//

import UIKit
import UIComponents
import WalletContext

final class WalletAssetsView: WTouchPassView {
    let walletTokensVC: WalletTokensVC
    private let walletCollectiblesView: WSegmentedControllerContent

    var onScrollingOffsetChanged: ((_ progress: CGFloat, _ animated: Bool) -> Void)?
    var scrollProgress: CGFloat = 0

    init(walletTokensVC: WalletTokensVC, walletCollectiblesView: WSegmentedControllerContent) {
        self.walletTokensVC = walletTokensVC
        self.walletCollectiblesView = walletCollectiblesView
        super.init(frame: .zero)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    lazy var tabsContainer = WSegmentedPagerView(
        items: [
            WSegmentedPagerItem(
                id: "tokens_placeholder",
                title: lang("Assets"),
                viewController: walletTokensVC
            ),
            WSegmentedPagerItem(
                id: "nfts_placeholder",
                title: lang("Collectibles"),
                viewController: walletCollectiblesView
            ),
        ],
        scrollContentMargin: 16,
        onScrollProgressChanged: { [weak self] progress, animated in
            self?.scrollProgress = progress
            self?.onScrollingOffsetChanged?(progress, animated)
        }
    )
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        tabsContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabsContainer)
        NSLayoutConstraint.activate([
            tabsContainer.leftAnchor.constraint(equalTo: leftAnchor),
            tabsContainer.rightAnchor.constraint(equalTo: rightAnchor),
            tabsContainer.topAnchor.constraint(equalTo: topAnchor),
            tabsContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        tabsContainer.onScrollProgressChanged?(0, false)
        
        updateTheme()
    }
    
    private func updateTheme() {
        backgroundColor = .air.groupedItem
    }
    
    var selectedIndex: Int {
        get { tabsContainer.selectedIndex ?? 0 }
        set {
            tabsContainer.handleSegmentChange(to: newValue, animated: false)
        }
    }
}
