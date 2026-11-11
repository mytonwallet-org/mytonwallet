package org.mytonwallet.app_air.uiagent.agentV2

import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentAnswerFeedback
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentDeeplink
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessageRole
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentSupportEvent
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
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
    val supportEvent = if (message.role == "event") {
        when (val code = message.code) {
            "support_requested", "operator_joined", "support_closed" -> AgentSupportEvent(
                code = code,
                operatorName = message.author?.name,
                reason = message.reason
            )

            else -> return null
        }
    } else {
        null
    }
    val markdown = message.content as? AgentV2MessageContent.Markdown
    val failureText = message.error?.let { agentV2ErrorText(it.code) }
    val text = when {
        message.role == "operator" -> message.text ?: return null

        supportEvent != null -> getSupportEventText(supportEvent)

        else -> when (val content = message.content) {
            is AgentV2MessageContent.Markdown -> content.text
            is AgentV2MessageContent.Semantic -> agentV2SemanticText(content.content)
            null -> if (failureText != null) "" else return null
        }
    }
    // A stopped answer shows what it had written, without suggestions, and nothing when it had written nothing
    val isStopped = message.status == "cancelled"
    if (isStopped && text.isEmpty() && markdown?.tables.isNullOrEmpty() &&
        message.content !is AgentV2MessageContent.Semantic && actions.isEmpty()
    ) {
        return null
    }
    val role = when (message.role) {
        "user" -> AgentMessageRole.USER
        "assistant" -> AgentMessageRole.ASSISTANT
        "operator" -> AgentMessageRole.OPERATOR
        else -> AgentMessageRole.SYSTEM
    }
    return AgentMessage(
        id = message.id,
        sdkMessageId = message.id,
        role = role,
        text = text,
        answerTables = markdown?.tables.orEmpty(),
        tableReferences = markdown?.tableReferences.orEmpty(),
        links = markdown?.links.orEmpty(),
        followups = if (isStopped) emptyList() else message.followups.orEmpty(),
        date = parseAgentV2Timestamp(message.createdAt) ?: Date(0),
        isStreaming = message.status == "streaming",
        deeplinks = actions.map { action ->
            AgentDeeplink(action.title, actionId = action.id)
        },
        // An operator's reply is rated as an answer is
        isComplete = (role == AgentMessageRole.ASSISTANT || role == AgentMessageRole.OPERATOR) &&
            message.status == "complete",
        feedback = AgentAnswerFeedback.fromWireValue(message.feedback),
        newsPost = message.newsPost == true,
        failureText = failureText,
        operator = message.author.takeIf { role == AgentMessageRole.OPERATOR },
        isPlainText = role == AgentMessageRole.OPERATOR,
        supportEvent = supportEvent
    )
}

private fun getSupportEventText(event: AgentSupportEvent): String = when (event.code) {
    "support_requested" -> LocaleController.getString("\$agent_support_requested")

    "operator_joined" -> LocaleController.getStringWithKeyValues(
        "\$agent_support_operator_joined",
        listOf(
            "%name%" to (event.operatorName ?: LocaleController.getString("\$agent_support_label"))
        )
    )

    else -> LocaleController.getString(
        if (event.reason == "inactivity") {
            "\$agent_support_closed_inactivity"
        } else {
            "\$agent_support_closed_operator"
        }
    )
}
