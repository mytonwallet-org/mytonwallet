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
    func headerHeightChanged(animated: Bool)
    func expandHeader()
    var isTracking: Bool { get }
}


@MainActor
final class BalanceHeaderView: WTouchPassView, WThemedView {
    
    // MARK: View height
    
    // minimum height to show collapsed mode
    static let minHeight = CGFloat(39.33)
    
    // main content height
    private static let contentHeight = CGFloat(158)
    
    var prevWalletCardViewState = WalletCardView.defaultState
    
    private var _cachedExpansionHeight = CGFloat(0)
    private var expansionHeight: CGFloat {
        if walletCardView?.state == prevWalletCardViewState {
            return _cachedExpansionHeight
        }
        _cachedExpansionHeight = walletCardView?.state ?? WalletCardView.defaultState == .expanded ? ((UIScreen.main.bounds.width - 32) * 208 / 358) - 95 : 0
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
    
    private var mainWidth: CGFloat = 0
    
    // MARK: - Views
    var updateStatusViewContainer: UIView!
    var updateStatusView: UpdateStatusView!
    
    // top sticky content
    var balanceContainer: WSensitiveData<BalanceView> = .init(cols: 12, rows: 3, cellSize: 12, cornerRadius: 10, theme: .adaptive, alignment: .center)
    var balanceView: BalanceView!
    var balanceViewSkeleton: UIView!
    var walletNameLabel: UILabel!
    var walletNameLabelSkeleton: UIView!
    var balanceTopConstraint: NSLayoutConstraint!
    var walletNameBelowBalanceConstraint: NSLayoutConstraint!
    
    // scrollable content
    var walletCardView: WalletCardView!
    var walletCardViewTopConstraint: NSLayoutConstraint!
    var walletCardViewBottomConstraint: NSLayoutConstraint!
    var walletCardViewPreferredBottomConstraint: NSLayoutConstraint!
    
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
        
        setupBalanceView()

        setupWalletNameView()
        
        bringSubviewToFront(balanceViewSkeleton)
        bringSubviewToFront(walletNameLabelSkeleton)
        
        setupWalletCardView()

        setupStatusView()

        constraints.append(contentsOf: [
            // to push top sticky content up on scroll
            bottomAnchor.constraint(equalTo: balanceView.bottomAnchor, constant: 76).withPriority(.defaultHigh),
            
            // to force balanceView to come down on pull-to-refresh with scrolling
            bottomAnchor.constraint(lessThanOrEqualTo: balanceView.bottomAnchor, constant: 64).withPriority(.init(990)),
            
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
        
        // Constraint to hold card view on top of balance view in collapsed mode
        walletCardViewBottomConstraint = walletCardView.centerYAnchor.constraint(lessThanOrEqualTo: balanceView.centerYAnchor, constant: -58).withPriority(.init(900)) // break in expanded mode
        
        walletCardViewPreferredBottomConstraint = walletCardView.bottomAnchor.constraint(lessThanOrEqualTo: balanceView.topAnchor, constant: -28).withPriority(.init(500)) // break on scrolling, just to have a better default look in 0 scroll offset
       
        addSubview(walletCardView)
        NSLayoutConstraint.activate([
            walletCardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            walletCardViewTopConstraint,
            walletCardViewBottomConstraint,
            walletCardViewPreferredBottomConstraint
        ])
    }
    
    private func setupBalanceView() {
        
        // balance view skeleton
        balanceViewSkeleton = UIView()
        balanceViewSkeleton.translatesAutoresizingMaskIntoConstraints = false
        balanceViewSkeleton.layer.cornerRadius = 8
        addSubview(balanceViewSkeleton)

        // balance view
        balanceView = BalanceView(config: .balanceHeader)
        balanceView.isUserInteractionEnabled = false
        balanceView.alpha = 0
        addSubview(balanceContainer)
        balanceContainer.addContent(balanceView)
        balanceTopConstraint = balanceView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 0)
        
        NSLayoutConstraint.activate([
            // to center collapsed mode (44 - (16+22)) / 2 and prevent it from going out from top!
            balanceTopConstraint,
            
            // to force balanceView to stick to top, unless we scroll down and a high (or required) constraint layout comes in
            balanceView.topAnchor.constraint(lessThanOrEqualTo: topAnchor, constant: -2).withPriority(.defaultHigh),
            
            balanceView.centerXAnchor.constraint(equalTo: centerXAnchor).withPriority(.init(999)),

            balanceViewSkeleton.widthAnchor.constraint(equalToConstant: 134),
            balanceViewSkeleton.heightAnchor.constraint(equalToConstant: 42),
            balanceViewSkeleton.centerYAnchor.constraint(equalTo: balanceView.centerYAnchor),
            balanceViewSkeleton.centerXAnchor.constraint(equalTo: balanceView.centerXAnchor).withPriority(.init(998)),
            balanceViewSkeleton.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40).withPriority(.init(999)),
        ])
       
        let g = UITapGestureRecognizer(target: self, action: #selector(onBalanceTap))
        g.numberOfTapsRequired = 1
        balanceContainer.addGestureRecognizer(g)
    }

    private func setupStatusView() {
        // update status view
        updateStatusViewContainer = UIView()
        updateStatusViewContainer.isUserInteractionEnabled = false
        updateStatusViewContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(updateStatusViewContainer)

        updateStatusView = UpdateStatusView()
        updateStatusViewContainer.addSubview(updateStatusView)

        NSLayoutConstraint.activate([
            updateStatusViewContainer.topAnchor.constraint(equalTo: topAnchor, constant: -5),
            updateStatusViewContainer.centerXAnchor.constraint(equalTo: centerXAnchor),

            updateStatusView.leftAnchor.constraint(equalTo: updateStatusViewContainer.leftAnchor),
            updateStatusView.rightAnchor.constraint(equalTo: updateStatusViewContainer.rightAnchor),
            updateStatusView.topAnchor.constraint(equalTo: updateStatusViewContainer.topAnchor),
            updateStatusView.bottomAnchor.constraint(equalTo: updateStatusViewContainer.bottomAnchor),
            updateStatusView.centerXAnchor.constraint(equalTo: updateStatusViewContainer.centerXAnchor),
        ])
    }
    
    private func setupWalletNameView() {
        // wallet name label skeleton
        walletNameLabelSkeleton = UIView()
        walletNameLabelSkeleton.translatesAutoresizingMaskIntoConstraints = false
        walletNameLabelSkeleton.layer.cornerRadius = 8
        addSubview(walletNameLabelSkeleton)

        // wallet name label
        walletNameLabel = UILabel()
        walletNameLabel.translatesAutoresizingMaskIntoConstraints = false
        walletNameLabel.textColor = WTheme.balanceHeaderView.secondary
        walletNameLabel.font = .systemFont(ofSize: 17, weight: .regular)
        walletNameLabel.alpha = 0
        walletNameLabel.textAlignment = .center
        walletNameLabel.text = lang("My Wallet")
        addSubview(walletNameLabel)
        walletNameBelowBalanceConstraint = walletNameLabel.topAnchor.constraint(equalTo: balanceView.bottomAnchor, constant: 8)
        NSLayoutConstraint.activate([
            walletNameLabel.centerXAnchor.constraint(equalTo: balanceView.centerXAnchor).withPriority(.init(999)),
            walletNameBelowBalanceConstraint,

            walletNameLabelSkeleton.widthAnchor.constraint(equalToConstant: 80),
            walletNameLabelSkeleton.heightAnchor.constraint(equalToConstant: 26),
            walletNameLabelSkeleton.centerYAnchor.constraint(equalTo: walletNameLabel.centerYAnchor),
            walletNameLabelSkeleton.centerXAnchor.constraint(equalTo: walletNameLabel.centerXAnchor),

            walletNameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            walletNameLabelSkeleton.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40)
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
        balanceViewSkeleton.backgroundColor = WTheme.balanceHeaderView.skeleton
        walletNameLabelSkeleton.backgroundColor = WTheme.balanceHeaderView.skeleton
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
    
    @objc func onBalanceTap() {
        let isHidden = AppStorageHelper.isSensitiveDataHidden
        AppActions.setSensitiveDataIsHidden(!isHidden)
    }
}

