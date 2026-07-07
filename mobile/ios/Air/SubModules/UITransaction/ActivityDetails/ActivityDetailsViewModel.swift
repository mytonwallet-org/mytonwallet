
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
    var isLoadingDetails = false

    @PerceptionIgnored
    private var detailsFetchTask: Task<Void, Never>?
    @PerceptionIgnored
    private var loadingDetailsActivityId: String?
    @PerceptionIgnored
    private var attemptedDetailsActivityIds = Set<String>()
    
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

    deinit {
        detailsFetchTask?.cancel()
    }
    
    func onDetailsExpanded() {
        guard detailsCollapseEnabled else { return }
        self.detailsExpanded.toggle()
        onDetailsExpandedChanged()
    }

    @discardableResult
    func updateActivity(_ newActivity: ApiActivity) -> Bool {
        guard !shouldIgnoreDetailsRegression(newActivity) else {
            return false
        }
        guard activity != newActivity else {
            fetchDetailsIfNeeded()
            return false
        }
        activity = newActivity
        fetchDetailsIfNeeded()
        return true
    }

    func fetchDetailsIfNeeded() {
        guard activity.shouldLoadDetails == true else {
            if isLoadingDetails {
                isLoadingDetails = false
            }
            return
        }

        let activity = activity
        let activityId = activity.id
        guard loadingDetailsActivityId != activityId else { return }
        guard !attemptedDetailsActivityIds.contains(activityId) else { return }

        if let detailsFetchTask {
            detailsFetchTask.cancel()
            self.detailsFetchTask = nil
            loadingDetailsActivityId = nil
            isLoadingDetails = false
        }

        attemptedDetailsActivityIds.insert(activityId)
        loadingDetailsActivityId = activityId
        isLoadingDetails = true

        detailsFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let detailedActivity = try await ActivityStore.fetchActivityDetails(
                    accountId: self.accountContext.accountId,
                    activity: activity
                )
                guard !Task.isCancelled else { return }
                guard self.activity.id == activityId else {
                    self.finishDetailsFetch(activityId: activityId)
                    return
                }
                self.activity = detailedActivity
                self.finishDetailsFetch(activityId: activityId)
            } catch {
                self.finishDetailsFetch(activityId: activityId)
            }
        }
    }

    private func finishDetailsFetch(activityId: String) {
        guard loadingDetailsActivityId == activityId else { return }
        loadingDetailsActivityId = nil
        detailsFetchTask = nil
        isLoadingDetails = false
    }

    private func shouldIgnoreDetailsRegression(_ newActivity: ApiActivity) -> Bool {
        activity.id == newActivity.id
        && attemptedDetailsActivityIds.contains(activity.id)
        && activity.shouldLoadDetails != true
        && newActivity.shouldLoadDetails == true
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
