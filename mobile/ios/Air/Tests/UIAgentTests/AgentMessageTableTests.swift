import XCTest
import UIKit
@testable import UIAgent
import UIComponents
import WalletContext
import WalletCore
import WalletResources

final class AgentMessageTableTests: XCTestCase {
    func testPlainTextKeepsSingleBlockPath() {
        let source = "Balance: **125 TON**\nNo table here."

        XCTAssertEqual(AgentMessageBlockParser.parse(source), [.text(source)])
    }

    func testStreamingTableAndCodeSettleOnceTheLineAfterThemIsComplete() {
        let table = "Intro\n\n| A | B |\n|---|---:|\n| x | 1 |"
        let code = "```swift\nlet a = 1\n```"
        let cases: [(source: String, settledLines: Int)] = [
            (table, 0),
            (table + "\n", 0),
            (table + "\n| y", 0),
            (table + "\n\nNext", 6),
            (table + "\n\nNext\n", 6),
            (table + "\nNext words", 0),
            (table + "\nNext words\n", 5),
            (code, 0),
            (code + "\n", 3),
            (code + "\n\n\nTail", 5),
            ("```\nopen fence\n| A | B |\n|---|---|\n| x | 1 |\nmore\n", 0),
        ]
        for (source, settledLines) in cases {
            XCTAssertEqual(AgentMessageBlockParser.countSettledLines(in: source), settledLines, source)
        }
    }

