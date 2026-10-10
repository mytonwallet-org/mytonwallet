package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.LeadingMarginSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.text.style.TabStopSpan
import android.text.style.TypefaceSpan
import android.util.Patterns
import kotlin.math.ceil
import org.mytonwallet.app_air.uiagent.agentV2.AgentTextLinks
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.walletbasecontext.APP_SCHEME

object MarkdownParser {

    enum class TableAlignment {
        START,
        CENTER,
        END
    }

    enum class TableVerticalAlignment {
        TOP,
        MIDDLE,
        BOTTOM
    }

    data class TableCell(
        val text: String,
        val header: Boolean = false,
        val isPlainText: Boolean = false,
        val alignment: TableAlignment = TableAlignment.START,
        val verticalAlignment: TableVerticalAlignment = TableVerticalAlignment.TOP,
        val columnSpan: Int = 1,
        val rowSpan: Int = 1
    )

    data class PlacedTableCell(val cell: TableCell, val row: Int, val column: Int)

    data class TableGrid(val cells: List<PlacedTableCell>, val rowCount: Int, val columnCount: Int)

    sealed interface Block {
        data class Text(val value: String) : Block

        data class Table(
            val rows: List<List<TableCell>>,
            val title: String? = null,
            val bordered: Boolean = true,
            val striped: Boolean = false
        ) : Block
    }

    private class PassiveLinkSpan

    private val urlPattern: Regex by lazy { Patterns.WEB_URL.toRegex() }

    /** ASCII punctuation that a backslash escapes, as the agent writes it and the server escapes link labels */
    internal const val ESCAPABLE_CHARACTERS = "\\`*_{}[]()<>#+-.!~|="
    private val htmlTableOpenPattern = Regex("(?i)<\\s*table(?:\\s|>|$)")
    private val htmlTableClosePattern = Regex("(?i)</\\s*table\\s*>")
    private val htmlTableTokenPattern = Regex(
        "(?is)<\\s*(/?)\\s*(table|caption|thead|tbody|tfoot|tr|td|th|br)\\b([^>]*)>"
    )
    private val htmlAttributePattern = Regex(
        "(?i)([a-z_:][a-z0-9_.:-]*)(?:\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+)))?"
    )
    private val htmlBreakPattern = Regex("(?i)<\\s*br\\s*/?\\s*>")
    private val htmlLinkPattern = Regex("(?is)<\\s*a\\b([^>]*)>(.*?)</\\s*a\\s*>")
    private val htmlBoldPattern = Regex(
        "(?is)<\\s*(?:b|strong)\\b[^>]*>(.*?)</\\s*(?:b|strong)\\s*>"
    )
    private val htmlItalicPattern = Regex(
        "(?is)<\\s*(?:i|em)\\b[^>]*>(.*?)</\\s*(?:i|em)\\s*>"
    )
    private val htmlCodePattern = Regex("(?is)<\\s*code\\b[^>]*>(.*?)</\\s*code\\s*>")
    private val htmlTagPattern = Regex("(?is)<[^>]+>")
    private val numericHtmlEntityPattern = Regex("&#(?:x([0-9a-fA-F]+)|([0-9]+));")
    private val tableDelimiterPattern = Regex("^:?-{3,}:?$")

    private val listPrefixPattern = Regex("^([-+*]|([0-9]+)[.)])[\\t ]+")
    private val codeFencePattern = Regex("^[\\t ]*```[^`]*$")
    private val markdownLinkPattern = Regex(
        """\[((?:\\.|[^\]\\\n])+)\]\(((?:https?://|mtw://)(?:\\.|[^()\\\s]|\((?:\\.|[^()\\\s])*\))+)\)"""
    )

