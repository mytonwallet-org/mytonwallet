import XCTest
import UIKit
import UIComponents
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

    /// A whitish glint crosses the status in the reading direction, from just before the text to just past it, in
    /// 0.75 s, and the text shows only its gradient before and after it
    func testStatusGlintCrossesTheText() throws {
        let width: CGFloat = 160
        let halfWidth = AgentGradientLabel.glintHalfWidth
        for isRightToLeft in [false, true] {
            func getCentre(_ time: CFTimeInterval) -> CGFloat? {
                AgentGradientLabel.getGlintCentre(time: time, width: width, isRightToLeft: isRightToLeft)
            }
            let start = try XCTUnwrap(getCentre(0))
            let middle = try XCTUnwrap(getCentre(0.375))
            let end = try XCTUnwrap(getCentre(0.75))
            XCTAssertEqual(start, isRightToLeft ? width + 2 * halfWidth : -2 * halfWidth, accuracy: 0.001, "Before the text")
            XCTAssertEqual(middle, width / 2, accuracy: 0.001)
            XCTAssertEqual(end, isRightToLeft ? -2 * halfWidth : width + 2 * halfWidth, accuracy: 0.001, "Past the text")
            XCTAssertNil(getCentre(-0.1), "Not before it starts")
            XCTAssertNil(getCentre(0.8), "Nor after it")
        }
    }

    /// The glint plays once each time the status changes: as "Analyzing the request…" appears, and once more after it
    /// turns into another step, as the new text comes into focus. Nothing repeats while a status stays.
    func testStatusGlintPlaysOnceForEachStatus() {
        let label = AgentGradientLabel()
        XCTAssertNil(label.glintTime)
        func playThrough() -> Int {
            var glintFrames = 0
            for _ in 0..<200 {
                label.step(by: 1.0 / 60)
                if let time = label.glintTime, time >= 0 { glintFrames += 1 }
            }
            return glintFrames
        }

        label.setText("Analyzing the request…", animated: false)
        XCTAssertEqual(label.glintTime, -AgentGradientLabel.glintDelay, "It waits for the text to come into focus")
        XCTAssertGreaterThan(playThrough(), 0, "One glint as the status appears")
        XCTAssertNil(label.glintTime, "Then none")
        XCTAssertEqual(playThrough(), 0, "Nothing repeats while the status stays")

        label.setText("Analyzing the request…", animated: false)
        XCTAssertNil(label.glintTime, "The same status plays none")

        label.setText("Searching the knowledge base…", animated: false)
        XCTAssertGreaterThan(playThrough(), 0, "One glint after the switch")
        XCTAssertEqual(playThrough(), 0)

        label.setText(nil, animated: false)
        XCTAssertNil(label.glintTime)
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

    func testAnimatedCharactersOfALongAnswerHideTheirStaticCopies() async throws {
        try await checkStreamingMask(text: longAnswer)
    }

    func testBurstOfTextAnimatesALimitedNumberOfCharacters() async throws {
        let hosted = makeHostedTextView()
        defer { hosted.tearDown() }
        hosted.configure(text: longAnswer, isStreaming: true, hadStreaming: true)
        let renderContainer = try XCTUnwrap(hosted.view.subviews.first)
        let imageView = try XCTUnwrap(renderContainer.subviews.first as? UIImageView)
        var sampledSnippetCount = 0
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(16))
            let snippetCount = (renderContainer.layer.sublayers ?? []).filter { $0 !== imageView.layer && $0.contents != nil }.count
            sampledSnippetCount = max(sampledSnippetCount, snippetCount)
            XCTAssertLessThanOrEqual(snippetCount, 150)
        }
        XCTAssertGreaterThan(sampledSnippetCount, 0, "The test must sample the live reveal animation")
    }

    func testStreamingTextFollowsItsLatestChunkAndFinalTextWinsOverALayoutInProgress() async throws {
        let hosted = makeHostedTextView()
        defer { hosted.tearDown() }
        var streamed = ""
        for word in longAnswer.split(separator: " ") {
            streamed += streamed.isEmpty ? String(word) : " \(word)"
            hosted.configure(text: streamed, isStreaming: true, hadStreaming: false)
        }
        let deadline = CACurrentMediaTime() + 5
        while hosted.view.displayText != streamed, CACurrentMediaTime() < deadline {
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertEqual(hosted.view.displayText, streamed, "A burst of chunks must end up at its latest text")

        hosted.configure(text: streamed + " More", isStreaming: true, hadStreaming: false)
        hosted.configure(text: "Final", isStreaming: false, hadStreaming: true)
        XCTAssertEqual(hosted.view.displayText, "Final")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(hosted.view.displayText, "Final", "A layout of older text must not replace the final one")
    }

    func testStreamingTextTakesATintThatChangesWhileItIsLaidOut() async throws {
        let hosted = makeHostedTextView()
        defer { hosted.tearDown() }
        let marked = AgentV2AnswerTables.text("Источник", tables: [], references: [], links: [
            ApiAgentV2AnswerLink(textOffset: 0, textLength: 8, url: "https://example.com")
        ])
        var text = marked
        hosted.configure(text: text, isStreaming: true, hadStreaming: false)
        let imageView = try XCTUnwrap(hosted.view.subviews.first?.subviews.first as? UIImageView)
        let traits = hosted.view.traitCollection
        func pixels(of image: CGImage?) -> Data? {
            image?.dataProvider?.data as Data?
        }
        let colors: [UIColor] = [.systemGreen, .systemOrange, .systemPurple, .systemTeal, .systemPink]

        // Each round changes the tint later, so that some rounds change it while the layout runs off the main thread
        for round in 0..<12 {
            text += " " + longAnswer
            hosted.configure(text: text, isStreaming: true, hadStreaming: false)
            try await Task.sleep(for: .milliseconds(10 * round))
            let color = colors[round % colors.count]
            hosted.host.view.tintColor = color
            let expected = AgentStreamingTextLayout.make(
                attributedString: AgentMessageTextRenderer.makeAttributedText(
                    text, textColor: UIColor.label.resolvedColor(with: traits), rendersMarkdown: true, detectsLinks: false,
                    markdownProfile: .agentMarkdownV1, isStreaming: true, baseFont: .systemFont(ofSize: 17),
                    linkColor: color.resolvedColor(with: traits)
                ),
                maxWidth: 280
            ).renderedImage
            let expectedPixels = pixels(of: expected)
            let deadline = CACurrentMediaTime() + 2
            while pixels(of: imageView.image?.cgImage) != expectedPixels, CACurrentMediaTime() < deadline {
                try await Task.sleep(for: .milliseconds(16))
            }
            XCTAssertTrue(pixels(of: imageView.image?.cgImage) == expectedPixels, "Round \(round) must end up in the latest tint")
        }
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

    /// An answer still arriving holds back a marker it has opened but not closed, and a list item with nothing after
    /// its marker yet, rather than drawing them as text; closed, the run renders as it will; the final text renders as
    /// it always has, an unclosed marker included
    func testStreamedMarkdownHoldsBackOpenMarkers() throws {
        let intro = "Риски сделки с заёмными деньгами:\n\n"
        let introShown = renderedAnswer(intro, isStreaming: true).string
        for partial in ["- **", "- ** ", "* **", "1. **", "- `", "- __", "- *"] {
            let shown = renderedAnswer(intro + partial, isStreaming: true).string
            XCTAssertFalse(shown.contains("*") || shown.contains("`") || shown.contains("_"), "\(partial.debugDescription) shows \(shown.debugDescription)")
            XCTAssertTrue(shown.hasPrefix(introShown.trimmingCharacters(in: .newlines)))
        }

        let closed = renderedAnswer(intro + "- **Плечо** — заём", isStreaming: true)
        XCTAssertFalse(closed.string.contains("*"))
        let bold = (closed.string as NSString).range(of: "Плечо")
        XCTAssertNotEqual(bold.location, NSNotFound)
        XCTAssertTrue(styleTraits(of: closed, at: bold.location).contains(.traitBold), "Bold once closed")
        let final = renderedAnswer(intro + "- **Плечо** — заём", isStreaming: false)
        XCTAssertEqual(closed.string, final.string)

        XCTAssertTrue(renderedAnswer(intro + "- **", isStreaming: false).string.hasSuffix("**"), "A final answer keeps its text")
    }

    /// A visible answer's cell streams its text through the streamed text view as each part arrives, and holds back a
    /// list item whose bold title has only its opening marker yet, with a space after it as well
    func testStreamingCellHoldsBackAListItemsOpenMarker() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        host.view.addSubview(cell)
        var message = AgentMessage(role: .assistant, text: "Риски", isStreaming: true, renderingPolicy: .agentV2Safe)
        cell.configure(with: message, onURLTap: { _ in })
        cell.layoutIfNeeded()
        let textView = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? AgentStreamingTextView }.first)
        // Streaming text is laid out off the main thread, so each part shows once its layout is in
        func waitForLayout(of text: String) async throws {
            let expected = renderedAnswer(text, isStreaming: true).string
            let deadline = CACurrentMediaTime() + 5
            while textView.displayText != expected, CACurrentMediaTime() < deadline {
                try await Task.sleep(for: .milliseconds(16))
                cell.layoutIfNeeded()
            }
            XCTAssertEqual(textView.displayText, expected)
        }
        for tail in ["- **", "- ** ", "* **"] {
            message.text = "Риски сделки с заёмными деньгами:\n\n" + tail
            cell.updateStreamingMessage(message)
            cell.layoutIfNeeded()
            try await waitForLayout(of: message.text)
            XCTAssertFalse(textView.isHidden, "Streamed through the streamed text view")
            XCTAssertFalse(textView.displayText.contains("*"), "\(tail.debugDescription) shows \(textView.displayText.debugDescription)")
        }
        message.text = "Риски сделки с заёмными деньгами:\n\n- **Плечо** — заём"
        cell.updateStreamingMessage(message)
        cell.layoutIfNeeded()
        try await waitForLayout(of: message.text)
        XCTAssertTrue(textView.displayText.hasSuffix("Плечо — заём"))
    }

    /// An answer that shows as rich content while it streams, as one with a table does, holds back the markers still
    /// open at its end as the streamed text does
    func testStreamedRichAnswerHoldsBackOpenMarkers() throws {
        let view = AgentRichMessageView()
        func lastText(isStreaming: Bool) -> String? {
            view.configure(
                blocks: [.text("Сравнение:"), .text("Риски сделки с заёмными деньгами:\n\n- **")],
                textColor: .label,
                maximumContentWidth: 300,
                detectsLinks: false,
                markdownProfile: .agentMarkdownV1,
                isStreaming: isStreaming,
                onURLTap: nil
            )
            return view.arrangedSubviews.compactMap { ($0 as? UITextView)?.attributedText.string }.last
        }
        let streamed = try XCTUnwrap(lastText(isStreaming: true))
        XCTAssertFalse(streamed.contains("**"), "Streaming shows \(streamed.debugDescription)")
        XCTAssertTrue(streamed.hasPrefix("Риски сделки"))
        XCTAssertTrue(try XCTUnwrap(lastText(isStreaming: false)).hasSuffix("**"), "The final answer as it always was")
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    private var longAnswer: String {
        Array(repeating: "Your wallet, at a glance.", count: 40).joined(separator: " ")
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

    /// A streamed character comes in as a transcript's does: out of a blur and nearly transparent, sharp within
    /// 0.15 s, in the accent, which then turns into its own colour within 0.5 s. With Reduce Motion it only fades in.
    func testStreamedCharacterComesOutOfABlurInTheAccent() {
        let appearance = AgentStreamedCharacterAppearance.self
        let arrival = appearance.getAppearance(age: 0)
        XCTAssertEqual(arrival.opacity, 0.15, accuracy: 0.001)
        XCTAssertEqual(arrival.glowOpacity, 0.9, accuracy: 0.001, "Blurred in the accent's glow")
        XCTAssertEqual(arrival.accent, 0.15, accuracy: 0.001, "All accent, as transparent as the character")

        let halfway = appearance.getAppearance(age: 0.075)
        XCTAssertEqual(halfway.opacity, 0.575, accuracy: 0.001)
        XCTAssertEqual(halfway.glowOpacity, 0.45, accuracy: 0.001)

        let sharp = appearance.getAppearance(age: 0.15)
        XCTAssertEqual(sharp.opacity, 1)
        XCTAssertEqual(sharp.glowOpacity, 0, "Sharp, without its glow")
        XCTAssertEqual(sharp.accent, 1, accuracy: 0.001, "Still in the accent")

        XCTAssertEqual(appearance.getAppearance(age: 0.4).accent, 0.5, accuracy: 0.001, "Turning into its own colour")
        let settled = appearance.getAppearance(age: 0.65)
        XCTAssertEqual(settled.opacity, 1)
        XCTAssertEqual(settled.accent, 0, accuracy: 0.001, "In its own colour")
        XCTAssertEqual(appearance.getAppearance(age: 2).accent, 0)

        XCTAssertEqual(appearance.getDuration(isMotionReduced: false), 0.65, accuracy: 0.0001)
        XCTAssertEqual(appearance.getDuration(isMotionReduced: true), 0.15, accuracy: 0.0001)
    }

    /// A streamed character arrives in the Agent's blue, which turns violet by the middle of its turn into its own
    /// colour: the violet copy over the blue one, together as much of the Agent's colours as the accent amount, and
    /// none once it is settled
    func testStreamedCharacterComesInInTheAgentsBlueTurningViolet() {
        let appearance = AgentStreamedCharacterAppearance.self
        let arrival = appearance.getTintOpacities(age: 0)
        XCTAssertEqual(arrival.blue, 0.15, accuracy: 0.001, "Blue as it arrives")
        XCTAssertEqual(arrival.violet, 0, accuracy: 0.001)
        let sharp = appearance.getTintOpacities(age: 0.15)
        XCTAssertEqual(sharp.blue, 1, accuracy: 0.001, "All blue once sharp")
        XCTAssertEqual(sharp.violet, 0, accuracy: 0.001)
        let middle = appearance.getTintOpacities(age: 0.4)
        XCTAssertEqual(middle.violet, 0.5, accuracy: 0.001, "Violet by the middle of its turn")
        XCTAssertEqual(middle.blue, 0, accuracy: 0.001)
        for age in stride(from: 0.0, through: 0.65, by: 0.05) {
            let tints = appearance.getTintOpacities(age: age)
            let shown = tints.blue * (1 - tints.violet) + tints.violet
            XCTAssertEqual(shown, appearance.getAppearance(age: age).accent, accuracy: 0.001, "As much colour at \(age) s")
        }
        let settled = appearance.getTintOpacities(age: 0.65)
        XCTAssertEqual(settled.blue + settled.violet, 0, accuracy: 0.001)

        // The deep pair on light and the bright pair on dark, the glow's own colours
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        func components(_ color: UIColor, _ traits: UITraitCollection) -> SIMD3<Float> {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return SIMD3(Float(red), Float(green), Float(blue))
        }
        for (color, traits, expected) in [
            (AgentGlowPalette.textBlue, light, AgentGlowPalette.deepBlue),
            (AgentGlowPalette.textViolet, light, AgentGlowPalette.deepViolet),
            (AgentGlowPalette.textBlue, dark, AgentGlowPalette.brightBlue),
            (AgentGlowPalette.textViolet, dark, AgentGlowPalette.brightViolet),
        ] {
            let difference = components(color, traits) - expected
            XCTAssertLessThan(max(abs(difference.x), abs(difference.y), abs(difference.z)), 0.002)
        }
    }

    /// The reveal starts in the Agent's palette, whatever the accent: its blue and violet layers over the settling
    /// characters, and the blue glow of a character coming out of its blur
    func testRevealStartsInTheAgentsColoursRatherThanTheAccent() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion only fades the characters in")
        let hosted = makeHostedTextView()
        defer { hosted.tearDown() }
        hosted.host.view.tintColor = .systemPink
        let view = hosted.view
        let text = (1...6).map { "Line \($0) of an answer that streams in." }.joined(separator: "\n")
        hosted.configure(text: text, isStreaming: true, hadStreaming: false)
        let renderContainer = try XCTUnwrap(view.subviews.first)
        let imageView = try XCTUnwrap(renderContainer.subviews.first as? UIImageView)
        let tints = (renderContainer.layer.sublayers ?? []).filter { $0.mask != nil && $0 !== imageView.layer }
        XCTAssertEqual(tints.count, 2, "Blue and violet")
        let traits = view.traitCollection
        let expected = [AgentGlowPalette.textBlue, AgentGlowPalette.textViolet].map { $0.resolvedColor(with: traits).cgColor }
        let accent = UIColor.systemPink.resolvedColor(with: traits).cgColor
        var glowSamples = 0
        for _ in 0..<60 where tints.contains(where: \.isHidden) || glowSamples == 0 {
            try await Task.sleep(for: .milliseconds(16))
            let snippets = (renderContainer.layer.sublayers ?? []).filter { $0 !== imageView.layer && $0.contents != nil }
            for snippet in snippets where snippet.animation(forKey: "revealshadowOpacity") != nil {
                glowSamples += 1
                XCTAssertEqual(snippet.shadowColor, expected[0], "The glow in the Agent's blue")
                XCTAssertNotEqual(snippet.shadowColor, accent)
            }
        }
        XCTAssertGreaterThan(glowSamples, 0, "The test must sample a character coming in")
        XCTAssertFalse(tints.contains(where: \.isHidden), "The colours show over the settling characters")
        XCTAssertEqual(tints.compactMap(\.backgroundColor), expected, "The Agent's blue under its violet")
        XCTAssertFalse(tints.contains { $0.backgroundColor == accent }, "Not the accent")
    }

    /// Only the characters still settling animate: the accent covers just them, never the whole answer, and the glow
    /// is gone from a character once it is sharp. Settled text, links and code included, shows in its final colours:
    /// no accent and no animated copy over the text once the reveal completes.
    func testOnlySettlingCharactersAnimateAndSettledTextKeepsItsColours() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion only fades the characters in")
        let hosted = makeHostedTextView()
        defer { hosted.tearDown() }
        let view = hosted.view
        let text = (1...12).map { "Line \($0) with **bold**, `code` and [a link](https://example.com)." }
            .joined(separator: "\n")
        hosted.configure(text: text, isStreaming: true, hadStreaming: false)
        let renderContainer = try XCTUnwrap(view.subviews.first)
        let imageView = try XCTUnwrap(renderContainer.subviews.first as? UIImageView)
        // The accent is the masked layer over the text, whose picture has its own reveal mask
        let accent = try XCTUnwrap(renderContainer.layer.sublayers?.first { $0.mask != nil && $0 !== imageView.layer })
        var accentSamples = 0
        var leavesSettledLines = false
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(16))
            let snippets = (renderContainer.layer.sublayers ?? []).filter { $0 !== imageView.layer && $0.contents != nil }
            for snippet in snippets {
                XCTAssertEqual(snippet.shadowOpacity, 0, "The glow rests at none; only its animation shows it")
            }
            guard !accent.isHidden else { continue }
            accentSamples += 1
            XCTAssertNotNil(accent.backgroundColor)
            XCTAssertLessThanOrEqual(accent.frame.maxY, renderContainer.bounds.height + 0.5)
            if accent.frame.minY > 0.5 {
                leavesSettledLines = true
            }
        }
        XCTAssertGreaterThan(accentSamples, 0, "The test must sample the accent while characters settle")
        // The accent covers the characters still settling: the first lines leave it as they settle, while the rest
        // still come in, rather than the whole answer staying under it
        XCTAssertTrue(leavesSettledLines, "The accent covers the characters still settling, not the whole answer")

        let completed = expectation(description: "Reveal completed")
        view.onRevealCompleted = { completed.fulfill() }
        hosted.configure(text: text, isStreaming: false, hadStreaming: true)
        await fulfillment(of: [completed], timeout: 10)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(accent.isHidden, "No accent over settled text")
        XCTAssertTrue(accent.mask?.sublayers?.isEmpty ?? true)
        XCTAssertTrue((renderContainer.layer.sublayers ?? []).allSatisfy { $0 === imageView.layer || $0.contents == nil })
        XCTAssertNil(imageView.layer.mask, "The text shows as rendered, in its final colours")
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
