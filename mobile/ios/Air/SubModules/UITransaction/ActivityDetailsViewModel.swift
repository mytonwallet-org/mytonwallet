
import SwiftUI
import WalletContext
import WalletCore

final class ActivityDetailsViewModel: ObservableObject {
    @Published var activity: ApiActivity
    @Published var detailsExpanded: Bool
    @Published var scrollingDisabled: Bool = true
    @Published var collapsedHeight: CGFloat = 0
    @Published var expandedHeight: CGFloat = 0
    @Published var progressiveRevealEnabled = true
    
    var onHeightChange: () -> () = { }
    var onDetailsExpandedChanged: () -> () = { }

    init(activity: ApiActivity, detailsExpanded: Bool, scrollingDisabled: Bool) {
        self.activity = activity
        self.detailsExpanded = detailsExpanded
        self.scrollingDisabled = scrollingDisabled
    }
    
    func onDetailsExpanded() {
        self.detailsExpanded.toggle()
        onDetailsExpandedChanged()
    }
}
