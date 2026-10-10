package org.mytonwallet.app_air.uiagent.agentV2

import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentDeeplink
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessageRole
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Action
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerLink
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerTable
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerTableReference
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2DisplayTable
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2MessageContent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2PersistedMessage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2RunResult

internal val AgentV2RunResult.hasVisibleFailure
    get() = state != "completed" && state != "cancelled"

internal fun requiresAgentV2ThreadResync(code: String) =
    code == "thread_revision_conflict" || code == "run_replay_expired"

private val agentV2DateFormats = object : ThreadLocal<List<SimpleDateFormat>>() {
    override fun initialValue() = listOf(
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXX"
    ).map { pattern ->
        SimpleDateFormat(pattern, Locale.US).apply {
            isLenient = false
            timeZone = TimeZone.getTimeZone("UTC")
        }
    }
}

internal fun parseAgentV2Timestamp(value: String): Date? {
    agentV2DateFormats.get().orEmpty().forEach { formatter ->
        val position = ParsePosition(0)
        formatter.parse(value, position)?.let { date ->
            if (position.index == value.length) return date
        }
    }
    return null
}

/** The answer text with its tables spliced in and its links marked for `MarkdownParser` (`AgentTextLinks`) */
internal fun agentV2AnswerTableText(
    text: String,
    tables: List<AgentV2AnswerTable>,
    references: List<AgentV2AnswerTableReference>,
    links: List<AgentV2AnswerLink> = emptyList()
): String = buildString {
    val (source, placements) = placeAnswerTables(text, tables, references, links)
    var offset = 0
    placements.forEach { (textOffset, table) ->
        append(source.substring(offset, textOffset))
        append("\n\n").append(answerTableMarkdown(table.content)).append("\n\n")
        offset = textOffset
    }
    append(source.substring(offset))
}

/** The answer text with its links marked, and the tables that fit it in order with their offsets in that text */
private fun placeAnswerTables(
    text: String,
    tables: List<AgentV2AnswerTable>,
    references: List<AgentV2AnswerTableReference>,
    links: List<AgentV2AnswerLink>
): Pair<String, List<Pair<Int, AgentV2AnswerTable>>> {
    val marked = AgentTextLinks.mark(text, links, references.map { it.textOffset })
    var offset = 0
    val placements = references.mapIndexedNotNull { index, reference ->
        val textOffset = marked.tableOffsets[index]
        if (textOffset < offset || textOffset > marked.text.length) return@mapIndexedNotNull null
        val table =
            tables.firstOrNull { it.id == reference.tableId } ?: return@mapIndexedNotNull null
        offset = textOffset
        textOffset to table
    }
    return marked.text to placements
}

private fun answerTableMarkdown(content: AgentV2DisplayTable): String =
    (content.notes + tableMarkdown(content.headers, content.rows))
        .filter(String::isNotBlank).joinToString("\n\n")

private fun tableMarkdown(headers: List<String>, rows: List<List<String>>): String {
    if (rows.isEmpty()) return ""
    return buildList {
        add(tableLine(headers))
        add(tableLine(headers.map { "---" }))
        rows.forEach { add(tableLine(it)) }
    }.joinToString("\n")
}

private fun tableLine(cells: List<String>) =
    cells.joinToString(" | ", prefix = "| ", postfix = " |") { cell ->
        buildString {
            cell.forEach { char ->
                when {
                    char in "&<>|\\`*_[]!" -> append("&#").append(char.code).append(';')
                    char == '\n' || char == '\r' -> append(' ')
                    else -> append(char)
                }
            }
        }
    }

internal fun buildAgentV2MessageBlocks(
    messageText: String,
    tables: List<AgentV2AnswerTable>,
    references: List<AgentV2AnswerTableReference>,
    links: List<AgentV2AnswerLink> = emptyList()
): List<MarkdownParser.Block> = buildList {
    val (source, placements) = placeAnswerTables(messageText, tables, references, links)
    val text = StringBuilder()
    var offset = 0

    fun flushText() {
        val value = text.toString().trim('\n', '\r')
        if (value.isNotEmpty()) addAll(MarkdownParser.parseBlocks(value))
        text.clear()
    }

    placements.forEach { (textOffset, table) ->
        text.append(source.substring(offset, textOffset)).append("\n\n")
        text.append(table.content.notes.filter(String::isNotBlank).joinToString("\n\n"))
        if (table.content.rows.isNotEmpty()) {
            flushText()
            add(buildAnswerTableBlock(table.content))
        }
        text.append("\n\n")
        offset = textOffset
    }
    text.append(source.substring(offset))
    flushText()
}

private fun buildAnswerTableBlock(content: AgentV2DisplayTable): MarkdownParser.Block.Table {
    val rows = listOf(content.headers) + content.rows
    return MarkdownParser.Block.Table(
        rows = rows.mapIndexed { rowIndex, row ->
            List(content.headers.size) { column ->
                MarkdownParser.TableCell(
                    text = row.getOrElse(column) {
                        ""
                    }.replace('\n', ' ').replace('\r', ' ').trim(),
                    header = rowIndex == 0,
                    isPlainText = true
                )
            }
        }
    )
}

internal fun mapAgentV2Message(
    message: AgentV2PersistedMessage,
    actions: List<AgentV2Action> = message.actions.orEmpty()
): AgentMessage? {
    val markdown = message.content as? AgentV2MessageContent.Markdown
    val text = when (val content = message.content) {
        is AgentV2MessageContent.Markdown -> content.text
        is AgentV2MessageContent.Semantic -> agentV2SemanticText(content.content)
        null -> message.error?.let { agentV2ErrorText(it.code) } ?: return null
    }
    val role = when (message.role) {
        "user" -> AgentMessageRole.USER
        "assistant" -> AgentMessageRole.ASSISTANT
        else -> AgentMessageRole.SYSTEM
    }
    val mapped = AgentMessage(
        id = message.id,
        sdkMessageId = message.id,
        role = role,
        text = text,
        answerTables = markdown?.tables.orEmpty(),
        tableReferences = markdown?.tableReferences.orEmpty(),
        links = markdown?.links.orEmpty(),
        followups = message.followups.orEmpty(),
        date = parseAgentV2Timestamp(message.createdAt) ?: Date(0),
        isStreaming = message.status == "streaming",
        deeplinks = actions.map { action ->
            AgentDeeplink(action.title, actionId = action.id)
        }
    )
    val error = message.error
    return if (error != null && message.content != null) {
        val errorText = agentV2ErrorText(error.code)
        mapped.copy(text = if (mapped.hasText) "$text\n\n$errorText" else errorText)
    } else {
        mapped
    }
}
