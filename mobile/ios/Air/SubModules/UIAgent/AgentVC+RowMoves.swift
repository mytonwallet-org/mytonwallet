import UIKit

extension AgentVC {
    /// Where the questions that wait at the chat's end, and the one that is going, stand on screen, for
    /// `moveWaitingRows(from:)` to move them from there once the list puts them elsewhere. Read before the list changes;
    /// empty while rows take their places at once, with animations off or Reduce Motion.
    func getWaitingRowScreenMinYs() -> [AgentItemID: CGFloat] {
        let itemIDs = model.trailingItemIDs + (model.revealingWaitingMessageID.map { [$0] } ?? [])
        guard !itemIDs.isEmpty, view.window != nil, UIView.areAnimationsEnabled,
              !UIAccessibility.isReduceMotionEnabled else { return [:] }
        let offsetY = collectionView.contentOffset.y
        var minYs: [AgentItemID: CGFloat] = [:]
        for itemID in itemIDs {
            guard let indexPath = messageIndexPath(for: itemID),
                  let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { continue }
            minYs[itemID] = frame.minY - offsetY
        }
        return minYs
    }

    /// Keeps the list's scrollable extent as the rows the model no longer has leave it, a stopped typing row above the
    /// questions that wait among them, so the list never scrolls back to fit what stays. Fitting the reserve to the
    /// offset after the update gives back what the offset doesn't need.
    func reserveSpaceForLeavingRows() {
        let itemIDs = Set(model.itemIDs)
        for itemID in snapshotMessageIDs() where !itemIDs.contains(itemID) {
            guard let indexPath = messageIndexPath(for: itemID) else { continue }
            reserveSpaceForLeavingRow(at: indexPath)
        }
    }

    /// Moves the rows of `screenMinYs` from where they stood on screen to where the list has put them, as rows above
    /// them come, go or change their height, rather than in one frame: on Telegram's list curve, as the chat closes the
    /// gap a message turning to dust leaves. The rows above stay where they show.
    func moveWaitingRows(from screenMinYs: [AgentItemID: CGFloat]) {
        guard !screenMinYs.isEmpty else { return }
        collectionView.layoutIfNeeded()
        let offsetY = collectionView.contentOffset.y
        let startTime = CACurrentMediaTime()
        // Each change has its own key, so a move that starts while another runs adds to it
        let key = Self.rowMoveAnimationKey + "." + UUID().uuidString
        for (itemID, minYBefore) in screenMinYs {
            guard let indexPath = messageIndexPath(for: itemID),
                  let cell = collectionView.cellForItem(at: indexPath) else { continue }
            // A row UIKit moves itself, in an animated update, glides already
            guard cell.layer.animation(forKey: "position") == nil else { continue }
            let shift = minYBefore - (cell.frame.minY - offsetY)
            guard abs(shift) > 0.5, abs(shift) < collectionView.bounds.height else { continue }
            let animation = CABasicAnimation(keyPath: "position")
            animation.isAdditive = true
            animation.fromValue = NSValue(cgPoint: CGPoint(x: 0, y: shift))
            animation.toValue = NSValue(cgPoint: .zero)
            animation.duration = AgentVCLayout.dissolvedGapCloseDuration
            animation.timingFunction = Self.makeRowMoveTiming()
            // The rows move together
            animation.beginTime = cell.layer.convertTime(startTime, from: nil)
            cell.layer.add(animation, forKey: key)
        }
    }

    /// Telegram's list curve
    private static func makeRowMoveTiming() -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    }
}
