import UIKit
import UIComponents

/// A list of the Agent's that ends at its latest row, as a chat and the News feed do. It opens at that row, scrolls to
/// it on Telegram's spring, and shows the scroll-to-bottom button while the row is out of reach.
@MainActor
protocol AgentChatListScrolling: AnyObject {
    /// What names a row the list keeps in place as rows come and go above it
    associatedtype AnchorItemID: Hashable

    var collectionView: AgentCollectionView { get }
    var listScrollAnimator: AgentListScrollAnimator { get }
    var scrollToBottomButton: AgentScrollToBottomButton { get }
    /// The row the list ends at
    var lastItemIndexPath: IndexPath? { get }
    /// The height at the list's bottom that what stands over it covers
    var occlusionBottomInset: CGFloat { get }
    /// The offset the list is heading to while it moves on its own, otherwise its offset
    var headingContentOffsetY: CGFloat { get }
    /// Keeps the scroll-to-bottom button away while it would stand in the way of something
    var isScrollToBottomButtonHeld: Bool { get }
    /// A scroll to the latest row reached it or was stopped
    func listDidEndScrollingToLatest()
    /// The row at `indexPath` if the list keeps it in place: a message or a news card rather than a date line
    func getAnchorItemID(at indexPath: IndexPath) -> AnchorItemID?
    func getIndexPath(forAnchorItemID itemID: AnchorItemID) -> IndexPath?
}

/// A row on screen and where it and the list stood, to keep it where it is as rows come in above it
struct AgentListAnchor<ItemID: Hashable> {
    let itemID: ItemID
    let minY: CGFloat
    let offsetY: CGFloat
}

extension AgentChatListScrolling {
    var maxContentOffsetY: CGFloat {
        let minY = -collectionView.adjustedContentInset.top
        let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        return max(minY, contentHeight - collectionView.bounds.height + collectionView.adjustedContentInset.bottom)
    }

    func clampedContentOffsetY(_ rawY: CGFloat) -> CGFloat {
        min(max(rawY, -collectionView.adjustedContentInset.top), maxContentOffsetY)
    }

    /// Goes to the latest row, as the scroll-to-bottom button and a tap on the current tab do
    func scrollToLatest(animated: Bool) {
        guard let indexPath = lastItemIndexPath else { return }
        scrollToBottom(of: indexPath, animated: animated)
        if !animated {
            revealLastItemSettlingRowHeights()
        }
    }

