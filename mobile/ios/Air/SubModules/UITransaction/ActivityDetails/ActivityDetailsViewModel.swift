
import SwiftUI
import WalletContext
import WalletCore
import Perception

@Perceptible @MainActor
final class ActivityDetailsViewModel {
    var activity: ApiActivity {
        didSet {
            refreshScamStatus()
        }
    }
    var isScam: Bool = false
    var detailsExpanded: Bool
    var detailsCollapseEnabled: Bool = true
    var scrollingDisabled: Bool = true
    var collapsedHeight: CGFloat = 0
    var expandedHeight: CGFloat = 0
    var progressiveRevealEnabled = true
    
    @PerceptionIgnored
    var onHeightChange: () -> () = { }
    @PerceptionIgnored
    var onDetailsExpandedChanged: () -> () = { }
    
    let accountContext: AccountContext
    let context: ActivityDetailsContext

    init(activity: ApiActivity, accountSource: AccountSource, detailsExpanded: Bool, scrollingDisabled: Bool, context: ActivityDetailsContext) {
        self.activity = activity
        self.accountContext = AccountContext(source: accountSource)
        self.detailsExpanded = detailsExpanded
        self.scrollingDisabled = scrollingDisabled
        self.context = context
        refreshScamStatus()
    }
    
    func onDetailsExpanded() {
        guard detailsCollapseEnabled else { return }
        self.detailsExpanded.toggle()
        onDetailsExpandedChanged()
    }

    func refreshScamStatus() {
        Task {
            guard case .transaction(let transaction) = activity else {
                isScam = false
                return
            }
            let activityId = transaction.id
            let isMetadataScam = transaction.metadata?.isScam == true
            let isPoisoning: Bool = transaction.isIncoming ? await ActivityStore.isTransactionWithPoisoning(accountId: accountContext.accountId, transaction: transaction) : false
            if activity.id == activityId {
                isScam = isMetadataScam || isPoisoning
            }
        }
    }
}
