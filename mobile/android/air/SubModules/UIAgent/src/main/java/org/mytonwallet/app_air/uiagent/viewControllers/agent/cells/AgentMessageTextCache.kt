package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.util.LruCache
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerLink
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerTable
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2AnswerTableReference

/** A chat screen's parsed finished messages, so scrolling back skips Markdown parsing. */
internal class AgentMessageTextCache {
    data class TextKey(
        val messageId: String,
        val source: String,
        val codeColor: Int,
        val linkColor: Int?,
        val detectsUrls: Boolean,
        val textSize: Float
    )

    data class BlocksKey(
        val messageId: String,
        val source: String,
        val tables: List<AgentV2AnswerTable>,
        val references: List<AgentV2AnswerTableReference>,
        val links: List<AgentV2AnswerLink>
    )

    // `LruCache` can't hold null for an answer without tables
    private class Blocks(val value: List<MarkdownParser.Block>?)

    private val texts = LruCache<TextKey, CharSequence>(MAX_MESSAGES)
    private val blocks = LruCache<BlocksKey, Blocks>(MAX_MESSAGES)

    fun getText(key: TextKey, parse: () -> CharSequence): CharSequence =
        texts.get(key) ?: parse().also { texts.put(key, it) }

    fun getBlocks(
        key: BlocksKey,
        build: () -> List<MarkdownParser.Block>?
    ): List<MarkdownParser.Block>? =
        (blocks.get(key) ?: Blocks(build()).also { blocks.put(key, it) }).value

    private companion object {
        const val MAX_MESSAGES = 64
    }
}
