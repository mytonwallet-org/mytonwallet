
import UIKit
import WalletContext

public final class ActivitiesTableView: UITableView, UIGestureRecognizerDelegate {

    private var isDeletingFirstRow = false
    
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

    public override func endUpdates() {
        super.endUpdates()
    }

    public override func reconfigureRows(at indexPaths: [IndexPath]) {
        super.reconfigureRows(at: indexPaths)
    }

    public override func insertRows(at indexPaths: [IndexPath], with animation: UITableView.RowAnimation) {
        super.insertRows(at: indexPaths, with: isDeletingFirstRow ? .none : .fade)
        isDeletingFirstRow = false
    }

    public override func insertSections(_ sections: IndexSet, with animation: UITableView.RowAnimation) {
        super.insertSections(sections, with: .fade)
    }

    public override func deleteRows(at indexPaths: [IndexPath], with animation: UITableView.RowAnimation) {
        isDeletingFirstRow = indexPaths.count == 1 && indexPaths[0].row == 0
        super.deleteRows(at: indexPaths, with: isDeletingFirstRow ? .none : .fade)
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
