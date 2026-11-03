import UIKit
import UIComponents

/// Scrolls the chat to a row on the spring Telegram's list scrolls on (the critically damped one of
/// `makeSpringAnimation` from iOS 26: stiffness 555.027, damping 47.118), moving the offset frame by frame, so the list
/// lays out each row it passes and none go missing on the way.
///
/// A scroll longer than the list's height doesn't race through everything between. As Telegram's list keeps the item
/// nodes it had on screen next to the ones it scrolls to, the list jumps to its destination at once and the rows that
/// were on screen, drawn as they were, slide out while the destination slides in after them.
///
/// A scroll ends the user's own motion first, as Telegram's list stops its scroller before it scrolls to an item: a
/// fling's deceleration or a bounce stops where it is, and a finger still on the list lets go of it, so neither carries
/// the list on once the scroll lands.
@MainActor
final class AgentListScrollAnimator {
    static let spring = GlassSpring(dampingRatio: 1, response: 2 * .pi / 555.027.squareRoot())
    static let departingViewIdentifier = "agent_departing_rows"

    private enum Motion {
        /// The offset runs from `startOffsetY` to the target
        case scroll(startOffsetY: CGFloat, appliedOffsetY: CGFloat)
        /// The list already rests at the target and its rows come in over `distance`, after `departingView`
        case relay(departingView: UIView, distance: CGFloat)
    }

    private let collectionView: UICollectionView
    private lazy var clock = GlassMotionClock { [weak self] time in self?.step(at: time) }
    private var curve: GlassSpringCurve?
    private var motion: Motion?
    private var getTargetOffsetY: () -> CGFloat? = { nil }
    private var completion: ((Bool) -> Void)?

    init(collectionView: UICollectionView) {
        self.collectionView = collectionView
    }

    var isRunning: Bool { curve != nil }

    /// Scrolls to the offset `getTargetOffsetY` returns, asked again on every frame as the rows on the way settle their
    /// heights. After a long scroll's jump, `settleJump` lets the destination's rows settle before they slide in.
    /// `completion` gets whether the scroll reached its target rather than being stopped.
    func scroll(
        to getTargetOffsetY: @escaping () -> CGFloat?,
        settleJump: () -> Void = {},
        completion: @escaping (Bool) -> Void
    ) {
        if case .scroll? = motion {
            // A scroll under way keeps its pace toward the new target
            self.getTargetOffsetY = getTargetOffsetY
            let previousCompletion = self.completion
            self.completion = { isFinished in
                previousCompletion?(isFinished)
                completion(isFinished)
            }
            return
        }
        stop()
        stopUserScrolling()
        collectionView.layoutIfNeeded()
        guard let targetOffsetY = getTargetOffsetY() else {
            completion(false)
            return
        }
        let startOffsetY = collectionView.contentOffset.y
        let distance = targetOffsetY - startOffsetY
        guard abs(distance) > 0.5, !UIAccessibility.isReduceMotionEnabled else {
            setOffsetY(targetOffsetY)
            settleJump()
            completion(true)
            return
        }
        self.getTargetOffsetY = getTargetOffsetY
        self.completion = completion
        let height = collectionView.bounds.height
        if abs(distance) > height, let departingView = makeDepartingView() {
            setOffsetY(targetOffsetY)
            settleJump()
            motion = .relay(departingView: departingView, distance: distance > 0 ? height : -height)
        } else {
            motion = .scroll(startOffsetY: startOffsetY, appliedOffsetY: startOffsetY)
        }
        curve = GlassSpringCurve(startTime: CACurrentMediaTime(), from: 0, target: 1, spring: Self.spring)
        step(at: CACurrentMediaTime())
        clock.start()
    }

    /// Ends a scroll where it is, as when the user takes the list
    func stop() {
        finish(isFinished: false)
    }

    /// Stops the list's own deceleration and bounce where they are and lets go of a drag, as Telegram's `stopScrolling`
    /// and `cancelTracking` do
    private func stopUserScrolling() {
        if collectionView.isTracking || collectionView.isDragging {
            let pan = collectionView.panGestureRecognizer
            pan.isEnabled = false
            pan.isEnabled = true
        }
        if collectionView.isDecelerating || collectionView.isDragging || collectionView.isTracking {
            collectionView.setContentOffset(collectionView.contentOffset, animated: false)
        }
    }

    private func step(at time: CFTimeInterval) {
        guard let curve, let motion else { return }
        let progress = curve.getValue(at: time)
        switch motion {
        case .scroll(var startOffsetY, let appliedOffsetY):
            // Rows above that settle their heights move the offset; the scroll carries on from where they put it
            let drift = collectionView.contentOffset.y - appliedOffsetY
            if abs(drift) > 0.5 {
                startOffsetY += drift
            }
            let targetOffsetY = getTargetOffsetY() ?? collectionView.contentOffset.y
            setOffsetY(startOffsetY + (targetOffsetY - startOffsetY) * progress)
            self.motion = .scroll(startOffsetY: startOffsetY, appliedOffsetY: collectionView.contentOffset.y)
        case .relay(let departingView, let distance):
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            collectionView.layer.sublayerTransform = CATransform3DMakeTranslation(0, distance * (1 - progress), 0)
            departingView.transform = CGAffineTransform(translationX: 0, y: -distance * progress)
            CATransaction.commit()
        }
        if time >= curve.restTime {
            finish(isFinished: true)
        }
    }

    private func finish(isFinished: Bool) {
        guard curve != nil else { return }
        clock.stop()
        curve = nil
        switch motion {
        case .scroll:
            if isFinished, let targetOffsetY = getTargetOffsetY() {
                setOffsetY(targetOffsetY)
            }
        case .relay(let departingView, _):
            collectionView.layer.sublayerTransform = CATransform3DIdentity
            departingView.removeFromSuperview()
        case nil:
            break
        }
        motion = nil
        getTargetOffsetY = { nil }
        let completion = completion
        self.completion = nil
        completion?(isFinished)
    }

    private func setOffsetY(_ offsetY: CGFloat) {
        guard abs(collectionView.contentOffset.y - offsetY) > 0.01 else { return }
        UIView.performWithoutAnimation {
            collectionView.contentOffset.y = offsetY
        }
    }

    /// The rows on screen as they are drawn now, over the background, above the list and under everything over it
    private func makeDepartingView() -> UIView? {
        guard let superview = collectionView.superview,
              let snapshot = collectionView.snapshotView(afterScreenUpdates: false) else { return nil }
        let container = UIView(frame: collectionView.frame)
        container.backgroundColor = superview.backgroundColor
        container.isUserInteractionEnabled = false
        container.isAccessibilityElement = false
        container.accessibilityElementsHidden = true
        container.accessibilityIdentifier = Self.departingViewIdentifier
        snapshot.frame = container.bounds
        container.addSubview(snapshot)
        superview.insertSubview(container, aboveSubview: collectionView)
        return container
    }
}
