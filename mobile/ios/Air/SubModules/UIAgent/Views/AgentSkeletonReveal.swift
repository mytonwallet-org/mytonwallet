import UIKit
import UIComponents
import WalletContext

/// Both layouts keep bubbles in visual order. A shared interpolation moves the whole column without intersections.
@MainActor
enum AgentSkeletonReveal {
    enum Row {
        case line
        case bubble(isOutgoing: Bool)
    }

    static let duration: CFTimeInterval = 0.36

    static func revealRows(
        in collectionView: UICollectionView,
        isRightToLeft: Bool,
        placeholders: [AgentMessagesSkeletonView.Placeholder] = [],
        row: (UICollectionViewCell, IndexPath) -> Row?
    ) {
        collectionView.layoutIfNeeded()
        let curve = AgentComposerMetrics.makeTelegramCurve()
        let now = CACurrentMediaTime()
        var remaining = placeholders.sorted { $0.frame.minY > $1.frame.minY }
        var sourceTop = collectionView.bounds.maxY - collectionView.adjustedContentInset.bottom
        var targetTop = collectionView.bounds.minY
        for cell in collectionView.visibleCells.sorted(by: { $0.frame.maxY > $1.frame.maxY }) {
            guard let indexPath = collectionView.indexPath(for: cell), let kind = row(cell, indexPath) else { continue }
            switch kind {
            case .line:
                fadeContents(of: cell, now: now, delay: duration)
            case .bubble(let isOutgoing):
                let targetView = (cell as? AgentMessageCell)?.skeletonRevealView
                    ?? (cell as? AgentNewsPostCell)?.newsView.bubbleView
                    ?? (cell as? AgentNewsFeedCardCell)?.newsView.bubbleView
                    ?? (cell as? AgentNewsDigestCardCell)?.bubbleView
                    ?? cell.contentView
                let target = targetView.convert(targetView.bounds, to: collectionView)
                guard target.width > 0, target.height > 0 else { continue }
                let source: CGRect
                if !remaining.isEmpty {
                    // Two consecutive answers must not exchange places to match the placeholder's sender.
                    source = collectionView.convert(remaining.removeFirst().frame, from: nil)
                } else {
                    let width = min(target.width, collectionView.bounds.width * 0.86)
                    source = CGRect(
                        x: isOutgoing != isRightToLeft ? collectionView.bounds.maxX - 16 - width : 16,
                        y: sourceTop - 184, width: width, height: 184
                    )
                }
                sourceTop = source.minY - AgentVCLayout.rowSpacing
                targetTop = min(targetTop, target.minY)
                let transform = CABasicAnimation(keyPath: "transform")
                transform.fromValue = CATransform3DConcat(
                    CATransform3DMakeScale(source.width / target.width, source.height / target.height, 1),
                    CATransform3DMakeTranslation(source.midX - target.midX, source.midY - target.midY, 0)
                )
                transform.toValue = CATransform3DIdentity
                transform.beginTime = targetView.layer.convertTime(now, from: nil)
                transform.duration = duration
                transform.timingFunction = curve
                targetView.layer.add(transform, forKey: "agentSkeletonReveal.geometry")
                if let bubble = targetView as? AgentBubbleBackgroundView {
                    bubble.revealFill(from: .air.agentBubbleFill, duration: duration)
                    fadeContents(of: bubble.contentView, now: now)
                } else {
                    for child in targetView.subviews { fadeContents(of: child, now: now) }
                }
                fadeOutsideBubble(in: cell.contentView, bubble: targetView, now: now)
            }
        }

        // Surplus loading rows move out above the real column, instead of lying beneath growing answers.
        for placeholder in remaining {
            let source = collectionView.convert(placeholder.frame, from: nil)
            let target = CGRect(x: source.minX, y: targetTop - AgentVCLayout.rowSpacing - source.height,
                                width: source.width, height: source.height)
            targetTop = target.minY
            let bubble = AgentBubbleBackgroundView()
            bubble.translatesAutoresizingMaskIntoConstraints = true
            bubble.isUserInteractionEnabled = false
            bubble.configure(direction: placeholder.isOutgoing ? .outgoing : .incoming,
                             fillColor: .air.agentBubbleFill, showsTail: true)
            bubble.frame = target
            collectionView.addSubview(bubble)
            bubble.layoutIfNeeded()
            bubble.layer.opacity = 0
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(cgPoint: CGPoint(x: source.midX, y: source.midY))
            move.toValue = NSValue(cgPoint: CGPoint(x: target.midX, y: target.midY))
            move.beginTime = bubble.layer.convertTime(now, from: nil)
            move.duration = duration
            move.timingFunction = curve
            bubble.layer.add(move, forKey: "agentSkeletonReveal.surplus")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.beginTime = move.beginTime
            fade.duration = duration
            bubble.layer.add(fade, forKey: "agentSkeletonReveal.opacity")
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak bubble] in
                bubble?.removeFromSuperview()
            }
        }
    }

    private static func fadeOutsideBubble(in view: UIView, bubble: UIView, now: CFTimeInterval) {
        for child in view.subviews where child !== bubble {
            if bubble.isDescendant(of: child) {
                fadeOutsideBubble(in: child, bubble: bubble, now: now)
            } else if let followups = child as? AgentFollowupView {
                followups.animateAppearance(delay: duration)
            } else {
                // Dates and follow-ups are outside the moving surfaces; they appear once the column settles.
                fadeContents(of: child, now: now, delay: duration)
            }
        }
    }

    private static func fadeContents(of view: UIView, now: CFTimeInterval, delay: CFTimeInterval = 0.14) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = view.layer.opacity
        fade.beginTime = view.layer.convertTime(now, from: nil) + delay
        fade.duration = 0.22
        fade.fillMode = .backwards
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer.add(fade, forKey: "agentSkeletonReveal.contents")
    }
}
