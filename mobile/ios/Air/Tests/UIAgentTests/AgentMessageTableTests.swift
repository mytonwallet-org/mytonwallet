import XCTest
@testable import UIAgent

final class AgentMessageTableTests: XCTestCase {
    func testPlainTextKeepsSingleBlockPath() {
        let source = "Balance: **125 TON**\nNo table here."

        XCTAssertEqual(AgentMessageBlockParser.parse(source), [.text(source)])
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
