
import UIKit
import WalletCore
import WalletContext


public final class ActivitiesTableView: UITableView, UIGestureRecognizerDelegate {

    var animatingRowsInsertion: Set<IndexPath> = []
    var animatingRowsDeletion: Set<IndexPath> = []
    var deleteSnapshot: UIView?

    public override init(frame: CGRect, style: UITableView.Style) {
        super.init(frame: frame, style: style)
        delaysContentTouches = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        if hitView == nil && self.point(inside: point, with: event) {
            return self
        }
        return hitView
    }

    @objc func _parentScrollView() -> UIScrollView? {
        return nil
    }

    public override func reconfigureRows(at indexPaths: [IndexPath]) {
        super.reconfigureRows(at: indexPaths)
    }

    public override func insertRows(at indexPaths: [IndexPath], with animation: UITableView.RowAnimation) {
        super.insertRows(at: indexPaths, with: .fade)
//        self.animatingRowsInsertion = Set(indexPaths)
    }

    public override func insertSections(_ sections: IndexSet, with animation: UITableView.RowAnimation) {
        super.insertSections(sections, with: .fade)
//        super.insertSections(sections, with: sections.contains(1) && sections.count >= 3 ? .fade : animation)
    }

    public override func deleteRows(at indexPaths: [IndexPath], with animation: UITableView.RowAnimation) {
        super.deleteRows(at: indexPaths, with: .fade)
        //        if indexPaths.count == 1, let idx = indexPaths.first, idx.section == 1, let cell = cellForRow(at: idx) {
//            if let snapshot = cell.snapshotView(afterScreenUpdates: false), let sv = cell.superview {
//                sv.addSubview(snapshot)
//                snapshot.frame = cell.frame
//                snapshot.layer.cornerRadius = cell.layer.cornerRadius
//                snapshot.layer.maskedCorners = cell.layer.maskedCorners
//                self.deleteSnapshot = snapshot
//                UIView.animate(withDuration: 0.2) {
//                    snapshot.alpha = 0
//                } completion: { _ in
//                    snapshot.removeFromSuperview()
//                    if self.deleteSnapshot === snapshot {
//                        self.deleteSnapshot = nil
//                    }
//                }
//            }
//            self.animatingRowsDeletion = Set(indexPaths)
//            super.deleteRows(at: indexPaths, with: .none)
//        } else {
//            super.deleteRows(at: indexPaths, with: .fade)
//        }
    }

    public override func deleteSections(_ sections: IndexSet, with animation: UITableView.RowAnimation) {
        super.deleteSections(sections, with: .fade)
    }

    public override func reloadRows(at indexPaths: [IndexPath], with animation: UITableView.RowAnimation) {
        super.reloadRows(at: indexPaths, with: animation)
    }

    public override func reloadSections(_ sections: IndexSet, with animation: UITableView.RowAnimation) {
        super.reloadSections(sections, with: animation)
    }
}