    func testMarkdownTableParsesAlignmentAndEscapedPipes() throws {
        let blocks = AgentMessageBlockParser.parse(
            """
            Portfolio:

            | Token | Pair | Value |
            | :--- | :---: | ---: |
            | TON | GRAM \\| TON | 125.50 |

            Updated now.
            """
        )

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks.first, .text("Portfolio:"))
        XCTAssertEqual(blocks.last, .text("Updated now."))
        let table = try XCTUnwrap(blocks.compactMap(\.table).first)
        XCTAssertEqual(table.rows[0], [
            AgentMessageTableCell(text: "Token", isHeader: true),
            AgentMessageTableCell(text: "Pair", isHeader: true, alignment: .center),
            AgentMessageTableCell(text: "Value", isHeader: true, alignment: .end),
        ])
        XCTAssertEqual(table.rows[1], [
            AgentMessageTableCell(text: "TON"),
            AgentMessageTableCell(text: "GRAM | TON", alignment: .center),
            AgentMessageTableCell(text: "125.50", alignment: .end),
        ])
    }

    func testMarkdownTablePadsMissingCellsAndIgnoresExtraCells() throws {
        let table = try XCTUnwrap(AgentMessageBlockParser.parse(
            """
            A | B
            --- | ---
            | one |
            one | two | three
            """
        ).compactMap(\.table).first)

        XCTAssertEqual(
            table.rows.dropFirst().map { $0.map(\.text) },
            [["one", ""], ["one", "two"]]
        )
    }

    func testMarkdownTableAcceptsSingleHyphenDelimiters() throws {
        let table = try XCTUnwrap(AgentMessageBlockParser.parse(
            """
            A | B | C
            - | :-: | -:
            one | two | three
            """
        ).compactMap(\.table).first)

        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows[0].map(\.alignment), [.start, .center, .end])
    }

    func testHTMLTableSupportsTelegramCellAttributes() throws {
        let blocks = AgentMessageBlockParser.parse(
            """
            Before
            <table border="1" class="striped compact">
            <caption><strong>Wallet</strong> &amp; positions</caption>
            <tr><th rowspan="2" valign="middle">Asset</th><th colspan="2" align="center">Position</th><th rowspan="2" valign="bottom">Status</th></tr>
            <tr><th align="right">Balance</th><th style="text-align: right">Value</th></tr>
            <tr><td><code>TON</code></td><td align="right">125.50</td><td align="right">$712.84</td><td align="center"><a href="https://tonviewer.com">Active</a></td></tr>
            <tr><td header colspan="2">Total</td><td colspan="2" align="right">**$712.84**</td></tr>
            </table>
            After
            """
        )

        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks.first, .text("Before"))
        XCTAssertEqual(blocks.last, .text("After"))
        let table = try XCTUnwrap(blocks.compactMap(\.table).first)
        XCTAssertEqual(table.title, "**Wallet** & positions")
        XCTAssertTrue(table.isBordered)
        XCTAssertTrue(table.isStriped)
        XCTAssertEqual(table.rows.count, 4)
        XCTAssertEqual(
            table.rows[0][0],
            AgentMessageTableCell(
                text: "Asset",
                isHeader: true,
                verticalAlignment: .middle,
                rowSpan: 2
            )
        )
        XCTAssertEqual(table.rows[0][1].columnSpan, 2)
        XCTAssertEqual(table.rows[0][1].alignment, .center)
        XCTAssertEqual(table.rows[0][2].verticalAlignment, .bottom)
        XCTAssertEqual(table.rows[2][0].text, "`TON`")
        XCTAssertEqual(table.rows[2][3].text, "Active (https://tonviewer.com)")
        XCTAssertTrue(table.rows[3][0].isHeader)
        XCTAssertEqual(table.rows[3][1].text, "**$712.84**")
    }

    func testHTMLTableOnlyKeepsApprovedLinkTargets() throws {
        let table = try XCTUnwrap(AgentMessageBlockParser.parse(
            """
            <table>
            <tr><td><a href="javascript:alert(1)">Script</a></td><td><a href="intent://scan">Intent</a></td></tr>
            <tr><td><a href="https://tonviewer.com">Web</a></td><td><a href="mtw://wallet">Wallet</a></td></tr>
            </table>
            """
        ).compactMap(\.table).first)

        XCTAssertEqual(
            table.rows.map { $0.map(\.text) },
            [
                ["Script", "Intent"],
                ["Web (https://tonviewer.com)", "Wallet (mtw://wallet)"],
            ]
        )
    }

    func testGridPlacesCellsAroundRowAndColumnSpans() throws {
        let table = try XCTUnwrap(AgentMessageBlockParser.parse(
            """
            <table border="1">
            <tr><th rowspan="2">Asset</th><th colspan="2">Position</th><th rowspan="2">Status</th></tr>
            <tr><th>Balance</th><th>Value</th></tr>
            <tr><td>TON</td><td>125.50</td><td>$712.84</td><td>Active</td></tr>
            </table>
            """
        ).compactMap(\.table).first)

        let grid = AgentMessageBlockParser.resolveGrid(table)

        XCTAssertEqual(grid.rowCount, 3)
        XCTAssertEqual(grid.columnCount, 4)
        XCTAssertEqual(grid.cells.map(\.column), [0, 1, 3, 1, 2, 0, 1, 2, 3])
    }

    func testTableSyntaxInsideFencedCodeRemainsText() {
        let source = """
        ```markdown
        | A | B |
        | --- | --- |
        | 1 | 2 |
        ```
        """

        XCTAssertEqual(AgentMessageBlockParser.parse(source), [.text(source)])
    }

    func testMarkdownAndHTMLTablesInsideTildeFenceRemainText() {
        let source = """
        ~~~html
        | A | B |
        | - | - |
        | 1 | 2 |
        <table><tr><td>A</td><td>B</td></tr></table>
        ~~~~
        """

        XCTAssertEqual(AgentMessageBlockParser.parse(source), [.text(source)])
    }

    func testInvalidTableFallsBackToPlainText() {
        let source = """
        | A | B |
        | -- | nope |
        | 1 | 2 |
        """

        XCTAssertEqual(AgentMessageBlockParser.parse(source), [.text(source)])
    }

    func testRenderingLimitAddsSpanningTruncationRow() {
        let rows = (0..<210).map { row in
            [AgentMessageTableCell(text: "\(row)")]
        }
        let limited = AgentMessageTableRenderer.limitedForRendering(AgentMessageTable(rows: rows))

        XCTAssertEqual(limited.rows.count, 201)
        XCTAssertEqual(limited.rows.last?.first?.text, "…")
        XCTAssertEqual(limited.rows.last?.first?.columnSpan, 1)
    }

    func testRenderingLimitTruncatesPartwayThroughWideRowsAtCellLimit() {
        let rows = (0..<50).map { row in
            (0..<41).map { column in
                AgentMessageTableCell(text: "\(row)-\(column)")
            }
        }
        let limited = AgentMessageTableRenderer.limitedForRendering(AgentMessageTable(rows: rows))

        XCTAssertEqual(limited.rows.count, 26)
        XCTAssertEqual(limited.rows[24].count, 16)
        XCTAssertEqual(limited.rows[24].last?.text, "24-15")
        XCTAssertEqual(limited.rows.last?.first?.text, "…")
        XCTAssertEqual(limited.rows.last?.first?.columnSpan, 41)
    }

}

