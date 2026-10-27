import UIKit

/// Blocks scrolling gestures without changing automatic safe-area insets.
@MainActor
final class CardScrollLock {
    private struct Entry {
        weak var pan: UIPanGestureRecognizer?
        let wasEnabled: Bool
    }
    private var entries: [Entry] = []
    private(set) var isLocked = false
    func lock(above view: UIView) {
        guard !isLocked else { return }
        isLocked = true
        var ancestor = view.superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                let pan = scroll.panGestureRecognizer
                entries.append(Entry(pan: pan, wasEnabled: pan.isEnabled))
                // Disabling the scroll view itself removes its automatic insets,
                // which moves the home header and the card under the finger.
                pan.isEnabled = false
            }
            ancestor = current.superview
        }
    }
    func unlock() {
        guard isLocked else { return }
        isLocked = false
        let saved = entries
        entries.removeAll()
        for entry in saved { entry.pan?.isEnabled = entry.wasEnabled }
    }
}
