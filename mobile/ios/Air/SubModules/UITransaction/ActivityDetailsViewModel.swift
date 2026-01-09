
import SwiftUI
import WalletContext
import WalletCore
import Perception

@Perceptible
final class ActivityDetailsViewModel {
    var activity: ApiActivity
    var detailsExpanded: Bool
    var scrollingDisabled: Bool = true
    var collapsedHeight: CGFloat = 0
    var expandedHeight: CGFloat = 0
    var progressiveRevealEnabled = true
    
    @PerceptionIgnored
    var onHeightChange: () -> () = { }
    @PerceptionIgnored
    var onDetailsExpandedChanged: () -> () = { }
    
    let accountContext: AccountContext

    init(activity: ApiActivity, accountId: String?, detailsExpanded: Bool, scrollingDisabled: Bool) {
        self.activity = activity
        self.accountContext = AccountContext(accountId: accountId)
        self.detailsExpanded = detailsExpanded
        self.scrollingDisabled = scrollingDisabled
    }
    
    func onDetailsExpanded() {
        self.detailsExpanded.toggle()
        onDetailsExpandedChanged()
    }
}
