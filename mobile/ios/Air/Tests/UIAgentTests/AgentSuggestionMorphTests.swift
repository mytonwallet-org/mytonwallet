import XCTest
import UIKit
@testable import UIAgent
import UIComponents
import WalletResources

@MainActor
final class AgentSuggestionMorphTests: XCTestCase {
    /// Frame by frame, a tapped suggestion turns into its question's bubble, a short one and one whose lines break
    /// differently in the pill and in the bubble: the pill starts where it was and moves and grows without a jump onto
    /// the bubble, the title and the bubble's text stand on one point and show one at a time, never both sharp at once.
    /// Once the morph has the bubble's fill, the bubble's tail grows out of its corner with it, opaque and of the
    /// bubble's colour, and the morph's last frame is the bubble with its tail. The morph stays opaque to its end, when
    /// the bubble takes its place at once, never two translucent bubbles over each other, with its tail already there.
    func testTappedSuggestionTurnsIntoTheBubbleFrameByFrame() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion shows the bubble at once")
        _ = WalletResourcesBundle.bundle.load()
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let container = try XCTUnwrap(window.rootViewController?.view)
        // The long title takes more lines in its narrow pill than in the bubble
        let suggestions: [(title: String, maxWidth: CGFloat)] = [
            ("Why does it matter?", 300),
            ("What would happen to my staking rewards if the network upgrade is delayed again?", 200),
        ]
        for (title, maxWidth) in suggestions {
            let button = AgentSuggestionButton()
            button.maximumNumberOfLines = 0
            button.preferredMaxLayoutWidth = maxWidth
            button.configure(title: title)
            button.frame = CGRect(origin: CGPoint(x: 16, y: 480), size: button.intrinsicContentSize)
            container.addSubview(button)
            button.layoutIfNeeded()
            let source = try XCTUnwrap(AgentSentMessageSource.makeSuggestion(of: button, in: container))
            button.removeFromSuperview()

            let cell = AgentMessageCell(frame: CGRect(x: 0, y: 560, width: 402, height: 160))
            container.addSubview(cell)
            defer { cell.removeFromSuperview() }
            cell.configure(with: AgentMessage(role: .user, text: title, isStreaming: false), onURLTap: { _ in })
            cell.layoutIfNeeded()
            let bubble = cell.bubbleBackgroundView
            let body = bubble.convert(bubble.bodyFrame, to: container)
            let restingTail = try XCTUnwrap(bubble.restingTail, "\(title): the question's bubble has a tail")
            let tailFrame = bubble.convert(restingTail.frame, to: container)
            let morph = try XCTUnwrap(AgentSuggestionMorph.start(from: source, in: container) { cell })
            defer { morph.cancel() }

            let frameCount = 54
            let distance = [
                abs(body.minX - source.frame.minX), abs(body.maxX - source.frame.maxX),
                abs(body.minY - source.frame.minY), abs(body.maxY - source.frame.maxY),
            ].max()!
            // Each frame moves the edges as far as the morph's curve goes over that frame, and no further
            let curve = AgentComposerMetrics.makeTelegramCurve()
            func eased(_ index: Int) -> CGFloat {
                AgentLayerAnimationSampler.getEasedFraction(curve, at: CGFloat(index) / CGFloat(frameCount))
            }
            var previous: CGRect?
            var previousTailScale: CGFloat = 0
            for index in 0...frameCount {
                let largestStep = distance * abs(eased(index) - eased(max(0, index - 1))) + 0.5
                morph.step(at: morph.startTime + AgentSuggestionMorph.duration * Double(index) / Double(frameCount))
                let frame = morph.morphView.frame
                if index == 0 {
                    XCTAssertEqual(frame.minX, source.frame.minX, accuracy: 0.5, "\(title): the pill starts where it was")
                    XCTAssertEqual(frame.minY, source.frame.minY, accuracy: 0.5)
                    XCTAssertEqual(frame.width, source.frame.width, accuracy: 0.5)
                    XCTAssertEqual(frame.height, source.frame.height, accuracy: 0.5)
                    XCTAssertEqual(cell.sentAppearanceView.alpha, 0, "\(title): the bubble waits for the morph")
                    XCTAssertTrue(morph.tailLayer.isHidden, "\(title): the pill has no tail")
                }
                if let previous {
                    for (edge, last) in [(frame.minX, previous.minX), (frame.maxX, previous.maxX),
                                         (frame.minY, previous.minY), (frame.maxY, previous.maxY)] {
                        XCTAssertLessThanOrEqual(abs(edge - last), largestStep, "\(title), frame \(index): no jump")
                    }
                }
                XCTAssertEqual(morph.titleView.alpha + morph.textView.alpha, 1, accuracy: 0.001, "\(title): one text at a time")
                if morph.titleView.alpha > 0.01, morph.textView.alpha > 0.01 {
                    XCTAssertGreaterThanOrEqual(
                        max(morph.titleBlurRadius, morph.textBlurRadius), AgentSuggestionMorph.crossfadeBlurRadius / 2 - 0.001,
                        "\(title), frame \(index): never both line layouts sharp at once"
                    )
                }
                if morph.textView.alpha > 0.99 {
                    XCTAssertEqual(morph.textBlurRadius, 0, accuracy: 0.001, "\(title), frame \(index): the text shows in focus")
                }
                XCTAssertEqual(morph.titleView.frame.minX, morph.textView.frame.minX, accuracy: 0.5, "\(title): on one point")
                XCTAssertEqual(morph.titleView.frame.minY, morph.textView.frame.minY, accuracy: 0.5)
                if !morph.isFinished {
                    XCTAssertEqual(morph.morphView.alpha, 1, "\(title), frame \(index): the morph is opaque")
                    XCTAssertEqual(cell.sentAppearanceView.alpha, 0, "\(title), frame \(index): the bubble waits for its end")
                    if !morph.tailLayer.isHidden {
                        XCTAssertGreaterThanOrEqual(morph.tailScale, previousTailScale, "\(title), frame \(index): the tail only grows")
                        XCTAssertEqual(morph.tailLayer.opacity, 1, "\(title), frame \(index): the tail is opaque")
                        XCTAssertEqual(morph.tailLayer.fillColor, restingTail.fill, "\(title), frame \(index): in the bubble's colour")
                        XCTAssertEqual(morph.textView.alpha, 1, accuracy: 0.001, "\(title), frame \(index): after the fill is the bubble's")
                        previousTailScale = morph.tailScale
                    }
                    if index == frameCount - 1 {
                        // The morph's last frame is the bubble with its tail
                        let shownTail = morph.morphView.convert(morph.tailLayer.frame, to: container)
                        XCTAssertFalse(morph.tailLayer.isHidden, "\(title): the last frame has the tail")
                        XCTAssertGreaterThan(morph.tailScale, 0.99, "\(title): grown")
                        for (shown, resting) in [(shownTail.minX, tailFrame.minX), (shownTail.minY, tailFrame.minY),
                                                 (shownTail.width, tailFrame.width), (shownTail.height, tailFrame.height)] {
                            XCTAssertEqual(shown, resting, accuracy: 0.5, "\(title): on the bubble's tail")
                        }
                    }
                }
                previous = frame
            }
            let landing = try XCTUnwrap(previous)
            XCTAssertEqual(landing.minX, body.minX, accuracy: 0.5, "\(title): it lands on the bubble")
            XCTAssertEqual(landing.minY, body.minY, accuracy: 0.5)
            XCTAssertEqual(landing.width, body.width, accuracy: 0.5)
            XCTAssertEqual(landing.height, body.height, accuracy: 0.5)
            XCTAssertTrue(morph.isFinished)
            XCTAssertNil(morph.morphView.superview, "\(title): the bubble is alone at the end")
            XCTAssertEqual(cell.sentAppearanceView.alpha, 1)
            XCTAssertEqual(morph.textView.alpha, 1, "\(title): the bubble's text shows by the end")
            XCTAssertEqual(morph.textBlurRadius, 0, "\(title): in focus")
            XCTAssertEqual(morph.titleView.alpha, 0)

            XCTAssertGreaterThan(previousTailScale, 0.99, "\(title): the tail grew in the morph")

            // The bubble shows with its tail, opaque, and nothing grows after the morph
            XCTAssertFalse(bubble.isTailMorphing, "\(title): the tail is already there")
            for layer in [cell.sentAppearanceView.layer, bubble.layer, bubble.bodyLayer] {
                XCTAssertEqual(layer.opacity, 1, "\(title): opaque")
            }
        }
    }

    /// A question flies out of the field into its bubble up to ten lines in the bubble, as on Android and the web, its
    /// lines counted as the bubble breaks them, its own line breaks and the ones its width makes
    func testOnlyAQuestionOfUpToTenLinesFlies() {
        let chatWidth: CGFloat = 402
        let lines = (1...11).map { "Line \($0)" }
        let tenLines = lines.prefix(10).joined(separator: "\n")
        XCTAssertEqual(AgentMessageCell.countQuestionLines(tenLines, chatWidth: chatWidth), 10)
        XCTAssertTrue(AgentSentMessageMorph.canFly(tenLines, chatWidth: chatWidth))
        XCTAssertFalse(AgentSentMessageMorph.canFly(lines.joined(separator: "\n"), chatWidth: chatWidth))
        // One line of text that wraps in the bubble counts every line it takes
        let wrapping = String(repeating: "word ", count: 120)
        XCTAssertGreaterThan(AgentMessageCell.countQuestionLines(wrapping, chatWidth: chatWidth), 10)
        XCTAssertFalse(AgentSentMessageMorph.canFly(wrapping, chatWidth: chatWidth))
        XCTAssertFalse(AgentSentMessageMorph.canFly("", chatWidth: chatWidth))
    }

    /// The suggestions beside a tapped one leave as a ripple away from it, the nearest first: each fades over several
    /// frames rather than vanishing at once, while the tapped one stays for its morph
    func testOtherSuggestionsRippleAwayFromTheTappedOne() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let window = makeKeyWindow(showing: UIViewController())
        defer { window.isHidden = true }
        let container = try XCTUnwrap(window.rootViewController?.view)
        let buttons = (0..<3).map { index -> AgentSuggestionButton in
            let button = AgentSuggestionButton()
            button.configure(title: "Suggestion \(index)")
            button.frame = CGRect(origin: CGPoint(x: 16, y: 400 + CGFloat(index) * 50), size: button.intrinsicContentSize)
            container.addSubview(button)
            return button
        }
        defer { buttons.forEach { $0.removeFromSuperview() } }
        container.layoutIfNeeded()
        CATransaction.flush()

        let pictures = AgentSuggestionMorph.rippleAway(buttons, from: buttons[0], in: container)
        XCTAssertEqual(pictures.count, 2)
        XCTAssertEqual(buttons[0].alpha, 1, "The tapped one stays for its morph")
        XCTAssertEqual(buttons[1].alpha, 0, "The others leave as pictures")
        XCTAssertEqual(buttons[2].alpha, 0)
        CATransaction.flush()
        var samples: [[Float]] = []
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < 0.4 {
            samples.append(pictures.map { $0.layer.presentation()?.opacity ?? $0.layer.opacity })
            try await Task.sleep(for: .milliseconds(10))
        }
        for index in pictures.indices {
            let opacities = samples.map { $0[index] }
            XCTAssertGreaterThanOrEqual(
                opacities.filter { $0 > 0.05 && $0 < 0.95 }.count, 2,
                "Picture \(index) fades over several frames: \(opacities)"
            )
            XCTAssertTrue(zip(opacities, opacities.dropFirst()).allSatisfy { $1 <= $0 + 0.01 }, "Only fading")
            XCTAssertEqual(opacities.last ?? 1, 0, accuracy: 0.01)
        }
        if !UIAccessibility.isReduceMotionEnabled {
            let firstFading = samples.firstIndex { $0[0] < 0.95 } ?? samples.count
            let secondFading = samples.firstIndex { $0[1] < 0.95 } ?? samples.count
            XCTAssertLessThanOrEqual(firstFading, secondFading, "The nearest leaves first")
        }
    }
}
