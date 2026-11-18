import UIKit

private let hiddenOffset: CGFloat = -12
private let appearingScale: CGFloat = 0.8

/// Swaps a title in two steps: the old content rises as it fades out, then the new content grows into place as it fades in
@MainActor
public enum TitleReplaceMotion {

    @discardableResult
    public static func hide(_ view: UIView, duration: TimeInterval, completion: @escaping () -> Void) -> UIViewPropertyAnimator {
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: duration, delay: 0, options: [.beginFromCurrentState], animations: {
            view.alpha = 0
            view.transform = CGAffineTransform(translationX: 0, y: hiddenOffset)
        }, completion: { _ in
            completion()
        })
    }

    public static func show(_ view: UIView, duration: TimeInterval, alongside: (() -> Void)? = nil) {
        view.transform = CGAffineTransform(scaleX: appearingScale, y: appearingScale)
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: duration, delay: 0, options: [], animations: {
            view.alpha = 1
            view.transform = .identity
            alongside?()
        })
    }
}
