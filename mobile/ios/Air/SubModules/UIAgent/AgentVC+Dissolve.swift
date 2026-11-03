import UIKit
import UIComponents

extension AgentVC {
    /// Takes the rows `itemIDs` out of the chat as `change` removes them, as Telegram deletes messages: a row on screen
    /// turns to dust where it stood, or fades out with Reduce Motion, and the rows that stay close the gap it leaves.
    /// Rows off screen simply go.
    func dissolveItems(_ itemIDs: [AgentItemID], during change: () -> Void) {
        guard !itemIDs.isEmpty, view.window != nil else {
            change()
            return
        }
        collectionView.layoutIfNeeded()
        let leavingItemIDs = Set(itemIDs.map { ListItemID.message($0) })
        let offsetBefore = collectionView.contentOffset.y
        var rowsBefore: [ListItemID: CGFloat] = [:]
        var hiddenCells: [UICollectionViewCell] = []
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  let listItemID = dataSource.itemIdentifier(for: indexPath) else { continue }
            if !leavingItemIDs.contains(listItemID) {
                rowsBefore[listItemID] = cell.frame.minY - offsetBefore
            } else if dissolveVisiblePart(of: cell) {
                hiddenCells.append(cell)
            }
        }

        change()

        // A cell that went with its row shows again as it ends displaying it; one that still shows a row shows it now
        for cell in hiddenCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  dataSource.itemIdentifier(for: indexPath) != nil else { continue }
            cell.contentView.isHidden = false
        }
        let remainingItemIDs = Set(model.itemIDs)
        if itemIDs.contains(where: remainingItemIDs.contains) {
            // A row that stayed shows as it is, rather than under its own dust
            removeMessageDissolveView()
        } else if messageDissolveView != nil {
            dissolvingItemIDs.formUnion(itemIDs)
        }
        closeDissolvedGap(rowsBefore: rowsBefore, offsetBefore: offsetBefore)
    }

    /// Hands the part of `cell` within the messages' bounds to the dissolve view and hides the cell's content. Returns
    /// whether it did.
    private func dissolveVisiblePart(of cell: UICollectionViewCell) -> Bool {
        let visibleFrame = cell.frame.intersection(collectionView.bounds)
        guard !visibleFrame.isNull, visibleFrame.width >= 1, visibleFrame.height >= 1 else { return false }
        // Drawn from the layers rather than taken from the screen: the message menu that Regenerate is chosen from keeps
        // the pressed message off the screen until the frame after the menu has gone. The dust takes 8-bit sRGB.
        let image = cell.makeLayerImage(
            of: visibleFrame.offsetBy(dx: -cell.frame.minX, dy: -cell.frame.minY),
            scale: max(1, cell.traitCollection.displayScale),
            range: .standard
        )
        let dissolveView = messageDissolveView ?? makeMessageDissolveView()
        dissolveView.dissolve(image, at: collectionView.convert(visibleFrame, to: dissolveView))
        cell.contentView.isHidden = true
        return true
    }

    /// Moves the rows that stay from where they stood, `rowsBefore` on screen at `offsetBefore`, to where they are now,
    /// on Telegram's list curve. A row that has just come into view moves with the rest of the chat.
    private func closeDissolvedGap(rowsBefore: [ListItemID: CGFloat], offsetBefore: CGFloat) {
        collectionView.layoutIfNeeded()
        let offsetAfter = collectionView.contentOffset.y
        // Each change has its own key, so a gap closing on one that is still closing adds to it
        let key = Self.dissolvedGapAnimationKey + "." + UUID().uuidString
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell),
                  let listItemID = dataSource.itemIdentifier(for: indexPath) else { continue }
            let rowBefore = rowsBefore[listItemID] ?? cell.frame.minY - offsetBefore
            let rowAfter = cell.frame.minY - offsetAfter
            let shift = rowBefore - rowAfter
            guard abs(shift) > 0.5 else { continue }
            let animation = CABasicAnimation(keyPath: "position")
            animation.isAdditive = true
            animation.fromValue = NSValue(cgPoint: CGPoint(x: 0, y: shift))
            animation.toValue = NSValue(cgPoint: .zero)
            animation.duration = AgentVCLayout.dissolvedGapCloseDuration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            cell.layer.add(animation, forKey: key)
        }
    }

    private func makeMessageDissolveView() -> AgentMessageDissolveView {
        let dissolveView = AgentMessageDissolveView(frame: collectionView.frame)
        dissolveView.translatesAutoresizingMaskIntoConstraints = false
        dissolveView.onEmpty = { [weak self, weak dissolveView] in
            guard let self, let dissolveView, self.messageDissolveView === dissolveView else { return }
            self.removeMessageDissolveView()
        }
        // Over the messages, under the header, the composer and the scroll button
        view.insertSubview(dissolveView, aboveSubview: collectionView)
        NSLayoutConstraint.activate([
            dissolveView.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            dissolveView.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            dissolveView.topAnchor.constraint(equalTo: collectionView.topAnchor),
            dissolveView.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor),
        ])
        messageDissolveView = dissolveView
        return dissolveView
    }

    func removeMessageDissolveView() {
        messageDissolveView?.removeFromSuperview()
        messageDissolveView = nil
        dissolvingItemIDs.removeAll()
    }
}
