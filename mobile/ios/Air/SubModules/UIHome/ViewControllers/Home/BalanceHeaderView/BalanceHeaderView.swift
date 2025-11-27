//
//  BalanceHeaderView.swift
//  UIWalletHome
//
//  Created by Sina on 4/20/23.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("BalanceHeaderView")

@MainActor protocol BalanceHeaderViewDelegate: AnyObject {
    func headerIsAnimating()
    func expandHeader()
    var isTracking: Bool { get }
}


@MainActor
final class BalanceHeaderView: WTouchPassView, WThemedView {
    
    // MARK: View height
    
    // minimum height to show collapsed mode
    static let minHeight = CGFloat(43.33)
    
    // main content height
    private static var contentHeight: CGFloat {
        165.0
    }
    
    var prevWalletCardViewState = WalletCardView.defaultState
    
    private var _cachedExpansionHeight = CGFloat(0)
    private var expansionHeight: CGFloat {
        if walletCardView?.state == prevWalletCardViewState {
            return _cachedExpansionHeight
        }
        _cachedExpansionHeight = walletCardView?.state ?? WalletCardView.defaultState == .expanded ? ((UIScreen.main.bounds.width - 32) * CARD_RATIO) - (BalanceHeaderView.contentHeight - 63) + (IOS_26_MODE_ENABLED ? 13 : 0) : 0
        return _cachedExpansionHeight
    }
    var calculatedHeight: CGFloat {
        BalanceHeaderView.contentHeight + self.expansionHeight
    }
    
    var isShowingSkeleton = true
    var isShowingSkeletonCompletely = true
    var isAnimatingHeight = false

    weak var vc: BalanceHeaderVC?
    weak var delegate: BalanceHeaderViewDelegate?
    
    var heightConstraint: NSLayoutConstraint!
    var walletNameLeadingConstraint: NSLayoutConstraint!
    
    private var mainWidth: CGFloat = 0
    
    // MARK: - Views
    var updateStatusViewContainer: UIView!
    var updateStatusView: UpdateStatusView!
    var updateStatusViewContainerTopConstraint: NSLayoutConstraint!
    
    // scrollable content
    var walletCardView: WalletCardView!
    var walletCardViewTopConstraint: NSLayoutConstraint!
    var walletCardViewBottomConstraint: NSLayoutConstraint!
    
    init(vc: BalanceHeaderVC, delegate: BalanceHeaderViewDelegate?) {
        self.vc = vc
        self.delegate = delegate
        super.init(frame: .zero)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        var constraints = [NSLayoutConstraint]()
        
        translatesAutoresizingMaskIntoConstraints = false
        heightConstraint = heightAnchor.constraint(equalToConstant: calculatedHeight)
        constraints.append(contentsOf: [
            heightConstraint,
            heightAnchor.constraint(greaterThanOrEqualToConstant: BalanceHeaderView.minHeight),
        ])
        
        // background should be clear to let refresh control appear
        backgroundColor = .clear
        
        setupWalletCardView()

        setupStatusView()

        constraints.append(contentsOf: [
            // to force actions compress on scroll
            bottomAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 51).withPriority(UILayoutPriority(999)),
            bottomAnchor.constraint(greaterThanOrEqualTo: walletCardView.bottomAnchor, constant: 16),
        ])
        
        NSLayoutConstraint.activate(constraints)
        
        updateTheme()
    }
    
    private func setupWalletCardView() {
        walletCardView = WalletCardView()
        // Constraint to hold card view on top in collapsed mode
        walletCardViewTopConstraint = walletCardView.topAnchor.constraint(equalTo: topAnchor, constant: 12).withPriority(.defaultHigh)
        
        addSubview(walletCardView)
        NSLayoutConstraint.activate([
            walletCardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            walletCardViewTopConstraint,
        ])
    }
    

    private func setupStatusView() {
        // update status view
        updateStatusViewContainer = UIView()
        updateStatusViewContainer.isUserInteractionEnabled = false
        updateStatusViewContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(updateStatusViewContainer)

        updateStatusView = UpdateStatusView()
        updateStatusViewContainer.addSubview(updateStatusView)

        updateStatusViewContainerTopConstraint = updateStatusViewContainer.topAnchor.constraint(equalTo: topAnchor)
        NSLayoutConstraint.activate([
            updateStatusViewContainerTopConstraint,
            updateStatusViewContainer.centerXAnchor.constraint(equalTo: centerXAnchor),

            updateStatusView.leftAnchor.constraint(equalTo: updateStatusViewContainer.leftAnchor),
            updateStatusView.rightAnchor.constraint(equalTo: updateStatusViewContainer.rightAnchor),
            updateStatusView.topAnchor.constraint(equalTo: updateStatusViewContainer.topAnchor),
            updateStatusView.bottomAnchor.constraint(equalTo: updateStatusViewContainer.bottomAnchor),
            updateStatusView.centerXAnchor.constraint(equalTo: updateStatusViewContainer.centerXAnchor),
        ])
    }
    
    // MARK: -
    
    override func layoutSubviews() {
        if mainWidth != frame.width {
            mainWidth = frame.width
            // All the subviews are setup and have constraints, let's update wallet card constraints
            walletCardView.layoutCardConstraints()
        }
        super.layoutSubviews()
    }

    func updateTheme() {
    }
    
    func accountChanged() {
        walletCardView.updateWithCurrentNft(accountChanged: true)
        let data = BalanceStore.currentAccountBalanceData
        update(
            balance: data?.totalBalance,
            balance24h: data?.totalBalanceYesterday,
            animated: false,
            onCompletion: nil
        )
    }
}

