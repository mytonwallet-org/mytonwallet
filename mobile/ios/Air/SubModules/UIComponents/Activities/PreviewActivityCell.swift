//
//  PreviewActivityCell.swift
//  UIComponents
//
//  Created by nikstar on 20.08.2025.
//

import UIKit
import WalletCore
import WalletContext
import SwiftUI

public class PreviewActivityCell: ActivityCell {
    
    var centeredLabel = UILabel()
    
    override func setupViews() {
        super.setupViews()
        
        centeredLabel.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(centeredLabel)
        centeredLabel.font = ActivityCell.medium16Font
        NSLayoutConstraint.activate([
            centeredLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            centeredLabel.leadingAnchor.constraint(equalTo: firstTwoRows.leadingAnchor),
        ])
    }
    
    public struct ConfigureOptions {
        var detailsOptions: ConfigureDetailsOptions
        var amountOptions: ConfigureAmountOptions

        public init(activity: ApiActivity, accountContext: AccountContext, tokenStore: _TokenStore) {
            self.detailsOptions = .init(activity: activity, accountContext: accountContext, isEmulation: true)
            self.amountOptions = .init(activity: activity, tokenStore: tokenStore)
        }
    }
    
    fileprivate func configure(_ options: ConfigureOptions) {
        let activity = options.detailsOptions.activity
        
        if skeletonView?.alpha ?? 0 > 0 {
            skeletonView?.alpha = 0
            mainView.alpha = 1
        }
        self.activity = activity
        self.delegate = nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)
                        
        iconView.config(with: activity)
        
        let shouldShowCenteredTitle = activity.shouldShowCenteredTitle
        if shouldShowCenteredTitle {
            configureCenteredLabel(activity: activity)
        }
        configureTitle(activity: activity, isEmulation: options.detailsOptions.isEmulation)
        configureDetails(options.detailsOptions)
        centeredLabel.isHidden = !shouldShowCenteredTitle
        titleLabel.isHidden = shouldShowCenteredTitle
        detailsLabel.isHidden = shouldShowCenteredTitle
                
        configureAmount(options.amountOptions)
        configureAmount2(options.amountOptions)
        configureSensitiveData(activity: activity)
        configureNft(activity: activity)
        configureComment(activity: activity)
        
        nftAndCommentConstraint.isActive = !nftView.isHidden && !commentView.isHidden
        
        UIView.performWithoutAnimation {
            setNeedsLayout()
            layoutIfNeeded()
        }
        
        CATransaction.commit()
    }
    
    func configureCenteredLabel(activity: ApiActivity) {
        centeredLabel.text = activity.displayTitle.future
    }
}

public struct WPreviewActivityCell: UIViewRepresentable {
    public var configureOptions: PreviewActivityCell.ConfigureOptions
    
    public init(_ configureOptions: PreviewActivityCell.ConfigureOptions) {
        self.configureOptions = configureOptions
    }
    
    public func makeUIView(context: Context) -> PreviewActivityCell {
        let cell =  PreviewActivityCell()
        cell.configure(configureOptions)
        return cell
    }
    
    public func updateUIView(_ cell: PreviewActivityCell, context: Context) {
        Task { @MainActor in cell.configure(configureOptions) }
    }
    
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView cell: PreviewActivityCell, context: Context) -> CGSize? {
        var fitting = cell.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        if let w = proposal.width, w > fitting.width {
            fitting.width = w
        }
        return .some(fitting)
    }
}

#if DEBUG
//@available(iOS 18, *)
//#Preview {
//    let activity = ApiActivity.transaction(ApiTransactionActivity(id: "d", kind: "transaction", timestamp: 0, amount: 123456789, fromAddress: "foo", toAddress: "bar", comment: nil, encryptedComment: nil, fee: 12345, slug: TON_USDT_SLUG, isIncoming: false, normalizedAddress: nil, externalMsgHashNorm: nil, shouldHide: nil, type: nil, metadata: nil, nft: nil, status: .pending))
//
//    WPreviewActivityCell(activity: activity)
//        .padding()
//        .background(Color.blue)
//}
#endif