    func scrollToBottom(of indexPath: IndexPath, animated: Bool) {
        guard let offsetY = getBottomOffsetY(of: indexPath) else { return }
        guard animated else {
            listScrollAnimator.stop()
            collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: offsetY), animated: false)
            return
        }
        collectionView.isScrollingToLatest = true
        listScrollAnimator.scroll(
            to: { [weak self] in
                guard let self, let indexPath = self.lastItemIndexPath else { return nil }
                return self.getBottomOffsetY(of: indexPath)
            },
            settleJump: { [weak self] in self?.revealLastItemSettlingRowHeights() }
        ) { [weak self] isFinished in
            guard let self, self.collectionView.isScrollingToLatest else { return }
            self.collectionView.isScrollingToLatest = false
            self.listDidEndScrollingToLatest()
            guard isFinished else { return }
            self.revealLastItemSettlingRowHeights()
            self.updateScrollToBottomButtonVisibility(animated: false)
        }
    }

    /// The offset that puts the bottom of the row at `indexPath` just above what covers the list's bottom
    func getBottomOffsetY(of indexPath: IndexPath) -> CGFloat? {
        guard let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return nil }
        return clampedContentOffsetY(frame.maxY - collectionView.bounds.height + occlusionBottomInset)
    }

    func revealLastItemIfNeeded(animated: Bool) {
        guard let indexPath = lastItemIndexPath else { return }
        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }
        let visibleBottom = collectionView.contentOffset.y
            + collectionView.bounds.height
            - occlusionBottomInset
        guard attributes.frame.maxY > visibleBottom + 0.5 else { return }
        scrollToBottom(of: indexPath, animated: animated)
    }

    func revealLastItemSettlingRowHeights() {
        guard let indexPath = lastItemIndexPath else { return }
        // Each pass can expose another estimated row; allow a final pass to settle its bottom
        for _ in 0...collectionView.numberOfItems(inSection: indexPath.section) {
            let offsetY = collectionView.contentOffset.y
            let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame
            revealLastItemIfNeeded(animated: false)
            collectionView.layoutIfNeeded()
            guard abs(collectionView.contentOffset.y - offsetY) > 0.5
                || collectionView.layoutAttributesForItem(at: indexPath)?.frame != frame else { return }
        }
    }

    /// Puts the row at `indexPath` at the top of the list's visible area, as a chat and the News feed open at their first
    /// unread row, settling the heights of the rows on the way there
    func revealItemAtTop(_ indexPath: IndexPath) {
        listScrollAnimator.stop()
        for _ in 0...collectionView.numberOfItems(inSection: indexPath.section) {
            collectionView.layoutIfNeeded()
            guard let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return }
            let offsetY = clampedContentOffsetY(frame.minY - collectionView.adjustedContentInset.top)
            guard abs(collectionView.contentOffset.y - offsetY) > 0.5 else { return }
            collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: offsetY), animated: false)
        }
    }

    /// The highest anchor row on screen, as older rows are about to come in above it
    func paginationAnchor() -> AgentListAnchor<AnchorItemID>? {
        guard let indexPath = collectionView.indexPathsForVisibleItems.filter({ getAnchorItemID(at: $0) != nil }).min(),
              let itemID = getAnchorItemID(at: indexPath),
              let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return nil }
        return AgentListAnchor(itemID: itemID, minY: frame.minY, offsetY: collectionView.contentOffset.y)
    }

    /// Moves the list so the anchor's row stands where it stood. Rows that come into view above it at their estimated
    /// heights take their own as the list lays them out, which moves the row again, so the list keeps it in place until
    /// they have settled.
    func restorePaginationAnchor(_ anchor: AgentListAnchor<AnchorItemID>) {
        collectionView.layoutIfNeeded()
        guard let indexPath = getIndexPath(forAnchorItemID: anchor.itemID) else { return }
        // A list pulled past its top keeps the pull for UIKit to spring back from, rather than jumping by it
        let isPulledPastTop = anchor.offsetY < -collectionView.adjustedContentInset.top
        for _ in 0...collectionView.numberOfItems(inSection: indexPath.section) {
            guard let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return }
            let rawOffsetY = anchor.offsetY + frame.minY - anchor.minY
            let offsetY = isPulledPastTop ? min(rawOffsetY, maxContentOffsetY) : clampedContentOffsetY(rawOffsetY)
            let shift = abs(collectionView.contentOffset.y - offsetY)
            if shift > 0.01 {
                collectionView.contentOffset.y = offsetY
            }
            guard shift > 0.5 else { return }
            collectionView.layoutIfNeeded()
        }
    }

    /// The list is close enough to its top to load what came before its first row
    var isNearTopForLoadingOlder: Bool {
        collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + AgentVCLayout.loadOlderThreshold
    }

    func isNearBottom() -> Bool {
        // A scroll to the latest row is as good as there, so the scroll button goes as it starts
        if collectionView.isScrollingToLatest, listScrollAnimator.isRunning {
            return true
        }
        guard collectionView.bounds.height > 0,
              let indexPath = lastItemIndexPath,
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
            return true
        }
        let visibleBottom = headingContentOffsetY + collectionView.bounds.height - occlusionBottomInset
        return attributes.frame.maxY <= visibleBottom + AgentVCLayout.nearBottomThreshold
    }

    func updateScrollToBottomButtonVisibility(animated: Bool) {
        scrollToBottomButton.setButtonVisible(!isNearBottom() && !isScrollToBottomButtonHeld, animated: animated)
    }
}