    fun parseBlocks(text: String): List<Block> {
        val blocks = mutableListOf<Block>()
        var textStart = 0
        var searchIndex = 0
        var inCodeBlock = false

        while (searchIndex < text.length) {
            val fenceIndex = text.indexOf("```", searchIndex).takeIf { it >= 0 }
            val tableMatch = htmlTableOpenPattern.find(text, searchIndex)
            if (fenceIndex != null && (tableMatch == null || fenceIndex < tableMatch.range.first)) {
                inCodeBlock = !inCodeBlock
                searchIndex = fenceIndex + 3
                continue
            }
            if (tableMatch == null) break
            if (inCodeBlock) {
                searchIndex = tableMatch.range.last + 1
                continue
            }

            val openingEnd = text.indexOf('>', tableMatch.range.first)
            if (openingEnd < 0) break
            val closingMatch = htmlTableClosePattern.find(text, openingEnd + 1)
            if (closingMatch == null) break
            val tableEnd = closingMatch.range.last + 1
            val table = parseHtmlTable(text.substring(tableMatch.range.first, tableEnd))
            if (table == null) {
                searchIndex = tableEnd
                continue
            }

            addMarkdownBlocks(text.substring(textStart, tableMatch.range.first), blocks)
            blocks.add(table)
            textStart = tableEnd
            searchIndex = tableEnd
        }

        addMarkdownBlocks(text.substring(textStart), blocks)
        return blocks.ifEmpty { listOf(Block.Text(text)) }
    }

    fun resolveTableGrid(table: Block.Table): TableGrid {
        val cells = mutableListOf<PlacedTableCell>()
        val occupiedUntilRow = mutableMapOf<Int, Int>()
        var columnCount = 0
        var rowCount = table.rows.size

        table.rows.forEachIndexed { rowIndex, row ->
            var column = 0
            row.forEach { cell ->
                val columnSpan = cell.columnSpan.coerceAtLeast(1)
                val rowSpan = cell.rowSpan.coerceAtLeast(1)
                while ((column until column + columnSpan).any {
                        occupiedUntilRow.getOrDefault(it, 0) > rowIndex
                    }
                ) {
                    column++
                }

                cells.add(PlacedTableCell(cell, rowIndex, column))
                for (occupiedColumn in column until column + columnSpan) {
                    occupiedUntilRow[occupiedColumn] = rowIndex + rowSpan
                }
                column += columnSpan
                columnCount = maxOf(columnCount, column)
                rowCount = maxOf(rowCount, rowIndex + rowSpan)
            }
        }

        return TableGrid(cells, rowCount, columnCount)
    }

    private fun addMarkdownBlocks(text: String, blocks: MutableList<Block>) {
        if (text.isEmpty()) return
        val lines = text.split('\n')
        val textLines = mutableListOf<String>()
        var inCodeBlock = false
        var lineIndex = 0

        fun flushText() {
            val value = textLines.joinToString("\n").trim('\n', '\r')
            if (value.isNotEmpty()) blocks.add(Block.Text(value))
            textLines.clear()
        }

        while (lineIndex < lines.size) {
            val line = lines[lineIndex].trimEnd('\r')
            if (line.trimStart().startsWith("```")) {
                inCodeBlock = !inCodeBlock
                textLines.add(line)
                lineIndex++
                continue
            }

            val table = if (!inCodeBlock && lineIndex + 1 < lines.size) {
                parseTable(lines, lineIndex)
            } else {
                null
            }
            if (table == null) {
                textLines.add(line)
                lineIndex++
                continue
            }

            flushText()
            blocks.add(table.block)
            lineIndex = table.nextLineIndex
        }
        flushText()
    }

