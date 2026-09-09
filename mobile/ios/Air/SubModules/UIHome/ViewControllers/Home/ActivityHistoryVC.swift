import UIKit
import UIActivityList
import UIComponents
import WalletContext
import WalletCore

@MainActor
final class ActivityHistoryVC: ActivityListViewController, ActivityListViewModelDelegate {
    private var pendingInitialActivityID: String?
    private var initialSnapshotContinuation: CheckedContinuation<Void, Never>?

    override var headerPlaceholderHeight: CGFloat { 0 }

    init(accountId: String, initialActivityID: String? = nil) async {
        self.pendingInitialActivityID = initialActivityID
        super.init(nibName: nil, bundle: nil)

        activityViewModel = await ActivityListViewModel(
            accountId: accountId,
            token: nil,
            delegate: self
        )
        if let initialActivityID,
           activityViewModel?.snapshot.indexOfItem(.transaction(accountId, initialActivityID)) == nil {
            pendingInitialActivityID = nil
        }
        await withCheckedContinuation { continuation in
            initialSnapshotContinuation = continuation
            loadViewIfNeeded()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        super.loadView()
        view.backgroundColor = .air.groupedBackground
        navigationItem.title = lang("Activity")
        setupCollectionView(collectionViewBottomConstraint: 0)
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            collectionView.topEdgeEffect.isHidden = true
        }
        addCustomNavigationBarBackground(color: .air.groupedBackground)
        isInitializingCache = false
        applySnapshot(makeSnapshot(), animatingDifferences: false)
        updateSkeletonState()
    }

    func activityViewModelChanged() {
        guard isViewLoaded else { return }
        transactionsUpdated(accountChanged: false, isUpdateEvent: true)
    }

    override func didApplySnapshot() {
        super.didApplySnapshot()
        let continuation = initialSnapshotContinuation
        initialSnapshotContinuation = nil
        continuation?.resume()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        guard let pendingInitialActivityID else { return }
        self.pendingInitialActivityID = nil
        UIView.performWithoutAnimation {
            view.layoutIfNeeded()
            scrollToActivity(stableID: pendingInitialActivityID, animated: false)
        }
    }

    override func updateSkeletonViewMask() {
        var skeletonViews = collectionView.visibleCells.compactMap { cell in
            (cell as? ActivityCell)?.contentView
        }
        skeletonViews += collectionView
            .visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader)
            .compactMap { view in
                (view as? ActivityDateCell)?.skeletonView
            }
        skeletonView.applyMask(with: skeletonViews)
    }
}
