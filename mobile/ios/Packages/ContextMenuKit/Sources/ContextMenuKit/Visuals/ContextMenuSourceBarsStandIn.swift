import UIKit

/// A copy of a context menu's source that shows only the source's parts outside the screen's content area, where the
/// header and the bottom bar blur them. It keeps the bars' backdrop while the source is hidden, and moves with the
/// source's replica, so the bars never show the source where the replica has left it. Like the replica, it is a portal
/// of the source, so at every moment it shows the source as the replica does, the press's squeeze letting go included.
final class ContextMenuSourceBarsStandIn: UIView {
    private let portalView: ContextMenuPortalView

    /// Mirrors `source` as the replica made with the same arguments does, while leaving the source's hiding to the
    /// replica
    init?(
        source: UIView,
        sourceUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection,
        appliesRightToLeftTransformCorrection: Bool
    ) {
        guard let portalView = ContextMenuPortalView(
            sourceView: source,
            sourceUserInterfaceLayoutDirection: sourceUserInterfaceLayoutDirection,
            appliesRightToLeftTransformCorrection: appliesRightToLeftTransformCorrection
        ) else {
            return nil
        }
        portalView.detachFromSourcePosition()
        self.portalView = portalView
        super.init(frame: .zero)
        self.isUserInteractionEnabled = false
        self.accessibilityElementsHidden = true
        self.addSubview(portalView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Stands over `source` in its superview and leaves `contentArea`, in that superview's coordinates, clear. Outside
    /// that area it shows all that the source draws, beyond the source's bounds as within them.
    func show(over source: UIView, clearOf contentArea: CGRect) {
        guard let superview = source.superview else {
            return
        }
        superview.insertSubview(self, aboveSubview: source)
        self.transform = .identity
        // The source's frame, as the replica takes it, with the source's transform left to the portal
        self.frame = superview.convert(source.bounds, from: source)
        self.portalView.frame = self.bounds

        let clearArea = self.convert(contentArea, from: superview)
        let screen = superview.window.map { self.convert($0.bounds, from: $0) } ?? self.bounds
        let path = UIBezierPath(rect: screen.union(self.bounds).union(clearArea))
        path.append(UIBezierPath(rect: clearArea))
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        mask.fillRule = .evenOdd
        self.layer.mask = mask
    }

    /// Moves the copy as the replica moves, from `startOffset` to `endOffset` away from the source in the window's
    /// vertical coordinates. `addMotion` adds the replica's own animation of an additive vertical offset to a layer.
    func followReplica(
        from startOffset: CGFloat,
        to endOffset: CGFloat,
        addMotion: (_ layer: CALayer, _ from: CGFloat, _ to: CGFloat) -> Void
    ) {
        let portalLayer = self.portalView.layer
        for key in portalLayer.animationKeys() ?? []
        where (portalLayer.animation(forKey: key) as? CAPropertyAnimation)?.keyPath == "position.y" {
            portalLayer.removeAnimation(forKey: key)
        }
        let start = self.getLocalOffset(fromWindowOffset: startOffset)
        let end = self.getLocalOffset(fromWindowOffset: endOffset)
        self.portalView.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY + end)
        addMotion(portalLayer, start - end, 0.0)
    }

    /// A vertical offset in the window, as this view's own coordinates measure it
    private func getLocalOffset(fromWindowOffset offset: CGFloat) -> CGFloat {
        self.convert(CGPoint(x: 0.0, y: offset), from: nil).y - self.convert(CGPoint.zero, from: nil).y
    }
}