    /**
     * Renders Markdown with answer links marked by `AgentTextLinks` as link spans. `detectsUrls` also links bare
     * URLs, which an answer from the server carries as answer links instead.
     */
    fun parse(
        text: String,
        codeColor: Int,
        linkColor: Int?,
        onUrlClick: ((String) -> Unit)? = null,
        detectsUrls: Boolean = true,
        textSize: Float = 16f,
        isStreaming: Boolean = false
    ): SpannableStringBuilder {
        val lines = stripHtmlTableMarkupForDisplay(text)
            .replace("\r\n", "\n").replace('\r', '\n').split('\n')
        val result = SpannableStringBuilder()
        var index = 0
        while (index < lines.size) {
            if (index > 0) result.append('\n')
            val line = lines[index]
            if (codeFencePattern.matches(line)) {
                val codeLines = mutableListOf<String>()
                index++
                while (index < lines.size && lines[index].trim() != "```") {
                    codeLines.add(lines[index++])
                }
                val start = result.length
                result.append(codeLines.joinToString("\n"))
                applyCodeSpan(result, start, result.length, codeColor)
                if (index < lines.size) index++
                continue
            }
            val isArriving = isStreaming && index == lines.lastIndex
            if (isArriving && line in listOf("-", "+", "*")) {
                index++
                continue
            }
            val prefix = listPrefixPattern.find(line)
                ?.takeIf { isArriving || line.substring(it.value.length).isNotBlank() }
            val start = result.length
            if (prefix != null) {
                val number = prefix.groupValues[2]
                result.append(if (number.isEmpty()) "•\t" else "$number.\t")
            }
            result.append(
                parseInline(
                    if (prefix == null) line else line.substring(prefix.value.length),
                    codeColor,
                    linkColor,
                    onUrlClick,
                    detectsUrls,
                    isArriving
                )
            )
            if (prefix != null) {
                val indent = ceil(textSize * 1.5f).toInt()
                result.setSpan(
                    LeadingMarginSpan.Standard(0, indent),
                    start,
                    result.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                result.setSpan(
                    TabStopSpan.Standard(indent),
                    start,
                    result.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            index++
        }
        applyAnswerLinks(result, linkColor, onUrlClick)
        if (onUrlClick != null && detectsUrls) applyUrlSpans(result, linkColor, onUrlClick)
        return result
    }

    private fun applyAnswerLinks(
        sb: SpannableStringBuilder,
        linkColor: Int?,
        onClick: ((String) -> Unit)?
    ) {
        val delete: (Int, Int) -> Unit = { start, end -> sb.delete(start, end) }
        // `parse` has already read the escapes in the text, labels included
        AgentTextLinks.resolve(sb, removesLabelEscapes = false, delete) { start, end, url ->
            if (onClick != null && sb.getSpans(start, end, TypefaceSpan::class.java)
                    .none { it.family == "monospace" }
            ) {
                sb.setSpan(
                    WClickableSpan(url, linkColor, onClick),
                    start,
                    end,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
        }
    }

    private fun applyUrlSpans(
        sb: SpannableStringBuilder,
        linkColor: Int? = null,
        onClick: (String) -> Unit
    ) {
        val text = sb.toString()
        for (match in urlPattern.findAll(text)) {
            val matchStart = match.range.first
            val matchEnd = match.range.last + 1

            val isInsideCode = sb.getSpans(matchStart, matchEnd, TypefaceSpan::class.java)
                .any { it.family == "monospace" }
            if (isInsideCode) continue
            if (sb.getSpans(matchStart, matchEnd, WClickableSpan::class.java).isNotEmpty() ||
                sb.getSpans(matchStart, matchEnd, PassiveLinkSpan::class.java).isNotEmpty()
            ) {
                continue
            }

            var url = match.value
            if (!url.startsWith("http://", ignoreCase = true) &&
                !url.startsWith("https://", ignoreCase = true)
            ) {
                url = "https://$url"
            }
            if (!AgentTextLinks.isOpenable(url)) continue
            sb.setSpan(
                WClickableSpan(url, linkColor, onClick),
                matchStart,
                matchEnd,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    private fun parseInline(
        text: String,
        codeColor: Int,
        linkColor: Int?,
        onUrlClick: ((String) -> Unit)?,
        detectsUrls: Boolean,
        isArriving: Boolean
    ): SpannableStringBuilder {
        val result = SpannableStringBuilder()
        var i = 0
        while (i < text.length) {
            if (isEscapeAt(text, i)) {
                result.append(text[i + 1])
                i += 2
                continue
            }
            if (isArriving && (text[i] == '*' || text[i] == '`') &&
                text.substring(i).all { it == '*' || it == '`' }
            ) {
                break
            }
            val link = markdownLinkPattern.matchAt(text, i)
            if (link != null && i > 0 && text[i - 1] == '!') {
                val start = result.length
                result.append(link.value)
                result.setSpan(
                    PassiveLinkSpan(),
                    start,
                    result.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                i += link.value.length
                continue
            }
            if (link != null) {
                val label =
                    parseInline(link.groupValues[1], codeColor, linkColor, null, false, false)
                val destination = removeMarkdownEscapes(link.groupValues[2])
                val start = result.length
                result.append(label)
                if (!destination.startsWith("mtw://")) {
                    if (detectsUrls && onUrlClick != null &&
                        AgentTextLinks.isOpenable(destination)
                    ) {
                        result.setSpan(
                            WClickableSpan(destination, linkColor, onUrlClick),
                            start,
                            result.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                        )
                    } else {
                        val passiveStart = result.length
                        result.append(" ($destination)")
                        result.setSpan(
                            PassiveLinkSpan(),
                            passiveStart,
                            result.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                        )
                    }
                }
                i += link.value.length
                continue
            }
            val marker = when {
                text[i] == '`' -> "`"
                text.startsWith("**", i) -> "**"
                text[i] == '*' && (i == 0 || !text[i - 1].isLetterOrDigit()) -> "*"
                else -> null
            }
            if (marker != null) {
                val contentStart = i + marker.length
                val end = if (marker == "`") {
                    indexOfUnescaped(text, marker, contentStart)
                } else {
                    indexOfStyleEnd(text, marker, contentStart)
                }
                val hasContent = contentStart < text.length &&
                    (marker == "`" || !text[contentStart].isWhitespace())
                if (hasContent && (end > contentStart || (isArriving && end < 0))) {
                    val contentEnd = if (end < 0) text.length else end
                    val content = text.substring(contentStart, contentEnd)
                    val start = result.length
                    if (marker == "`") {
                        result.append(removeMarkdownEscapes(content))
                        applyCodeSpan(result, start, result.length, codeColor)
                    } else {
                        result.append(
                            parseInline(
                                content,
                                codeColor,
                                linkColor,
                                onUrlClick,
                                detectsUrls,
                                isArriving && end < 0
                            )
                        )
                        result.setSpan(
                            StyleSpan(
                                if (marker ==
                                    "**"
                                ) {
                                    Typeface.BOLD
                                } else {
                                    Typeface.ITALIC
                                }
                            ),
                            start,
                            result.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                        )
                    }
                    i = if (end < 0) text.length else end + marker.length
                    continue
                }
            }
            result.append(text[i++])
        }
        return result
    }

    private fun indexOfStyleEnd(text: String, marker: String, from: Int): Int {
        var index = from
        while (index < text.length) {
            if (isEscapeAt(text, index)) {
                index += 2
            } else if (text[index] == '`') {
                val end = indexOfUnescaped(text, "`", index + 1)
                index = if (end < 0) index + 1 else end + 1
            } else if (text[index] == '*') {
                var end = index + 1
                while (end < text.length && text[end] == '*') end++
                val count = end - index
                if (marker == "**" && count >= 2) return index + count % 2
                if (marker == "*" && count % 2 == 1) return end - 1
                index = end
            } else {
                index++
            }
        }
        return -1
    }

    private fun removeMarkdownEscapes(text: String): String = buildString {
        var index = 0
        while (index < text.length) {
            if (isEscapeAt(text, index)) index++
            append(text[index++])
        }
    }

    private fun isEscapeAt(text: String, index: Int) =
        text[index] == '\\' && index + 1 < text.length && text[index + 1] in ESCAPABLE_CHARACTERS

    /** The index of `delimiter` in `text` from `from` that no backslash escapes, or -1 */
    private fun indexOfUnescaped(text: String, delimiter: String, from: Int): Int {
        var index = text.indexOf(delimiter, from)
        while (index > 0 && isEscaped(text, index)) index = text.indexOf(delimiter, index + 1)
        return index
    }

    private fun isEscaped(text: String, index: Int): Boolean {
        var backslashes = 0
        while (index - backslashes > 0 && text[index - backslashes - 1] == '\\') backslashes++
        return backslashes % 2 == 1
    }

    private fun applyCodeSpan(sb: SpannableStringBuilder, start: Int, end: Int, color: Int) {
        sb.setSpan(
            TypefaceSpan("monospace"),
            start,
            end,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        sb.setSpan(
            RelativeSizeSpan(0.9f),
            start,
            end,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        sb.setSpan(
            ForegroundColorSpan(color),
            start,
            end,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }

    private fun stripHtmlTableMarkupForDisplay(source: String): String {
        if (!htmlTableOpenPattern.containsMatchIn(source)) return source

        val result = StringBuilder(source.length)
        var index = 0
        var inCodeBlock = false
        var inTable = false
        while (index < source.length) {
            if (!inTable && source.startsWith("```", index)) {
                inCodeBlock = !inCodeBlock
                result.append("```")
                index += 3
                continue
            }
            if (!inCodeBlock && source[index] == '<') {
                if (!inTable && htmlTableOpenPattern.matchAt(source, index) != null) inTable = true
                if (inTable) {
                    val tag = appendHtmlTableDisplayTag(source, index, result) ?: break
                    inTable = !tag.closesTable
                    index = tag.nextIndex
                    continue
                }
            }
            result.append(source[index])
            index++
        }
        return result.toString()
    }

    private data class HtmlTableDisplayTag(val nextIndex: Int, val closesTable: Boolean)

    private fun appendHtmlTableDisplayTag(
        source: String,
        index: Int,
        result: StringBuilder
    ): HtmlTableDisplayTag? {
        val tagEnd = source.indexOf('>', index)
        if (tagEnd < 0) return null
        val tag = source.substring(index + 1, tagEnd).trim().lowercase()
        val closing = tag.startsWith('/')
        val name = tag
            .removePrefix("/")
            .substringBefore(' ')
            .removeSuffix("/")
        when {
            name == "br" -> result.append('\n')
            closing && name == "caption" -> result.append('\n')
            closing && (name == "td" || name == "th") -> result.append("  ")
            closing && name == "tr" -> result.append('\n')
        }
        return HtmlTableDisplayTag(
            nextIndex = tagEnd + 1,
            closesTable = closing && name == "table"
        )
    }

    private data class ParsedTable(val block: Block.Table, val nextLineIndex: Int)

    private fun parseTable(lines: List<String>, headerIndex: Int): ParsedTable? {
        val headerLine = lines[headerIndex].trimEnd('\r')
        if (!hasUnescapedPipe(headerLine)) return null

        val header = splitTableRow(headerLine)
        val delimiter = splitTableRow(lines[headerIndex + 1].trimEnd('\r'))
        if (delimiter.size != header.size) return null
        val alignments = delimiter.map { parseAlignment(it) ?: return null }

        val rows = mutableListOf<List<TableCell>>()
        rows.add(
            header.mapIndexed { index, value ->
                TableCell(
                    text = value,
                    header = true,
                    alignment = alignments[index]
                )
            }
        )
        var index = headerIndex + 2
        while (index < lines.size) {
            val rowLine = lines[index].trimEnd('\r')
            if (rowLine.isBlank() || !hasUnescapedPipe(rowLine)) break
            val cells = splitTableRow(rowLine)
            rows.add(
                List(header.size) { column ->
                    TableCell(
                        text = cells.getOrElse(column) { "" },
                        alignment = alignments[column]
                    )
                }
            )
            index++
        }

        return ParsedTable(
            Block.Table(
                rows = rows
            ),
            nextLineIndex = index
        )
    }

    private fun parseAlignment(value: String): TableAlignment? {
        val marker = value.trim()
        if (!marker.matches(tableDelimiterPattern)) return null
        return when {
            marker.startsWith(':') && marker.endsWith(':') -> TableAlignment.CENTER
            marker.endsWith(':') -> TableAlignment.END
            else -> TableAlignment.START
        }
    }

    private fun hasUnescapedPipe(line: String): Boolean {
        var escaped = false
        for (char in line) {
            when {
                escaped -> escaped = false
                char == '\\' -> escaped = true
                char == '|' -> return true
            }
        }
        return false
    }

    private fun splitTableRow(line: String): List<String> {
        val trimmed = line.trim()
        val content = trimmed
            .removePrefix("|")
            .removeSuffix("|")
        val cells = mutableListOf<String>()
        val cell = StringBuilder()
        var escaped = false
        for (char in content) {
            when {
                escaped -> {
                    if (char != '|') cell.append('\\')
                    cell.append(char)
                    escaped = false
                }

                char == '\\' -> escaped = true

                char == '|' -> {
                    cells.add(cell.toString().trim())
                    cell.clear()
                }

                else -> cell.append(char)
            }
        }
        if (escaped) cell.append('\\')
        cells.add(cell.toString().trim())
        return cells
    }

    private data class HtmlCellDraft(
        val header: Boolean,
        val alignment: TableAlignment,
        val verticalAlignment: TableVerticalAlignment,
        val columnSpan: Int,
        val rowSpan: Int,
        val content: StringBuilder = StringBuilder()
    )

    private fun parseHtmlTable(source: String): Block.Table? {
        val tokens = htmlTableTokenPattern.findAll(source).toList()
        if (tokens.isEmpty()) return null

        val tableAttributes = parseHtmlAttributes(tokens.first().groupValues[3])
        val rows = mutableListOf<List<TableCell>>()
        var currentRow: MutableList<TableCell>? = null
        var currentCell: HtmlCellDraft? = null
        var caption: StringBuilder? = null
        var title: String? = null
        var previousEnd = 0

        fun appendContent(value: String) {
            when {
                currentCell != null -> currentCell?.content?.append(value)
                caption != null -> caption?.append(value)
            }
        }

        fun finishCell() {
            val cell = currentCell ?: return
            currentRow?.add(
                TableCell(
                    text = sanitizeInlineHtml(cell.content.toString()),
                    header = cell.header,
                    alignment = cell.alignment,
                    verticalAlignment = cell.verticalAlignment,
                    columnSpan = cell.columnSpan,
                    rowSpan = cell.rowSpan
                )
            )
            currentCell = null
        }

        fun finishRow() {
            finishCell()
            currentRow?.takeIf { it.isNotEmpty() }?.let(rows::add)
            currentRow = null
        }

        tokens.forEach { token ->
            appendContent(source.substring(previousEnd, token.range.first))
            previousEnd = token.range.last + 1
            val closing = token.groupValues[1].isNotEmpty()
            val tag = token.groupValues[2].lowercase()
            val attributes = parseHtmlAttributes(token.groupValues[3])

            when (tag) {
                "caption" -> if (closing) {
                    title = caption?.let { sanitizeInlineHtml(it.toString()) }
                        ?.takeIf { it.isNotEmpty() }
                    caption = null
                } else {
                    caption = StringBuilder()
                }

                "tr" -> if (closing) {
                    finishRow()
                } else {
                    finishRow()
                    currentRow = mutableListOf()
                }

                "td", "th" -> if (closing) {
                    finishCell()
                } else if (currentRow != null) {
                    finishCell()
                    currentCell = HtmlCellDraft(
                        header = tag == "th" || attributes.containsKey("header"),
                        alignment = parseHtmlAlignment(attributes),
                        verticalAlignment = parseHtmlVerticalAlignment(attributes["valign"]),
                        columnSpan = parseHtmlSpan(attributes["colspan"]),
                        rowSpan = parseHtmlSpan(attributes["rowspan"])
                    )
                }

                "br" -> if (!closing) appendContent("\n")
            }
        }
        appendContent(source.substring(previousEnd))
        finishRow()

        if (rows.isEmpty()) return null
        val borderValue = tableAttributes["border"]
        return Block.Table(
            rows = rows,
            title = title,
            bordered = borderValue != null &&
                borderValue != "0" && !borderValue.equals("false", ignoreCase = true),
            striped = tableAttributes["class"]
                ?.split(Regex("\\s+"))
                ?.any { it.equals("striped", ignoreCase = true) } == true
        )
    }

    private fun parseHtmlAttributes(source: String): Map<String, String> = buildMap {
        htmlAttributePattern.findAll(source).forEach { match ->
            val value = match.groupValues.drop(2).firstOrNull { it.isNotEmpty() }.orEmpty()
            put(match.groupValues[1].lowercase(), decodeHtmlEntities(value))
        }
    }

    private fun parseHtmlAlignment(attributes: Map<String, String>): TableAlignment {
        val alignment = attributes["align"] ?: attributes["style"]
            ?.lowercase()
            ?.substringAfter("text-align", "")
            ?.substringAfter(':', "")
            ?.substringBefore(';')
        return when (alignment?.trim()?.lowercase()) {
            "center" -> TableAlignment.CENTER
            "right", "end" -> TableAlignment.END
            else -> TableAlignment.START
        }
    }

    private fun parseHtmlVerticalAlignment(value: String?): TableVerticalAlignment = when (
        value?.trim()?.lowercase()
    ) {
        "middle", "center" -> TableVerticalAlignment.MIDDLE
        "bottom" -> TableVerticalAlignment.BOTTOM
        else -> TableVerticalAlignment.TOP
    }

    private fun parseHtmlSpan(value: String?): Int = value
        ?.toIntOrNull()
        ?.coerceIn(1, 32)
        ?: 1

    private fun sanitizeInlineHtml(source: String): String {
        var result = htmlLinkPattern.replace(source) { match ->
            val label = match.groupValues[2]
            val href = sanitizeHtmlHref(
                parseHtmlAttributes(match.groupValues[1])["href"].orEmpty()
            )
            when {
                href.isEmpty() -> label
                label.trim() == href -> href
                else -> "$label ($href)"
            }
        }
        result = htmlBoldPattern.replace(result) { "**${it.groupValues[1]}**" }
        result = htmlItalicPattern.replace(result) { "*${it.groupValues[1]}*" }
        result = htmlCodePattern.replace(result) { "`${it.groupValues[1]}`" }
        result = htmlBreakPattern.replace(result, "\n")
        return decodeHtmlEntities(htmlTagPattern.replace(result, "")).trim()
    }

    private fun sanitizeHtmlHref(value: String): String {
        val href = value.trim()
        val schemeSeparator = href.indexOf("://")
        if (schemeSeparator <= 0) return ""

        val scheme = href.substring(0, schemeSeparator)
        val isApprovedScheme = scheme.equals("http", ignoreCase = true) ||
            scheme.equals("https", ignoreCase = true) ||
            scheme.equals("mytonwallet", ignoreCase = true) ||
            scheme.equals("mtw", ignoreCase = true) ||
            runCatching { scheme.equals(APP_SCHEME, ignoreCase = true) }.getOrDefault(false)
        return href.takeIf { isApprovedScheme }.orEmpty()
    }

    private fun decodeHtmlEntities(source: String): String {
        val named = source
            .replace("&nbsp;", " ", ignoreCase = true)
            .replace("&lt;", "<", ignoreCase = true)
            .replace("&gt;", ">", ignoreCase = true)
            .replace("&quot;", "\"", ignoreCase = true)
            .replace("&#39;", "'", ignoreCase = true)
            .replace("&amp;", "&", ignoreCase = true)
        return numericHtmlEntityPattern.replace(named) { match ->
            val codePoint = match.groupValues[1].takeIf { it.isNotEmpty() }
                ?.toIntOrNull(16)
                ?: match.groupValues[2].toIntOrNull()
            codePoint?.takeIf(Character::isValidCodePoint)
                ?.let { String(Character.toChars(it)) }
                ?: match.value
        }
    }
}
