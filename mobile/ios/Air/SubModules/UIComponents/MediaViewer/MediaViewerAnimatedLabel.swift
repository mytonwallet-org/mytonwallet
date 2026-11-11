import UIKit
import WalletContext

/// One centred line of text that animates only what changes, as Telegram's animated text does: the characters the old
/// and the new text share at their start and end stay and slide to their new places, and the ones between roll out and
/// in, upward as the pictures go forward and downward as they go back. With Reduce Motion they cross-fade in place.
@MainActor
final class MediaViewerAnimatedLabel: UIView {
    enum Direction {
        case forward
        case backward
    }

    /// The part of the new text that differs from the old one, with what it replaces
    struct Change: Equatable {
        let prefix: String
        let removed: String
        let inserted: String
        let suffix: String
    }

    static let duration: TimeInterval = 0.3
    /// How far a changing part rolls, in heights of its line
    static let rollDistance: CGFloat = 0.6

    var font: UIFont = .systemFont(ofSize: 17) {
        didSet { resetRuns() }
    }
    var textColor: UIColor = .white {
        didSet { runLabels.forEach { $0.textColor = textColor } }
    }
    private(set) var text: String?
    /// The text's parts in reading order, which together show `text`
    private(set) var runLabels: [UILabel] = []
    /// Old parts rolling out
    private var leavingLabels: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The parts the texts share at their start and their end, which never overlap, and what changes between them
    static func getChange(from oldText: String, to newText: String) -> Change {
        let old = Array(oldText)
        let new = Array(newText)
        let maxShared = min(old.count, new.count)
        var prefixCount = 0
        while prefixCount < maxShared, old[prefixCount] == new[prefixCount] {
            prefixCount += 1
        }
        var suffixCount = 0
        while suffixCount < maxShared - prefixCount, old[old.count - 1 - suffixCount] == new[new.count - 1 - suffixCount] {
            suffixCount += 1
        }
        return Change(
            prefix: String(new[..<prefixCount]),
            removed: String(old[prefixCount..<(old.count - suffixCount)]),
            inserted: String(new[prefixCount..<(new.count - suffixCount)]),
            suffix: String(new[(new.count - suffixCount)...])
        )
    }

    func setText(_ newText: String?, direction: Direction, animated: Bool) {
        let newText = newText?.nilIfEmpty
        guard newText != text else { return }
        let oldText = text
        text = newText
        finishAnimations()
        guard animated, let oldText, let newText, window != nil, bounds.width > 0,
              measureWidth(of: oldText) <= bounds.width, measureWidth(of: newText) <= bounds.width else {
            resetRuns()
            return
        }
        animateChange(Self.getChange(from: oldText, to: newText), direction: direction)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let text else { return .zero }
        return CGSize(width: min(size.width, measureWidth(of: text).rounded(.up)), height: font.lineHeight.rounded(.up))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (label, frame) in zip(runLabels, getFrames(of: runLabels.map { $0.text ?? "" })) {
            label.frame = frame
        }
    }

    private func animateChange(_ change: Change, direction: Direction) {
        let oldRuns = [change.prefix, change.removed, change.suffix]
        let newRuns = [change.prefix, change.inserted, change.suffix]
        let oldFrames = getFrames(of: oldRuns)
        let newFrames = getFrames(of: newRuns)
        runLabels.forEach { $0.removeFromSuperview() }
        runLabels = newRuns.map(makeLabel)
        let leaving = makeLabel(change.removed)
        leavingLabels = [leaving]

        let isReduced = UIAccessibility.isReduceMotionEnabled
        let roll = isReduced ? 0 : font.lineHeight * Self.rollDistance * (direction == .forward ? 1 : -1)
        leaving.frame = oldFrames[1]
        runLabels[0].frame = oldFrames[0]
        runLabels[2].frame = oldFrames[2]
        runLabels[1].frame = newFrames[1].offsetBy(dx: 0, dy: roll)
        runLabels[1].alpha = 0

        let update = {
            leaving.frame = oldFrames[1].offsetBy(dx: 0, dy: -roll)
            leaving.alpha = 0
            for (label, frame) in zip(self.runLabels, newFrames) {
                label.frame = frame
                label.alpha = 1
            }
        }
        let completion = { (_: Bool) in
            leaving.removeFromSuperview()
            self.leavingLabels.removeAll { $0 === leaving }
        }
        if isReduced {
            UIView.animate(withDuration: Self.duration, delay: 0, options: [.curveEaseInOut], animations: update, completion: completion)
        } else {
            UIView.animate(
                withDuration: Self.duration,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: [],
                animations: update,
                completion: completion
            )
        }
    }

    /// Ends the parts' motion where it was going, so a new change starts from the text it shows
    private func finishAnimations() {
        leavingLabels.forEach { $0.removeFromSuperview() }
        leavingLabels.removeAll()
        for label in runLabels {
            label.layer.removeAllAnimations()
            label.alpha = 1
        }
    }

    private func resetRuns() {
        finishAnimations()
        runLabels.forEach { $0.removeFromSuperview() }
        runLabels = text.map { [makeLabel($0)] } ?? []
        setNeedsLayout()
    }

    private func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = font
        label.textColor = textColor
        label.text = text
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        return label
    }

    private func measureWidth(of text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// The frames of `runs` laid side by side, centred as a whole, from the trailing side in a right-to-left layout. A
    /// lone run wider than the line truncates.
    private func getFrames(of runs: [String]) -> [CGRect] {
        let widths = runs.map { $0.isEmpty ? 0 : measureWidth(of: $0) }
        let total = widths.reduce(0, +)
        let height = font.lineHeight.rounded(.up)
        let y = ((bounds.height - height) / 2).rounded(.down)
        let scale = max(1, traitCollection.displayScale)
        var x = max(0, ((bounds.width - total) / 2 * scale).rounded() / scale)
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        var frames: [CGRect] = []
        for width in isRightToLeft ? widths.reversed() : widths {
            frames.append(CGRect(x: x, y: y, width: min(width.rounded(.up), bounds.width), height: height))
            x += width
        }
        return isRightToLeft ? frames.reversed() : frames
    }
}