private extension AgentMessageBlock {
    var table: AgentMessageTable? {
        if case .table(let table) = self { return table }
        return nil
    }
}

@MainActor
final class AgentMessageTableLayoutTests: XCTestCase {
    private let source = """
    Вот ваши активы в «My Wallet 25»:

    | Актив | Сеть | Баланс |
    | --- | --- | --- |
    | TON | ton | 125.123456789 |
    | USDT | ethereum | 42.50 |
    """

    func testRestoredTableUsesAvailableWidthBeforeAndAfterFitting() throws {
        _ = WalletResourcesBundle.bundle.load()
        for initialWidth: CGFloat in [0, 44, 402] {
            for hasAnswerBlocks in [false, true] {
                let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: initialWidth, height: 80))
                var message = AgentMessage(role: .assistant, text: source, isStreaming: false)
                message.answerBlocks = hasAnswerBlocks ? AgentMessageBlockParser.parse(source) : nil
                cell.configure(with: message, onURLTap: { _ in })
                cell.layoutIfNeeded()
                try assertTableLayout(cell, width: 402)
                try assertTableLayout(cell, width: 320)
                try assertTableLayout(cell, width: 874)
                try assertTableLayout(cell, width: 402)
            }
        }
    }

    func testReusedTableKeepsWidthAfterFollowupsDisappear() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 80))
        for role in [AgentMessage.Role.user, .assistant] {
            cell.configure(with: AgentMessage(role: role, text: "T", isStreaming: false), onURLTap: { _ in })
            cell.layoutIfNeeded()
            cell.prepareForReuse()
            var message = AgentMessage(role: .assistant, text: source, isStreaming: false,
                controls: [AgentMessageControl(id: "followup:next", title: "Tell me more", isEnabled: true, kind: .followup)])
            cell.configure(with: message, onURLTap: { _ in })
            try assertTableLayout(cell, width: 402)
            message.controls = []
            cell.configure(with: message, onURLTap: { _ in })
            try assertTableLayout(cell, width: 402)
            cell.prepareForReuse()
        }
    }

    func testStreamingAnswerShowsItsClosedTableAboveTheTextStillArriving() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 80))
        var message = AgentMessage(role: .assistant, text: source, isStreaming: true)
        cell.configure(with: message, onURLTap: { _ in })
        cell.layoutIfNeeded()
        let richContent = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? AgentRichMessageView }.first)
        let revealView = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? AgentStreamingTextView }.first)
        XCTAssertTrue(richContent.isHidden)

        message.text = source + "\n\nUpdated just now"
        cell.updateStreamingMessage(message)
        cell.layoutIfNeeded()
        XCTAssertFalse(richContent.isHidden)
        XCTAssertTrue(richContent.displayText.contains("USDT"))
        XCTAssertFalse(revealView.isHidden)
        XCTAssertEqual(revealView.displayText, "Updated just now")
    }

    func testNewsPostDrawsItsTableAsAnswersDo() throws {
        _ = WalletResourcesBundle.bundle.load()
        let code = "Run:\n```\nlet USDT = 1\n```"
        for (body, hasBlocks) in [(source, true), (code, true), ("Plain news text", false)] {
            let post = AgentNewsPostView()
            post.configure(with: AgentNewsPostView.Content(news: ApiAgentV2ThreadNewsCard(
                eventId: 1,
                headline: "Headline",
                excerpt: nil,
                imageUrl: nil,
                publishedAt: "2026-11-05T08:00:00Z",
                source: nil,
                body: body,
                sources: nil
            )), isHeaderVisible: true)
            post.updateTextMaxWidth(forBubbleWidth: 360)
            post.layoutIfNeeded()

            let richContent = try XCTUnwrap(descendants(of: post).compactMap { $0 as? AgentRichMessageView }.first)
            XCTAssertEqual(richContent.isHidden, !hasBlocks)
            XCTAssertEqual(richContent.displayText.contains("USDT"), hasBlocks)
            let isBodyLabelShown = descendants(of: post).contains {
                ($0 as? UILabel)?.attributedText?.string == body && !$0.isHidden
            }
            XCTAssertEqual(isBodyLabelShown, !hasBlocks)
            // The body drawn once the width is known reaches VoiceOver too
            XCTAssertEqual(post.accessibilityContentElement.accessibilityLabel?.contains("USDT"), hasBlocks)
        }
    }

    private func assertTableLayout(_ cell: AgentMessageCell, width: CGFloat, file: StaticString = #filePath, line: UInt = #line) throws {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.size = CGSize(width: width, height: 80)
        let fitted = cell.preferredLayoutAttributesFitting(attributes)
        cell.frame.size = fitted.size
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        let richContent = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? AgentRichMessageView }.first)
        XCTAssertEqual(fitted.size.width, width, accuracy: 0.5, file: file, line: line)
        XCTAssertFalse(richContent.isHidden, file: file, line: line)
        XCTAssertGreaterThan(richContent.bounds.width, 200, file: file, line: line)
        XCTAssertLessThanOrEqual(richContent.bounds.width, min(width, 580) - 60, file: file, line: line)
        let introduction = try XCTUnwrap(descendants(of: richContent).compactMap { $0 as? UITextView }.first { $0.text.hasPrefix("Вот ваши активы") })
        XCTAssertLessThan(introduction.bounds.height, 100, file: file, line: line)
        XCTAssertLessThan(fitted.size.height, 350, file: file, line: line)
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

