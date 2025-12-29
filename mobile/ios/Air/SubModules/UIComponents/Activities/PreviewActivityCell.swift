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
    
    public func configure(withPreviewActivity activity: ApiActivity, delegate: Delegate?, shouldFadeOutSkeleton: Bool) {
        
        if shouldFadeOutSkeleton {
            skeletonView?.layer.maskedCorners = contentView.layer.maskedCorners
            fadeOutSkeleton()
        } else if skeletonView?.alpha ?? 0 > 0 {
            skeletonView?.alpha = 0
            mainView.alpha = 1
        }
        self.activity = activity
        self.delegate = delegate

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        iconView.config(with: activity)
        
        let shouldShowCenteredTitle = activity.shouldShowCenteredTitle
        if shouldShowCenteredTitle {
            configureCenteredLabel(activity: activity)
        }
        configureTitle(activity: activity, isEmulation: true)
        configureDetails(activity: activity, isEmulation: true)
        centeredLabel.isHidden = !shouldShowCenteredTitle
        titleLabel.isHidden = shouldShowCenteredTitle
        detailsLabel.isHidden = shouldShowCenteredTitle
        
        configureAmount(activity: activity)
        configureAmount2(activity: activity)
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
    
    public var activity: ApiActivity
    
    public init(activity: ApiActivity) {
        self.activity = activity
    }
    
    public func makeUIView(context: Context) -> PreviewActivityCell {
        PreviewActivityCell()
    }
    
    public func updateUIView(_ cell: PreviewActivityCell, context: Context) {
        cell.configure(withPreviewActivity: activity, delegate: nil, shouldFadeOutSkeleton: false)
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
