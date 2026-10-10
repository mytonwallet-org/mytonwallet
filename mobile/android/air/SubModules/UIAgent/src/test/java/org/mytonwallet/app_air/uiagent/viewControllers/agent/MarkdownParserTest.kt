package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
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
}
