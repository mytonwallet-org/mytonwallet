import UIKit
import WalletContext

public final class ActivitiesCollectionView: UICollectionView, UIGestureRecognizerDelegate {

    public var tracesHomeUpdates = false
    private var traceGesture = 0
    private var traceCounts: [String: Int] = [:]
    private var traceCauses = Set<UInt64>()
    private var traceWindowStart = HomeTrace.isEnabled ? HomeTrace.now : 0
    private var traceMaximumLayoutMS: Double = 0

    @discardableResult
    public func traceHome(_ event: String, _ details: @autoclosure () -> String = "") -> UInt64? {
        guard tracesHomeUpdates, HomeTrace.isEnabled else { return nil }
        let motion = isDragging ? "dragging" : isDecelerating ? "decelerating" : isTracking ? "tracking" : "idle"
        return HomeTrace.record(event, "cv=\(ObjectIdentifier(self)) gesture=\(traceGesture) motion=\(motion) visible=\(window != nil) y=\(contentOffset.y) contentH=\(contentSize.height) inset=\(contentInset.top),\(contentInset.bottom) adjustedTop=\(adjustedContentInset.top) \(details())")
    }

    public func countHomeWork(_ name: @autoclosure () -> String) {
        guard tracesHomeUpdates, HomeTrace.isEnabled else { return }
        traceCounts[name(), default: 0] += 1
        if let cause = HomeTrace.cause { traceCauses.insert(cause) }
    }

    public func traceHomeGestureBegan() {
        guard tracesHomeUpdates, HomeTrace.isEnabled else { return }
        flushHomeTrace(reason: "before-drag", force: true)
        traceGesture += 1
        traceHome("scroll.begin")
    }

    public func flushHomeTrace(reason: String, force: Bool = false) {
        guard tracesHomeUpdates, HomeTrace.isEnabled, !traceCounts.isEmpty else { return }
        let now = HomeTrace.now
        guard force || now - traceWindowStart >= 0.25 else { return }
        let counts = traceCounts.sorted { $0.key < $1.key }.map { entry -> String in
            "\(entry.key)=\(entry.value)"
        }.joined(separator: " ")
        let causes = traceCauses.sorted().map(String.init).joined(separator: ",")
        traceHome("layout.window", "reason=\(reason) window_ms=\(HomeTrace.milliseconds(since: traceWindowStart)) maxLayout_ms=\(String(format: "%.2f", traceMaximumLayoutMS)) causes=[\(causes)] \(counts)")
        traceCounts.removeAll(keepingCapacity: true)
        traceCauses.removeAll(keepingCapacity: true)
        traceMaximumLayoutMS = 0
        traceWindowStart = now
    }

    public override func layoutSubviews() {
        guard tracesHomeUpdates, HomeTrace.isEnabled else {
            super.layoutSubviews()
            return
        }
        let start = HomeTrace.now
        countHomeWork("collectionLayout")
        super.layoutSubviews()
        traceMaximumLayoutMS = max(traceMaximumLayoutMS, (HomeTrace.now - start) * 1_000)
        flushHomeTrace(reason: "layout")
    }

    public override var contentSize: CGSize {
        didSet {
            if oldValue != contentSize {
                traceHome("geometry.contentSize", "old=\(oldValue.width)x\(oldValue.height) new=\(contentSize.width)x\(contentSize.height)")
            }
        }
    }

    public override var contentInset: UIEdgeInsets {
        didSet {
            if oldValue != contentInset {
                traceHome("geometry.contentInset", "oldTop=\(oldValue.top) oldBottom=\(oldValue.bottom)")
            }
        }
    }

    public override func reloadData() {
        traceHome("collection.reloadData")
        countHomeWork("reloadData")
        super.reloadData()
    }

    public override func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
        countHomeWork("batchUpdates")
        super.performBatchUpdates(updates, completion: completion)
    }

    public override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
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
}
