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
    private let walletCollectiblesView: WSegmentedControllerContent
    private var accountTransitionSnapshot: UIView?

    var onScrollingOffsetChanged: ((_ progress: CGFloat, _ animated: Bool) -> Void)?
    var scrollProgress: CGFloat = 0

    init(walletCollectiblesView: WSegmentedControllerContent) {
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
                id: "nfts_placeholder",
                title: lang("Collectibles"),
                viewController: walletCollectiblesView
            ),
        ],
        scrollContentMargin: 16,
        contentTopInsetWhenSegmentedControlHidden: 4,
        onScrollProgressChanged: { [weak self] progress, animated in
            self?.scrollProgress = progress
            self?.onScrollingOffsetChanged?(progress, animated)
        }
    )
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        tabsContainer.translatesAutoresizingMaskIntoConstraints = false
        tabsContainer.isSegmentedControlHidden = true
        addSubview(tabsContainer)
        NSLayoutConstraint.activate([
            tabsContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabsContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabsContainer.topAnchor.constraint(equalTo: topAnchor),
            tabsContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        tabsContainer.onScrollProgressChanged?(0, false)
        
        updateTheme()
    }
    
    private func updateTheme() {
        backgroundColor = .air.groupedItem
    }

    func prepareAccountTransition(animated: Bool) {
        let previousSnapshot = accountTransitionSnapshot
        accountTransitionSnapshot = nil
        defer { previousSnapshot?.removeFromSuperview() }

        guard animated, let window, !bounds.isEmpty else { return }
        var visibleRect = convert(bounds, to: window).intersection(window.bounds)
        var ancestor: UIView? = self
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0 else { return }
            if view.clipsToBounds {
                visibleRect = visibleRect.intersection(view.convert(view.bounds, to: window))
            }
            ancestor = view.superview
        }
        guard !visibleRect.isEmpty,
              let snapshot = snapshotView(afterScreenUpdates: false) else { return }
        // Capture the current composite before removing an interrupted fade.
        snapshot.frame = bounds
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        addSubview(snapshot)
        accountTransitionSnapshot = snapshot
    }

    func animateAccountTransition() {
        guard let snapshot = accountTransitionSnapshot else { return }
        UIView.animateAdaptive(duration: 0.3) {
            snapshot.alpha = 0
        } completion: { [weak self] _ in
            snapshot.removeFromSuperview()
            if self?.accountTransitionSnapshot === snapshot {
                self?.accountTransitionSnapshot = nil
            }
        }
    }
    
    var selectedIndex: Int {
        get { tabsContainer.selectedIndex ?? 0 }
        set {
            tabsContainer.handleSegmentChange(to: newValue, animated: false)
        }
    }
}