/// Code and tables as Telegram draws them in an incoming message, in the accent and in greys over the bubble
@MainActor
final class AgentMessageCodeAndTableStyleTests: XCTestCase {
    func testFencesStandApartWithTheirLanguageIfAny() {
        let blocks = AgentMessageBlockParser.separatingCode([
            .text("Run this:\n```swift\nlet a = 1\nprint(a)\n```\nThen\n```\nplain\n```\n```js\nopen"),
        ])

        XCTAssertEqual(blocks, [
            .text("Run this:"),
            .code(AgentMessageCode(language: "swift", text: "let a = 1\nprint(a)")),
            .text("Then"),
            .code(AgentMessageCode(language: nil, text: "plain")),
            .code(AgentMessageCode(language: "js", text: "open")),
        ])
    }

    func testAnswerLinkInsideCodeStaysItsLabel() {
        let source = "See docs\n```\nopen docs now\n```"
        let marked = AgentTextLinks.mark(source, links: [
            ApiAgentV2AnswerLink(textOffset: 4, textLength: 4, url: "https://example.com/a"),
            ApiAgentV2AnswerLink(textOffset: 18, textLength: 4, url: "https://example.com/b"),
        ], tableOffsets: []).text

        let blocks = AgentMessageBlockParser.separatingCode([.text(marked)])

        XCTAssertEqual(blocks.last, .code(AgentMessageCode(language: nil, text: "open docs now")))
    }

    func testCodeTakesTheAccentWithoutABackground() throws {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            "Call `swap()` now\n```swift\nlet a = 1\n```",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1,
            linkColor: .systemPink
        )
        let string = rendered.string as NSString

