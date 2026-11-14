import UIKit
import UIComponents

/// What a question being sent came from, for its bubble to grow out of: its text in the field, or the suggestion
/// tapped, where it stood in the view that holds the morph: the chat's, or the window for a question the chat list
/// sends to a new chat
struct AgentSentMessageSource {
    enum Kind {
        /// A picture of the question's text in the field, which lines up with the bubble's text
        case text(UIView)
        /// The question's text in the chat list's field, drawn from its layers, and the text's font size, for the new
        /// chat's first bubble to grow out of as the chat comes in
        case textPicture(UIImage, fontSize: CGFloat)
        /// The suggestion tapped: a picture of its title, where the title stood, and the title's font size
        case suggestion(title: UIImage, titleFrame: CGRect, titleFontSize: CGFloat)
    }

    let kind: Kind
    let frame: CGRect
    let time: CFTimeInterval

    /// A source older than this is not the sent question's any more
    static let lifetime: CFTimeInterval = 1
    /// A new chat's question may wait a moment longer for its chat to show it
    static let openingLifetime: CFTimeInterval = 3

    /// A picture of `view`'s `rect`, as it shows now, and its frame in `container`
    @MainActor
    static func makeText(of view: UIView, rect: CGRect, in container: UIView) -> AgentSentMessageSource? {
        guard view.window != nil, rect.width >= 1, rect.height >= 1, !UIAccessibility.isReduceMotionEnabled,
              let picture = view.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) else {
            return nil
        }
        return AgentSentMessageSource(kind: .text(picture), frame: view.convert(rect, to: container), time: CACurrentMediaTime())
    }

    /// `textView`'s `rect` drawn from its layers, so text set a moment ago and not yet on screen shows in it, and its
    /// frame in `container`
    @MainActor
    static func makeTextPicture(of textView: UITextView, rect: CGRect, in container: UIView) -> AgentSentMessageSource? {
        guard textView.window != nil, rect.width >= 1, rect.height >= 1, !UIAccessibility.isReduceMotionEnabled else {
            return nil
        }
        let fontSize = textView.font?.pointSize ?? UIFont.preferredFont(forTextStyle: .body).pointSize
        return AgentSentMessageSource(
            kind: .textPicture(textView.makeLayerImage(of: rect), fontSize: fontSize),
            frame: textView.convert(rect, to: container),
            time: CACurrentMediaTime()
        )
    }

    /// The suggestion `button` as it stands in `container`, its title drawn without a transition it may be in
    @MainActor
    static func makeSuggestion(of button: AgentSuggestionButton, in container: UIView) -> AgentSentMessageSource? {
        guard button.window != nil, !button.bounds.isEmpty, !UIAccessibility.isReduceMotionEnabled,
              let title = button.makeTitlePicture(in: container) else { return nil }
        return AgentSentMessageSource(
            kind: .suggestion(title: title.image, titleFrame: title.frame, titleFontSize: AgentSuggestionButton.titleFont.pointSize),
            frame: button.convert(button.bounds, to: container),
            time: CACurrentMediaTime()
        )
    }
}

/// Telegram iOS's send transition, after its `ChatMessageTransitionNode`: the sent question's bubble comes out of the
/// field. The text moves from the field into the bubble, which grows around it, and the text's picture flies with the
/// bubble and fades into it on Telegram's 0.4 s curve.
@MainActor
enum AgentSentMessageMorph {
    static let duration: TimeInterval = 0.4
    /// A question of more lines in its bubble is sent without the flight, its bubble showing in its place, as Telegram
    /// Android leaves a longer message, and as Android and the web do here
    static let maxLineCount = 10

    /// Whether `text` flies out of the field into its bubble in a chat `chatWidth` wide
    static func canFly(_ text: String?, chatWidth: CGFloat) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return AgentMessageCell.countQuestionLines(text, chatWidth: chatWidth) <= maxLineCount
    }
    /// How much smaller the bubble starts around the text, as it grows around it
    private static let textBubbleStartScale: CGFloat = 0.85

    /// Morphs `bubble`, the sent question's appearance view, from `picture`, the field's text at `sourceFrame` in
    /// `container`. `target` is the bubble's text, which the picture lines up with, also as the list moves the bubble
    /// during the flight, as it does going down with the keyboard.
    static func animate(_ bubble: UIView, target: UIView, from picture: UIView, at sourceFrame: CGRect, in container: UIView) {
        let source = (picture: picture, frame: sourceFrame)
        let targetFrame = target.convert(target.bounds, to: container)
        guard targetFrame.width > 0, targetFrame.height > 0, let bubbleSuperview = bubble.superview else { return }
        let scale = min(1.25, max(0.75, source.frame.height / targetFrame.height)) * textBubbleStartScale
        // The transform takes the bubble about its own centre; the target's centre lands on the source's
        let bubbleCenter = bubbleSuperview.convert(bubble.center, to: container)
        let targetOffset = CGPoint(x: targetFrame.midX - bubbleCenter.x, y: targetFrame.midY - bubbleCenter.y)
        let start = CGAffineTransform(
            translationX: source.frame.midX - bubbleCenter.x - targetOffset.x * scale,
            y: source.frame.midY - bubbleCenter.y - targetOffset.y * scale
        ).scaledBy(x: scale, y: scale)

        let picture = source.picture
        picture.frame = source.frame
        picture.isUserInteractionEnabled = false
        container.addSubview(picture)
        // The picture goes along with the bubble, from where it stood to where the bubble's text lands
        let pictureEnd = CGAffineTransform(
            translationX: targetFrame.midX - source.frame.midX,
            y: targetFrame.midY - source.frame.midY
        ).scaledBy(x: targetFrame.height / source.frame.height, y: targetFrame.height / source.frame.height)

        bubble.transform = start
        bubble.alpha = 0
        let move = UIViewPropertyAnimator(duration: duration, timingParameters: AgentComposerMetrics.makeTelegramCubicTiming())
        move.addAnimations {
            bubble.transform = .identity
            picture.transform = pictureEnd
        }
        move.addCompletion { _ in
            bubble.transform = .identity
            bubble.alpha = 1
            picture.removeFromSuperview()
        }
        move.startAnimation()
        follow(bubbleSuperview, with: picture, in: container)
        // The bubble shows as the picture goes, crossing over in the first half of the flight
        UIView.animate(withDuration: duration * 0.5, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            bubble.alpha = 1
        }
        UIView.animate(withDuration: duration * 0.45, delay: duration * 0.1, options: [.curveEaseIn, .allowUserInteraction]) {
            picture.alpha = 0
        }
    }

    /// Moves `picture` by as much as `landing`, the view the bubble lands in, moves in `container` from now on, every
    /// frame until the picture is gone
    private static func follow(_ landing: UIView, with picture: UIView, in container: UIView) {
        let landingOrigin = landing.convert(CGPoint.zero, to: container)
        let center = picture.center
        // The clock keeps itself until the picture is gone
        var clock: GlassMotionClock?
        clock = GlassMotionClock(frameRateRange: nil) { [weak landing, weak picture, weak container] _ in
            guard let landing, let picture, let container, picture.superview != nil else {
                clock?.stop()
                clock = nil
                return
            }
            let origin = landing.convert(CGPoint.zero, to: container)
            picture.center = CGPoint(x: center.x + origin.x - landingOrigin.x, y: center.y + origin.y - landingOrigin.y)
        }
        clock?.start()
    }
}
