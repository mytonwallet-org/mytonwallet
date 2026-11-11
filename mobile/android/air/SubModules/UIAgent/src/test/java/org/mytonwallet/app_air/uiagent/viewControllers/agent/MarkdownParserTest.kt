package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MarkdownParserTest {

    @Test
    fun `html table only displays approved link targets`() {
        val table = MarkdownParser.parseBlocks(
            """
                <table>
                <tr><td><a href="javascript:alert(1)">Script</a></td><td><a href="intent://scan">Intent</a></td></tr>
                <tr><td><a href="https://tonviewer.com">Web</a></td><td><a href="mtw://wallet">Wallet</a></td></tr>
                </table>
            """.trimIndent()
        ).filterIsInstance<MarkdownParser.Block.Table>().single()

        assertEquals(
            listOf(
                listOf("Script", "Intent"),
                listOf("Web (https://tonviewer.com)", "Wallet (mtw://wallet)")
            ),
            table.rows.map { row -> row.map(MarkdownParser.TableCell::text) }
        )
    }

    @Test
    fun `headings take their level and text without their marks`() {
        assertEquals(MarkdownParser.Heading(1, "Title"), MarkdownParser.parseHeading("# Title #"))
        assertEquals(
            MarkdownParser.Heading(2, "Section with **bold**"),
            MarkdownParser.parseHeading("   ## Section with **bold**  ")
        )
        assertEquals(
            MarkdownParser.Heading(6, "Small"),
            MarkdownParser.parseHeading("###### Small")
        )
        listOf("####### Seven", "#NoSpace", "    # Indented code", "\\# Escaped").forEach {
            assertNull(it, MarkdownParser.parseHeading(it))
        }
    }

    @Test
    fun `heading marks still arriving wait for their text`() {
        listOf("#", "##", "## ").forEach { assertNull(it, MarkdownParser.parseHeading(it)) }
        listOf("#", "##", "## ", "## **").forEach {
            assertTrue(it, MarkdownParser.isHeadingMarks(it))
        }
        listOf("## T", "#hashtag", "####### ").forEach {
            assertFalse(it, MarkdownParser.isHeadingMarks(it))
        }
        assertEquals(MarkdownParser.Heading(2, "T"), MarkdownParser.parseHeading("## T"))
    }

    @Test
    fun `list markers still arriving wait for their text`() {
        // A bullet whose bold text has not come in yet, as an answer streams it, shows neither
        listOf("-", "- ", "- **", "* ", "+ `", "1.", "12. **").forEach {
            assertTrue(it, MarkdownParser.isListMarks(it))
        }
        // Once its text comes, the item shows, its bold closed or still open
        listOf("- **Low**", "- **Lo", "1. Step", "**", "-1", "Plain").forEach {
            assertFalse(it, MarkdownParser.isListMarks(it))
        }
    }

    @Test
    fun `fences stand apart as code blocks with their language`() {
        val blocks = MarkdownParser.parseBlocks(
            "Run:\n```swift\nlet a = 1\n\nprint(a)\n```\n" +
                "Then\n```\n| A | B |\n| --- | --- |\n```\n" +
                "```js\nopen("
        )

        assertEquals(
            listOf(
                MarkdownParser.Block.Text("Run:"),
                MarkdownParser.Block.Code("swift", "let a = 1\n\nprint(a)"),
                MarkdownParser.Block.Text("Then"),
                MarkdownParser.Block.Code(null, "| A | B |\n| --- | --- |"),
                MarkdownParser.Block.Code("js", "open(")
            ),
            blocks
        )
    }
}
