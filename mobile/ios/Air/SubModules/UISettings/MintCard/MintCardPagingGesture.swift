import UIKit

final class MintCardPagingGesture: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    var canSelect: () -> Bool = { true }
    var onSelect: (Int) -> Void = { _ in }

    init() {
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(handlePan))
        delegate = self
        maximumNumberOfTouches = 1
        cancelsTouchesInView = true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let velocity = velocity(in: view)
        return canSelect() && abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let view, let scrollView = otherGestureRecognizer.view as? UIScrollView,
              scrollView.isDescendant(of: view) else { return false }
        return otherGestureRecognizer === scrollView.panGestureRecognizer
    }

    static func selectionOffset(translation: CGFloat, velocity: CGFloat, width: CGFloat, isRTL: Bool) -> Int {
        guard width > 0 else { return 0 }
        let projected = (translation + velocity * 0.15) / width
        guard abs(projected) >= 0.18 else { return 0 }
        return (projected < 0 ? 1 : -1) * (isRTL ? -1 : 1)
    }

    @objc private func handlePan() {
        // Drag updates deliberately do no rendering or layout work.
        guard state == .ended, canSelect(), let view else { return }
        let offset = Self.selectionOffset(
            translation: translation(in: view).x, velocity: velocity(in: view).x,
            width: view.bounds.width, isRTL: view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        if offset != 0 { onSelect(offset) }
    }
}
