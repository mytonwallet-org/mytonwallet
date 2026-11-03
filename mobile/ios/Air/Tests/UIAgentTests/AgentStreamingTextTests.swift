import XCTest
import UIKit
import WalletCore
@testable import UIAgent

@MainActor
final class AgentStreamingTextTests: XCTestCase {
    func testRenderedLinksKeepTheirExplicitColorAndUnderline() throws {
        let marked = AgentV2AnswerTables.text("Источник", tables: [], references: [], links: [
            ApiAgentV2AnswerLink(textOffset: 0, textLength: 8, url: "https://example.com")
        ])
        for (name, color) in [("pink", UIColor.systemPink), ("black", .black), ("white", .white)] {
            let text = AgentMessageTextRenderer.makeAttributedText(
                marked, textColor: .label, rendersMarkdown: true,
                markdownProfile: .agentMarkdownV1, linkColor: color
            )
            let expected = NSMutableAttributedString(attributedString: text)
            expected.removeAttribute(.link, range: NSRange(location: 0, length: expected.length))
            let reference = try XCTUnwrap(AgentStreamingTextLayout.make(attributedString: expected, maxWidth: 280).renderedImage)
            for measuresCharacters in [true, false] {
                let layout = AgentStreamingTextLayout.make(
                    attributedString: text, maxWidth: 280, measuresCharacters: measuresCharacters
                )
                let rendered = try XCTUnwrap(layout.renderedImage)
                XCTAssertEqual(UIImage(cgImage: rendered).pngData(), UIImage(cgImage: reference).pngData(),
                    "TextKit must not replace the explicit link style with its default blue underline")
                if !measuresCharacters {
                    let attachment = XCTAttachment(image: UIImage(cgImage: rendered))
                    attachment.name = "Answer link — \(name)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                let region = try XCTUnwrap(layout.linkRegions.first)
                XCTAssertEqual(layout.link(at: CGPoint(x: region.rect.midX, y: region.rect.midY)), URL(string: "https://example.com"))
            }
        }
    }

    func testRenderedLinksFollowInheritedTintAndAccentChanges() throws {
        let marked = AgentV2AnswerTables.text("Источник", tables: [], references: [], links: [
            ApiAgentV2AnswerLink(textOffset: 0, textLength: 8, url: "https://example.com")
        ])
        let view = AgentStreamingTextView()
        defer { view.prepareForReuse() }
        view.configure(
            text: marked, textColor: .label, isStreaming: false, hadStreaming: false,
            rendersMarkdown: true, markdownProfile: .agentMarkdownV1, allowsLinks: false, layoutMaxWidth: 280
        )
        let parent = UIView()
        parent.tintColor = .systemPink
        parent.addSubview(view)
        let imageView = try XCTUnwrap(view.subviews.first?.subviews.first as? UIImageView)
        for color: UIColor in [.systemPink, .black, .white, .systemGreen] {
            parent.tintColor = color
            let expected = NSMutableAttributedString(attributedString: AgentMessageTextRenderer.makeAttributedText(
                "Источник", textColor: color, rendersMarkdown: true,
                detectsLinks: false, markdownProfile: .agentMarkdownV1
            ))
            expected.addAttribute(.underlineStyle, value: color == .black || color == .white ? 1 : 0,
                range: NSRange(location: 0, length: expected.length))
            let reference = try XCTUnwrap(AgentStreamingTextLayout.make(attributedString: expected, maxWidth: 280).renderedImage)
            let rendered = try XCTUnwrap(imageView.image?.cgImage)
            XCTAssertEqual(UIImage(cgImage: rendered).pngData(), UIImage(cgImage: reference).pngData(),
                "Already rendered answers must pick up their parent's accent after attachment and when it changes")
        }
    }

    func testRichAnswerLinksFollowInheritedTintAndAccentChanges() throws {
        let marked = AgentV2AnswerTables.text("Источник", tables: [], references: [], links: [
            ApiAgentV2AnswerLink(textOffset: 0, textLength: 8, url: "https://example.com")
        ])
        let view = AgentRichMessageView()
        view.configure(
            blocks: [.text(marked), .table(AgentMessageTable(rows: [[AgentMessageTableCell(text: marked, isPlainText: true)]]))],
            textColor: .label, maximumContentWidth: 280, detectsLinks: false,
            markdownProfile: .agentMarkdownV1, onURLTap: nil
        )
        let parent = UIView()
        parent.tintColor = .systemPink
        parent.addSubview(view)
        func textViews(in view: UIView) -> [UITextView] {
            view.subviews.flatMap { subview in
                (subview as? UITextView).map { [$0] } ?? textViews(in: subview)
            }
        }
        let links = textViews(in: view)
        XCTAssertEqual(links.count, 2)
        for color: UIColor in [.systemPink, .black, .white, .systemGreen] {
            parent.tintColor = color
            for textView in links {
                XCTAssertEqual(textView.linkTextAttributes[.foregroundColor] as? UIColor, color)
                XCTAssertEqual(textView.linkTextAttributes[.underlineStyle] as? Int, color == .black || color == .white ? 1 : 0)
            }
        }
    }

    func testMessageLinksUnderlineOnlyAMonochromeAccent() throws {
        let marked = AgentV2AnswerTables.text("Docs", tables: [], references: [], links: [
            ApiAgentV2AnswerLink(textOffset: 0, textLength: 4, url: "https://example.com")
        ])
        for color: UIColor in [.systemBlue, .black, .white, UIColor(red: 0, green: 0, blue: 0, alpha: 1)] {
            let text = AgentMessageTextRenderer.makeAttributedText(
                marked, textColor: .label, rendersMarkdown: true,
                markdownProfile: .agentMarkdownV1, linkColor: color
            )
            let attributes = text.attributes(at: 0, effectiveRange: nil)
            XCTAssertNotNil(attributes[.link])
            XCTAssertEqual(attributes[.foregroundColor] as? UIColor, color)
            XCTAssertEqual(attributes[.underlineStyle] as? Int, color == .systemBlue ? 0 : NSUnderlineStyle.single.rawValue)
        }
    }

    func testStatusGradientSweepsInTheReadingDirection() {
        let width: CGFloat = 120
        let phases: [CGFloat] = [0, 0.25, 0.5, 0.75, 0.999]
        for isRightToLeft in [false, true] {
            let offsets = phases.map {
                AgentGradientLabel.getSweepOffset(phase: $0, width: width, isRightToLeft: isRightToLeft)
            }
            for (offset, next) in zip(offsets, offsets.dropFirst()) {
                if isRightToLeft {
                    XCTAssertLessThan(next, offset)
                } else {
                    XCTAssertGreaterThan(next, offset)
                }
            }
            // The two tiles, each two widths long, always cover the label
            for offset in offsets {
                XCTAssertLessThanOrEqual(offset, 0)
                XCTAssertGreaterThanOrEqual(offset + width * 4, width)
            }
            // A full sweep moves by one tile, so the loop has no seam
            let start = AgentGradientLabel.getSweepOffset(phase: 0, width: width, isRightToLeft: isRightToLeft)
            let end = AgentGradientLabel.getSweepOffset(phase: 1, width: width, isRightToLeft: isRightToLeft)
            XCTAssertEqual(abs(end - start), width * 2, accuracy: 0.001)
        }
    }

    func testTypingStatusKeepsItsMinimumDurationAndCoalescesUpdates() throws {
        var time: TimeInterval = 0
        var scheduled: [(delay: TimeInterval, update: DispatchWorkItem)] = []
        var updateCount = 0
        let pacing = AgentTypingStatusPacing(
            minimumDuration: 1.2,
            now: { time },
            schedule: { scheduled.append(($0, $1)) },
            onUpdate: { updateCount += 1 }
        )

        XCTAssertNil(pacing.typingStatusText(nil))
        XCTAssertEqual(pacing.typingStatusText("Searching"), "Searching")
        time = 0.3
        XCTAssertEqual(pacing.typingStatusText("Found sources"), "Searching")
        time = 0.6
        XCTAssertEqual(pacing.typingStatusText("Reading sources"), "Searching")
        XCTAssertEqual(pacing.typingStatusText(nil), "Searching")
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(try XCTUnwrap(scheduled.first?.delay), 0.9, accuracy: 0.0001)
        XCTAssertEqual(updateCount, 0)

        time = 1.2
        try XCTUnwrap(scheduled.first?.update).perform()
        XCTAssertEqual(updateCount, 1)
        XCTAssertEqual(pacing.typingStatusText("Reading sources"), "Reading sources")
        XCTAssertEqual(pacing.typingStatusText("Reading sources"), "Reading sources")
        XCTAssertEqual(scheduled.count, 1)

        time = 1.5
        XCTAssertEqual(pacing.typingStatusText(nil), "Reading sources")
        XCTAssertEqual(scheduled.count, 2)
        time = 2.4
        scheduled[1].update.perform()
        XCTAssertEqual(updateCount, 2)
        XCTAssertNil(pacing.typingStatusText(nil))
        XCTAssertEqual(pacing.typingStatusText("Answering"), "Answering")
        XCTAssertEqual(scheduled.count, 2)
    }

    func testAnimatedCharactersHideTheirStaticCopies() async throws {
        try await checkStreamingMask(text: "Your wallet, at a glance")
    }

    func testAnimatedRTLCharactersHideTheirStaticCopies() async throws {
        try await checkStreamingMask(text: "שלום עולם مرحبا بالعالم")
    }

    func testAnimatedCharactersStayAlignedInRTLLayout() async throws {
        try await checkStreamingMask(text: "שלום עולם مرحبا بالعالم", layoutDirection: .forceRightToLeft)
    }

    func testAnimatedMixedDirectionAndCombinedCharactersHideTheirStaticCopies() async throws {
        try await checkStreamingMask(text: "TON שלום 👨‍👩‍👧‍👦 café e\u{0301} ffi")
    }

    func testLeadingMarginStaysFixedAsTextAndBubbleWidthsChange() throws {
        try checkLeadingMargin(layoutDirection: .forceLeftToRight)
    }

    func testRTLLeadingMarginStaysFixedAsTextAndBubbleWidthsChange() throws {
        try checkLeadingMargin(layoutDirection: .forceRightToLeft)
    }

    func testRevealCompletesOnceTheTextStopsResizing() async throws {
        let hosted = makeHostedTextView()
        defer { hosted.tearDown() }

        var revealCompletedAt: CFTimeInterval?
        hosted.view.onRevealCompleted = { revealCompletedAt = CACurrentMediaTime() }
        let text = "You can review your assets, explore supported tokens, or learn how swaps work."
        hosted.configure(text: text, isStreaming: true, hadStreaming: false)
        hosted.configure(text: text, isStreaming: false, hadStreaming: true)

        var samples: [(time: CFTimeInterval, size: CGSize)] = []
        let deadline = CACurrentMediaTime() + 5
        while revealCompletedAt == nil, CACurrentMediaTime() < deadline {
            hosted.host.view.layoutIfNeeded()
            samples.append((CACurrentMediaTime(), hosted.view.bounds.size))
            try await Task.sleep(for: .milliseconds(16))
        }
        let completedAt = try XCTUnwrap(revealCompletedAt, "The reveal must complete")
        let settledSize = try XCTUnwrap(
            samples.last?.size,
            "The reveal must complete on a later frame, not inside `configure`"
        )
        XCTAssertNotEqual(samples.first?.size, settledSize, "The test must sample the text growing during the reveal")
        let settledAt = try XCTUnwrap(samples.reversed().prefix { $0.size == settledSize }.last?.time)
        // The budget absorbs main-thread stalls on a busy simulator
        XCTAssertLessThan(
            completedAt - settledAt,
            0.75,
            "The reveal, and the follow-ups that wait for it, must not lag behind the settled text"
        )
    }

    func testStreamedMarkdownKeepsRenderedTextAsMoreArrives() {
        let answer = "Your **balance** is `12.5 TON`.\n- **TON:** *staked* 10\n- `USDT` 5\n1. Open **Send**\n2. Enter the *amount*"
        let final = renderedAnswer(answer, isStreaming: false)
        var received = ""
        for character in answer {
            received.append(character)
            let streamed = renderedAnswer(received, isStreaming: true)
            XCTAssertTrue(
                final.string.hasPrefix(streamed.string),
                "\(received.debugDescription) renders as \(streamed.string.debugDescription)"
            )
            for index in 0..<min(streamed.length, final.length) {
                XCTAssertEqual(
                    styleTraits(of: streamed, at: index),
                    styleTraits(of: final, at: index),
                    "Style of character \(index) for \(received.debugDescription)"
                )
            }
        }
    }

    func testStreamedMarkdownKeepsLiteralAsterisks() {
        for isStreaming in [true, false] {
            XCTAssertEqual(renderedAnswer("Costs 2 ** 3 and 4 * 5", isStreaming: isStreaming).string, "Costs 2 ** 3 and 4 * 5")
            XCTAssertEqual(renderedAnswer("**unfinished\nNext", isStreaming: isStreaming).string, "**unfinished\nNext")
        }
    }

    private func renderedAnswer(_ text: String, isStreaming: Bool) -> NSAttributedString {
        AgentMessageTextRenderer.makeAttributedText(
            text,
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1,
            isStreaming: isStreaming
        )
    }

    private func styleTraits(of text: NSAttributedString, at index: Int) -> UIFontDescriptor.SymbolicTraits {
        let font = text.attribute(.font, at: index, effectiveRange: nil) as? UIFont
        return (font?.fontDescriptor.symbolicTraits ?? []).intersection([.traitBold, .traitItalic, .traitMonoSpace])
    }

    private func checkLeadingMargin(layoutDirection: UISemanticContentAttribute) throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let leadingInset: CGFloat = 14
        host.semanticContentAttribute = layoutDirection
        let view = AgentStreamingTextView()
        view.semanticContentAttribute = layoutDirection
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        let widthConstraint = view.widthAnchor.constraint(equalToConstant: 240)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: leadingInset),
            widthConstraint
        ])
        defer { view.prepareForReuse() }

        for (text, width, isStreaming) in [("i", 120.0, true), ("i have", 240.0, true),
                                           ("i have a question", 280.0, true), ("Done", 240.0, false)] {
            widthConstraint.constant = width
            view.configure(
                text: text,
                textColor: .label,
                isStreaming: isStreaming,
                hadStreaming: false,
                rendersMarkdown: false,
                baseFont: .systemFont(ofSize: 17),
                allowsLinks: false,
                layoutMaxWidth: 280
            )
            host.layoutIfNeeded()

            let renderContainer = try XCTUnwrap(view.subviews.first)
            let imageView = try XCTUnwrap(renderContainer.subviews.first as? UIImageView)
            let imageRect = imageView.convert(imageView.bounds, to: host)
            let leadingMargin = layoutDirection == .forceRightToLeft
                ? host.bounds.maxX - imageRect.maxX
                : imageRect.minX - host.bounds.minX
            XCTAssertEqual(leadingMargin, leadingInset, accuracy: 0.5, "The leading margin must not depend on text or bubble width")
        }
    }

    private func checkStreamingMask(
        text: String,
        layoutDirection: UISemanticContentAttribute = .forceLeftToRight
    ) async throws {
        let hosted = makeHostedTextView(layoutDirection: layoutDirection)
        defer { hosted.tearDown() }
        let view = hosted.view

        hosted.configure(text: text, isStreaming: true, hadStreaming: true)
        let renderContainer = try XCTUnwrap(view.subviews.first)
        let imageView = try XCTUnwrap(renderContainer.subviews.first as? UIImageView)
        var sampledSnippetCount = 0
        var visibleStaticCopyCount = 0
        var settledPoints: [CGPoint] = []

        // Inspect actual animation layers across several display-link frames, including overlapping glyph bounds.
        for _ in 0..<45 {
            try await Task.sleep(for: .milliseconds(16))
            let snippets = (renderContainer.layer.sublayers ?? []).filter { $0 !== imageView.layer && $0.contents != nil }
            guard !snippets.isEmpty else { continue }
            let mask = try XCTUnwrap(imageView.layer.mask as? CAShapeLayer)
            let path = try XCTUnwrap(mask.path)
            let fillRule: CGPathFillRule = mask.fillRule == .evenOdd ? .evenOdd : .winding
            for snippet in snippets {
                let rect = imageView.layer.convert(snippet.frame, from: renderContainer.layer)
                sampledSnippetCount += 1
                XCTAssertEqual(snippet.opacity, 0, "A snapshot of the layer tree must not show a glyph before it fades in")
                for x in [rect.minX + 0.1, rect.midX, rect.maxX - 0.1] {
                    let point = CGPoint(x: x, y: rect.midY)
                    if path.contains(point, using: fillRule) {
                        visibleStaticCopyCount += 1
                    }
                    settledPoints.append(point)
                }
            }
        }

        XCTAssertGreaterThan(sampledSnippetCount, 0, "The test must sample the live reveal animation")
        XCTAssertEqual(visibleStaticCopyCount, 0, "Animated glyphs must not also appear in the static text image")

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue((renderContainer.layer.sublayers ?? []).allSatisfy { $0 === imageView.layer || $0.contents == nil })
        let settledMask = try XCTUnwrap(imageView.layer.mask as? CAShapeLayer)
        let settledPath = try XCTUnwrap(settledMask.path)
        for point in settledPoints {
            XCTAssertTrue(settledPath.contains(point), "The static glyph must return after its animation finishes")
        }

        let completed = expectation(description: "Reveal completed")
        view.onRevealCompleted = { completed.fulfill() }
        hosted.configure(text: text, isStreaming: false, hadStreaming: true)
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertNil(imageView.layer.mask)
        XCTAssertEqual(view.displayText, text)
    }

    private func makeHostedTextView(
        layoutDirection: UISemanticContentAttribute = .forceLeftToRight
    ) -> HostedTextView {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let host = UIViewController()
        host.view.semanticContentAttribute = layoutDirection
        window.rootViewController = host
        window.makeKeyAndVisible()
        let view = AgentStreamingTextView()
        view.semanticContentAttribute = layoutDirection
        view.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: host.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor, constant: 20)
        ])
        return HostedTextView(window: window, host: host, view: view)
    }
}

@MainActor
private struct HostedTextView {
    let window: UIWindow
    let host: UIViewController
    let view: AgentStreamingTextView

    func configure(text: String, isStreaming: Bool, hadStreaming: Bool) {
        view.configure(
            text: text,
            textColor: .label,
            isStreaming: isStreaming,
            hadStreaming: hadStreaming,
            rendersMarkdown: true,
            markdownProfile: .agentMarkdownV1,
            baseFont: .systemFont(ofSize: 17),
            allowsLinks: false,
            layoutMaxWidth: 280
        )
        host.view.layoutIfNeeded()
    }

    func tearDown() {
        view.prepareForReuse()
        view.removeFromSuperview()
        window.isHidden = true
    }
}
