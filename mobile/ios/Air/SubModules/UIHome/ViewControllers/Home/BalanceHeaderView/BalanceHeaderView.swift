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
    var isTracking: Bool { get }
}


@MainActor
final class BalanceHeaderView: WTouchPassView, WThemedView, Sendable {
    
    let headerViewModel: HomeHeaderViewModel
    let accountSource: AccountSource
    
    // MARK: View height
    
    // minimum height to show collapsed mode
    static let minHeight = CGFloat(43.33)
    
    var prevWalletCardViewState: HomeHeaderState = .expanded
    
    var lastStateChange: Date = .distantPast
    
    var calculatedHeight: CGFloat {
        if headerViewModel.state == .expanded {
            itemHeight + 63 + (IOS_26_MODE_ENABLED ? 13 : 0) - expansionInset
        } else {
            165.0
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
            heightAnchor.constraint(greaterThanOrEqualToConstant: BalanceHeaderView.minHeight),
        ])
        
        // background should be clear to let refresh control appear
        backgroundColor = .clear
        
        setupStatusView()

        constraints.append(contentsOf: [
            // to force actions compress on scroll
            bottomAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 51).withPriority(UILayoutPriority(999)),
        ])
        
        NSLayoutConstraint.activate(constraints)
        
        updateTheme()
    }
    
    private func setupStatusView() {
        // update status view
        updateStatusViewContainer = UIView()
        updateStatusViewContainer.isUserInteractionEnabled = false
        updateStatusViewContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(updateStatusViewContainer)

        updateStatusView = UpdateStatusView(accountSource: accountSource)
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

    private func prepareTransitionGenerator() {
        Haptics.prepare(.transition)
    }

    func updateTheme() {
    }
}

