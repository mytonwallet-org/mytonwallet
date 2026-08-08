//
//  BalanceHeaderView.swift
//
//  Created by Sina on 4/20/23.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

private let additionalSpacingToNavigationBar: CGFloat = 6
private let standardCollapsedHeight: CGFloat = 102.0

@MainActor protocol BalanceHeaderViewDelegate: AnyObject {
    func headerIsAnimating()
    var isTracking: Bool { get }
}


@MainActor
final class BalanceHeaderView: WTouchPassView, Sendable {
    
    let headerViewModel: HomeHeaderViewModel
    let accountSource: AccountSource
    let updateStatusAccountContext: AccountContext
    
    // MARK: View height
    
    // minimum height to show collapsed mode
    static let minHeight = CGFloat(43.33)

    var minimumHeight: CGFloat {
        headerViewModel.rootNavigationStyle.usesNavigationBarTopTabs ? 0 : Self.minHeight
    }
    
    var prevWalletCardViewState: HomeHeaderState = .expanded
    
    var lastStateChange: Date = .distantPast
    var cardLayoutMetrics: HomeCardLayoutMetrics = .screen
    
    var calculatedHeight: CGFloat {
        if headerViewModel.state == .expanded {
            cardLayoutMetrics.itemHeight - expansionInset + additionalSpacingToNavigationBar
        } else if headerViewModel.rootNavigationStyle.usesNavigationBarTopTabs {
            headerViewModel.collapsedHeight
        } else {
            standardCollapsedHeight + (IOS_26_MODE_ENABLED ? 0.0 : 12.0)
        }
    }
    
    weak var delegate: BalanceHeaderViewDelegate?
    
    var heightConstraint: NSLayoutConstraint!
    
    // MARK: - Views
    var updateStatusViewContainer: UIView!
    var updateStatusView: UpdateStatusView!
    var updateStatusViewContainerTopConstraint: NSLayoutConstraint!
    
    init(headerViewModel: HomeHeaderViewModel, accountSource: AccountSource, delegate: BalanceHeaderViewDelegate?) {
        self.headerViewModel = headerViewModel
        self.accountSource = accountSource
        self.updateStatusAccountContext = AccountContext(source: accountSource)
        self.delegate = delegate
        super.init(frame: .zero)
        setupViews()
        prepareTransitionGenerator()
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
            heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight),
        ])
        
        // background should be clear to let refresh control appear
        backgroundColor = .clear
        
        setupStatusView()

        constraints.append(contentsOf: [
            // to force actions compress on scroll
            bottomAnchor.constraint(
                greaterThanOrEqualTo: topAnchor,
                constant: headerViewModel.rootNavigationStyle.usesNavigationBarTopTabs ? 0 : 51
            ).withPriority(UILayoutPriority(999)),
        ])
        
        NSLayoutConstraint.activate(constraints)
        
    }
    
    private func setupStatusView() {
        // update status view
        updateStatusViewContainer = UIView()
        updateStatusViewContainer.isUserInteractionEnabled = false
        updateStatusViewContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(updateStatusViewContainer)

        updateStatusView = UpdateStatusView(accountContext: updateStatusAccountContext)
        updateStatusViewContainer.addSubview(updateStatusView)

        updateStatusViewContainerTopConstraint = updateStatusViewContainer.topAnchor.constraint(equalTo: topAnchor)
        NSLayoutConstraint.activate([
            updateStatusViewContainerTopConstraint,
            updateStatusViewContainer.centerXAnchor.constraint(equalTo: centerXAnchor),

            updateStatusView.leadingAnchor.constraint(equalTo: updateStatusViewContainer.leadingAnchor),
            updateStatusView.trailingAnchor.constraint(equalTo: updateStatusViewContainer.trailingAnchor),
            updateStatusView.topAnchor.constraint(equalTo: updateStatusViewContainer.topAnchor),
            updateStatusView.bottomAnchor.constraint(equalTo: updateStatusViewContainer.bottomAnchor),
            updateStatusView.centerXAnchor.constraint(equalTo: updateStatusViewContainer.centerXAnchor),
        ])
    }

    private func prepareTransitionGenerator() {
        Haptics.prepare(.transition)
    }
}
