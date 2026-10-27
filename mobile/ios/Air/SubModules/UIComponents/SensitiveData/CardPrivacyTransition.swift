import UIKit

/// A radial wipe on the live content, synchronized with the dust wave. No text
/// snapshots are retained; interruption/backgrounding immediately settles state.
@MainActor
final class CardPrivacyTransition {
    private weak var view: UIView?
    private var concealed: Bool?
    private var generation = 0
    private var mask: CAShapeLayer?
    var nextOrigin: CGPoint?
    var active = false { didSet { if !active { settle() } } }
    private(set) var lastOrigin = CGPoint.zero
    var isAnimating: Bool { mask != nil }

    func setConcealed(_ hidden: Bool, in target: UIView, animated: Bool) {
        guard concealed != hidden || view !== target else { return }
        generation += 1
        let token = generation
        mask?.removeAllAnimations(); mask = nil
        view?.layer.mask = nil
        view = target; concealed = hidden
        let origin = nextOrigin ?? CGPoint(x: target.bounds.midX, y: target.bounds.midY)
        nextOrigin = nil; lastOrigin = origin
        guard animated, active, target.window != nil, !target.bounds.isEmpty,
              !UIAccessibility.isReduceMotionEnabled else {
            target.isHidden = hidden
            return
        }
        let rect = target.bounds.insetBy(dx: -2, dy: -2)
        let radius = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                      CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
            .map { hypot($0.x - origin.x, $0.y - origin.y) }.max()! + 2
        func path(radius: CGFloat) -> CGPath {
            let path = CGMutablePath()
            if hidden { path.addRect(rect) }
            path.addEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
            return path
        }
        let mask = CAShapeLayer()
        mask.frame = target.bounds
        mask.fillColor = UIColor.black.cgColor; mask.fillRule = .evenOdd
        let start = path(radius: 0.01), end = path(radius: radius)
        mask.path = end
        target.layer.mask = mask; target.isHidden = false
        self.mask = mask
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak target] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                target?.isHidden = hidden; target?.layer.mask = nil; self.mask = nil
            }
        }
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = start; animation.toValue = end
        animation.duration = 0.55
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        mask.add(animation, forKey: "privacyWave")
        CATransaction.commit()
    }
    func reset() {
        settle(); concealed = nil; view = nil; nextOrigin = nil
    }
    private func settle() {
        generation += 1
        mask?.removeAllAnimations(); mask = nil
        view?.isHidden = concealed ?? true
        view?.layer.mask = nil
    }
}
