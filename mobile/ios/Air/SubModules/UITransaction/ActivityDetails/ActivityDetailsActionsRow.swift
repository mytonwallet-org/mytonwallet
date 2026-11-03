import ContextMenuKit
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception

struct ActivityDetailsActionsRow: View {

    var model: ActivityDetailsViewModel

    var shouldShowRepeat: Bool {
        let account = model.accountContext.account
        guard account.type != .view else { return false }
        
        switch model.activity {
        case .transaction(let tx):
            if tx.isStaking {
                return account.supportsEarn
            }
            if tx.isIncoming || tx.type != nil || tx.nft != nil {
                return false
            }
            return account.supportsSend
        case .swap(let swap):
            let status = swap.displayStatus(at: model.currentDate)
            return account.supportsSwap && (swap.cex == nil || (!status.isPending && status != .hold))
        }
    }

    private var shareUrl: URL? {
        let activity = model.activity
        let chain: ApiChain
        let txHash: String
        if let swap = activity.swap {
            let transactionIds = swap.displayTransactionIds
            guard let reference = transactionIds.outgoing ?? transactionIds.incoming else { return nil }
            chain = reference.chain
            txHash = reference.hash
        } else {
            guard let tokenChain = TokenStore.tokens[activity.slug]?.chain else { return nil }
            chain = tokenChain
            txHash = activity.parsedTxId.hash
        }
        guard chain.isSupported else { return nil }
        
        let url = ExplorerHelper.viewTransactionUrl(network: model.accountContext.account.network, chain: chain, txHash: txHash)
        return url
    }
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            
            let shareUrl = self.shareUrl
            ReceiptActionsView(
                onDetails: model.detailsCollapseEnabled ? { model.onDetailsExpanded() } : nil,
                onRepeat: shouldShowRepeat ? { AppActions.repeatActivity(accountContext: model.accountContext, model.activity) } : nil,
                onShare: shareUrl.map { url in { AppActions.shareUrl(url) } },
                onWearMenu: model.wearableNft != nil ? {
                    model.refreshWearableNft()
                    guard let nft = model.wearableNft else { return nil }
                    return MtwCardWearMenu.makeConfiguration(
                        accountId: model.accountContext.accountId,
                        nft: nft,
                        source: "activityDetails"
                    )
                } : nil,
                detailsExpanded: model.detailsExpanded
            )
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }
}