        for code in ["swap()", "let a = 1"] {
            let attributes = rendered.attributes(at: string.range(of: code).location, effectiveRange: nil)
            XCTAssertEqual(attributes[.foregroundColor] as? UIColor, .systemPink, code)
            XCTAssertNil(attributes[.backgroundColor], code)
            let font = try XCTUnwrap(attributes[.font] as? UIFont)
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace), code)
        }
        XCTAssertEqual(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .label)
    }

    /// A fence still open while the answer arrives shows its lines as code: 2 pt under the body, in the accent, on
    /// lines 1.5 times the code's size without gaps between them, an empty one as tall as the others
    func testOpenFenceArrivingShowsItsLinesAsCode() throws {
        let rendered = AgentMessageTextRenderer.makeAttributedText(
            "Run:\n```swift\nlet a = 1\n\nprint(",
            textColor: .label,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1,
            isStreaming: true,
            baseFont: .systemFont(ofSize: 17),
            linkColor: .systemPink
        )
        let string = rendered.string as NSString

        XCTAssertEqual(rendered.string, "Run:\nlet a = 1\n\nprint(")
        let codeLineHeight = ceil(15 * 1.5)
        for line in ["let a = 1", "print("] {
            let attributes = rendered.attributes(at: string.range(of: line).location, effectiveRange: nil)
            XCTAssertEqual((attributes[.font] as? UIFont)?.pointSize, 15, line)
            XCTAssertEqual(attributes[.foregroundColor] as? UIColor, .systemPink, line)
            let style = try XCTUnwrap(attributes[.paragraphStyle] as? NSParagraphStyle)
            XCTAssertEqual(style.minimumLineHeight, codeLineHeight, line)
            XCTAssertEqual(style.paragraphSpacing, 0, line)
        }
        let emptyLine = string.range(of: "\n\n").location + 1
        let emptyStyle = try XCTUnwrap(rendered.attribute(.paragraphStyle, at: emptyLine, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(emptyStyle.minimumLineHeight, codeLineHeight)
    }

    func testCodeBlockStripNamesTheLanguageOrCopy() {
        XCTAssertEqual(AgentCodeBlockView.makeTitle(language: "swift"), "swift")
        XCTAssertEqual(AgentCodeBlockView.makeTitle(language: nil), lang("Copy"))
        XCTAssertEqual(AgentCodeBlockView.makeTitle(language: " "), lang("Copy"))
    }

    func testCodeBlockColorsFollowTheAccentAndTheTheme() {
        let accent = UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        let light = AgentCodeBlockView.Colors.make(accent: accent, isDark: false)
        let dark = AgentCodeBlockView.Colors.make(accent: accent, isDark: true)

        XCTAssertEqual(light.background, accent.withAlphaComponent(0.12))
        XCTAssertEqual(dark.background, UIColor.black.withAlphaComponent(0.75))
        for colors in [light, dark] {
            XCTAssertEqual(colors.bar, accent.withAlphaComponent(0.9))
            XCTAssertEqual(colors.header, accent.withAlphaComponent(0.3))
            XCTAssertEqual(colors.title, accent)
            XCTAssertEqual(colors.copyIcon, accent.withAlphaComponent(0.6))
            XCTAssertEqual(colors.code, accent)
        }
    }

    func testCodeBlockStripCopiesTheCode() throws {
        let view = AgentCodeBlockView()
        view.configure(code: AgentMessageCode(language: "swift", text: "let a = 1"), baseFont: .systemFont(ofSize: 17))
        var copyCount = 0
        view.onCopy = { copyCount += 1 }
        let strip = try XCTUnwrap(view.subviews.compactMap { $0 as? UIControl }.first)

        XCTAssertEqual(strip.accessibilityLabel, lang("Copy"))
        let action = try XCTUnwrap(strip.actions(forTarget: view, forControlEvent: .touchUpInside)?.first)
        view.perform(NSSelectorFromString(action))
        XCTAssertEqual(copyCount, 1)
        XCTAssertEqual(view.codeLabel.text, "let a = 1")
        XCTAssertEqual((view.codeLabel.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize, 15)
    }

    func testTableShadesItsHeaderAndBordersOverTheBubbleInEachTheme() {
        for (style, white) in [(UIUserInterfaceStyle.light, CGFloat(0)), (.dark, 1)] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for (color, alpha) in [(AgentTableColors.headerFill, CGFloat(0.05)), (AgentTableColors.border, 0.12)] {
                var resolvedWhite: CGFloat = -1
                var resolvedAlpha: CGFloat = -1
                XCTAssertTrue(color.resolvedColor(with: traits).getWhite(&resolvedWhite, alpha: &resolvedAlpha))
                XCTAssertEqual(resolvedWhite, white, accuracy: 0.01)
                XCTAssertEqual(resolvedAlpha, alpha, accuracy: 0.001)
            }
        }
    }

    func testAnswerWithCodeShowsItsCodeBlockInTheRichView() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 80))
        let message = AgentMessage(
            role: .assistant,
            text: "Run:\n```swift\nlet a = 1\n```",
            isStreaming: false,
            renderingPolicy: .agentV2Safe
        )
        cell.configure(with: message, onURLTap: { _ in })
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.size = CGSize(width: 402, height: 80)
        cell.frame.size = cell.preferredLayoutAttributesFitting(attributes).size
        cell.layoutIfNeeded()

        let richContent = try XCTUnwrap(descendants(of: cell).compactMap { $0 as? AgentRichMessageView }.first)
        XCTAssertFalse(richContent.isHidden)
        let codeBlock = try XCTUnwrap(descendants(of: richContent).compactMap { $0 as? AgentCodeBlockView }.first)
        XCTAssertEqual(codeBlock.codeLabel.text, "let a = 1")
        XCTAssertEqual(richContent.displayText, "Run:\nlet a = 1")
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
