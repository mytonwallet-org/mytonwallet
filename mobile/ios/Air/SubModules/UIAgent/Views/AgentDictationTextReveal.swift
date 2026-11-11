import UIKit
import UIComponents

/// Brings a transcript into a text view character by character, after the text before it, as the Agent's answers come
/// in: each character comes out of a blur in the accent colour, transparent and blurred, sharp within
/// `sharpenDuration`, and then turns to the text colour. A transcript comes back whole, so its characters come
/// `characterStep` apart, closer for a long one so the last starts within `maxDuration`. The text grows character by
/// character, and the field with it.
@MainActor
final class AgentDictationTextReveal {
    static let characterStep: TimeInterval = 0.006
    static let maxDuration: TimeInterval = 0.8
    static let sharpenDuration: TimeInterval = 0.15
    static let colorDuration: TimeInterval = 0.5

    /// The time between the starts of two characters of a transcript of `characterCount` characters
    static func getCharacterStep(characterCount: Int) -> TimeInterval {
        guard characterCount > 1 else { return characterStep }
        return min(characterStep, maxDuration / Double(characterCount - 1))
    }

    private let textView: UITextView
    private let prefix: String
    private let text: String
    private let characterRanges: [NSRange]
    private let characterEnds: [String.Index]
    private let step: TimeInterval
    private let baseAttributes: [NSAttributedString.Key: Any]
    private let onTextGrown: () -> Void
    private let onFinished: () -> Void
    private var startTime: CFTimeInterval?
    private var shownCount = 0
    private var firstAnimatingIndex = 0
    /// The reveal is changing the view's text, which a caller watching the view's selection can tell from the user's
    private(set) var isEditingText = false
    private lazy var clock = GlassMotionClock(frameRateRange: nil) { [weak self] _ in self?.advance() }

    /// Starts showing `text` after `prefix` in `textView`, whose text becomes `prefix`. `onTextGrown` follows each
    /// frame text comes in, and `onFinished` the end, when the view holds the whole text as plain text again.
    init(
        text: String,
        after prefix: String = "",
        in textView: UITextView,
        onTextGrown: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.textView = textView
        self.prefix = prefix
        self.text = text
        let ranges = text.indices.map { $0..<text.index(after: $0) }
        let prefixLength = (prefix as NSString).length
        characterRanges = ranges.map {
            let range = NSRange($0, in: text)
            return NSRange(location: prefixLength + range.location, length: range.length)
        }
        characterEnds = ranges.map(\.upperBound)
        step = Self.getCharacterStep(characterCount: ranges.count)
        self.onTextGrown = onTextGrown
        self.onFinished = onFinished
        isEditingText = true
        textView.text = prefix
        isEditingText = false
        baseAttributes = textView.typingAttributes
    }

    func start() {
        startTime = CACurrentMediaTime()
        advance()
        if startTime != nil { clock.start() }
    }

    /// Stops the reveal where it is, leaving the view to whoever changes its text next
    func cancel() {
        startTime = nil
        clock.stop()
    }

    /// Ends the reveal with the whole text in, as plain text: every character in the text colour and sharp, and what is
    /// typed next too, wherever the caret went meanwhile
    func complete() {
        guard startTime != nil else { return }
        cancel()
        settleText()
    }

    private func settleText() {
        isEditingText = true
        textView.attributedText = NSAttributedString(string: prefix + text, attributes: baseAttributes)
        textView.typingAttributes = baseAttributes
        isEditingText = false
    }

    private func advance() {
        guard let startTime else { return }
        guard !characterRanges.isEmpty else {
            finish()
            return
        }
        let elapsed = CACurrentMediaTime() - startTime
        let storage = textView.textStorage
        let count = min(characterRanges.count, Int(elapsed / step) + 1)
        let hasGrown = count > shownCount
        isEditingText = true
        defer { isEditingText = false }
        storage.beginEditing()
        if hasGrown {
            let shownEnd = shownCount > 0 ? characterEnds[shownCount - 1] : text.startIndex
            let addition = String(text[shownEnd..<characterEnds[count - 1]])
            storage.append(NSAttributedString(string: addition, attributes: baseAttributes))
            shownCount = count
        }
        let accent = textView.tintColor ?? .systemBlue
        let textColor = (baseAttributes[.foregroundColor] as? UIColor) ?? .label
        let traits = textView.traitCollection
        // Neighbours at the same stage share their attributes, so a frame sets a few runs rather than every character
        var run: (stage: Stage, range: NSRange)?
        func applyRun() {
            guard let run else { return }
            let attributes = Self.getAttributes(of: run.stage, accent: accent, textColor: textColor, traits: traits)
            storage.addAttributes(attributes, range: run.range)
            if attributes[.shadow] == nil {
                storage.removeAttribute(.shadow, range: run.range)
            }
        }
        for index in firstAnimatingIndex..<shownCount {
            let age = elapsed - Double(index) * step
            if age >= Self.sharpenDuration + Self.colorDuration, index == firstAnimatingIndex {
                firstAnimatingIndex += 1
            }
            let stage = Self.getStage(age: age)
            let range = characterRanges[index]
            if let current = run, current.stage == stage {
                run = (stage, NSUnionRange(current.range, range))
            } else {
                applyRun()
                run = (stage, range)
            }
        }
        applyRun()
        storage.endEditing()
        if hasGrown {
            onTextGrown()
        }
        if firstAnimatingIndex >= characterRanges.count {
            finish()
        }
    }

    /// How far a character has come: how sharp it is, in twelfths, and how far it has turned to the text colour, in
    /// twentieths
    private struct Stage: Equatable {
        let sharpness: Int
        let toText: Int
    }

    private static func getStage(age: TimeInterval) -> Stage {
        let sharpness = min(1, max(0, age / sharpenDuration))
        let toText = min(1, max(0, (age - sharpenDuration) / colorDuration))
        return Stage(sharpness: Int((sharpness * 12).rounded()), toText: Int((toText * 20).rounded()))
    }

    /// A character at `stage`: transparent and blurred in the accent colour while it sharpens, then turning to the
    /// text colour
    private static func getAttributes(
        of stage: Stage,
        accent: UIColor,
        textColor: UIColor,
        traits: UITraitCollection
    ) -> [NSAttributedString.Key: Any] {
        let sharpness = CGFloat(stage.sharpness) / 12
        let toText = CGFloat(stage.toText) / 20
        let color = blend(accent.resolvedColor(with: traits), textColor.resolvedColor(with: traits), toText)
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color.withAlphaComponent(color.cgColor.alpha * (0.15 + 0.85 * sharpness))
        ]
        if sharpness < 1 {
            let shadow = NSShadow()
            shadow.shadowColor = accent.withAlphaComponent(0.9 * (1 - sharpness))
            shadow.shadowBlurRadius = 6 * (1 - sharpness)
            shadow.shadowOffset = .zero
            attributes[.shadow] = shadow
        }
        return attributes
    }

    private static func blend(_ from: UIColor, _ to: UIColor, _ progress: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * progress,
            green: g1 + (g2 - g1) * progress,
            blue: b1 + (b2 - b1) * progress,
            alpha: a1 + (a2 - a1) * progress
        )
    }

    private func finish() {
        guard startTime != nil else { return }
        cancel()
        settleText()
        onFinished()
    }
}
