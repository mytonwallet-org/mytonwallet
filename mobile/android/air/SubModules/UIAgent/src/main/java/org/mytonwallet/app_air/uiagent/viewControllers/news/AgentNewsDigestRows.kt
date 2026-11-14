package org.mytonwallet.app_air.uiagent.viewControllers.news

import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline

/** What leads a digest's headline row */
internal enum class AgentNewsDigestLead { BULLET, PICTURE, NEWS_MARK }

/** How far a headline's picture has come */
internal enum class AgentNewsDigestPictureState { NONE, LOADING, SHOWN, FAILED }

/** The digest's pictures the media viewer pages through, in the headlines' order, and the one it opens at */
internal class AgentNewsDigestPictures(
    val headlines: List<AgentV2NewsDigestHeadline>,
    val index: Int
)

/** A TalkBack action of the post's bubble that opens a headline's picture */
internal class AgentNewsDigestPictureAction(val label: String, val open: () -> Unit)

/** A headline row's tap targets: the row, and the picture over its square */
internal interface AgentNewsDigestRowTargets {
    fun setOnRowClick(onClick: () -> Unit)
    fun setOnPictureClick(onClick: () -> Unit)

    /** [isPictureClickable]: the picture takes taps of its own; otherwise they reach the row */
    fun showLead(
        lead: AgentNewsDigestLead,
        state: AgentNewsDigestPictureState,
        isPictureClickable: Boolean
    )
}

internal val AgentV2NewsDigestHeadline.pictureUrl: String?
    get() = imageUrl?.takeIf { it.isNotBlank() }

/**
 * A digest's headline rows apart from their views: what leads each and where a tap goes. Without any picture every row
 * leads with a bullet; otherwise with its picture, or the News mark in its place. A picture that shows takes a tap of
 * its own, which opens the digest's pictures that show; anything else on the row opens its news item's discussion.
 */
internal class AgentNewsDigestRows {
    var headlines: List<AgentV2NewsDigestHeadline> = emptyList()
        private set
    var leads: List<AgentNewsDigestLead> = emptyList()
        private set
    private var pictureStates: List<AgentNewsDigestPictureState> = emptyList()

    var onHeadlineClick: ((AgentV2NewsDigestHeadline) -> Unit)? = null
    var onPictureClick: ((AgentNewsDigestPictures) -> Unit)? = null

    val hasPictures: Boolean get() = leads.any { it != AgentNewsDigestLead.BULLET }

    // A row whose picture stays keeps how far it has come, as its view doesn't load it again
    fun update(headlines: List<AgentV2NewsDigestHeadline>) {
        val previous = this.headlines
        val previousStates = pictureStates
        this.headlines = headlines
        val hasPictures = headlines.any { it.pictureUrl != null }
        leads = headlines.map {
            when {
                !hasPictures -> AgentNewsDigestLead.BULLET
                it.pictureUrl != null -> AgentNewsDigestLead.PICTURE
                else -> AgentNewsDigestLead.NEWS_MARK
            }
        }
        pictureStates = headlines.mapIndexed { index, headline ->
            val url = headline.pictureUrl
            when {
                url == null -> AgentNewsDigestPictureState.NONE
                previous.getOrNull(index)?.pictureUrl == url -> previousStates[index]
                else -> AgentNewsDigestPictureState.LOADING
            }
        }
    }

    fun setPictureLoaded(index: Int, isLoaded: Boolean) {
        if (pictureStates[index] == AgentNewsDigestPictureState.NONE) return
        val state =
            if (isLoaded) AgentNewsDigestPictureState.SHOWN else AgentNewsDigestPictureState.FAILED
        pictureStates = pictureStates.toMutableList().also { it[index] = state }
    }

    /** Only a picture that shows takes a tap of its own; on its square while it loads or on the News mark the row does */
    fun isPictureTarget(index: Int): Boolean =
        pictureStates[index] == AgentNewsDigestPictureState.SHOWN

    /** Sends [row]'s taps to the headline at [index]: the row's to its discussion, the picture's to the viewer */
    fun bindRow(row: AgentNewsDigestRowTargets, index: Int) {
        row.setOnRowClick { clickRow(index) }
        row.setOnPictureClick { clickPicture(index) }
    }

    fun updateRow(row: AgentNewsDigestRowTargets, index: Int) {
        row.showLead(leads[index], pictureStates[index], isPictureTarget(index))
    }

    /** One action for each picture that shows, named [pictureLabel] and its headline, opening the viewer at it */
    fun buildPictureActions(pictureLabel: String): List<AgentNewsDigestPictureAction> =
        headlines.indices.filter(::isPictureTarget).map { index ->
            AgentNewsDigestPictureAction("$pictureLabel, ${headlines[index].headline}") {
                clickPicture(index)
            }
        }

    fun clickRow(index: Int) {
        onHeadlineClick?.invoke(headlines[index])
    }

    fun clickPicture(index: Int) {
        buildPictures(index)?.let { onPictureClick?.invoke(it) }
    }

    fun buildPictures(index: Int): AgentNewsDigestPictures? {
        if (!isPictureTarget(index)) return null
        val shown = headlines.indices.filter(::isPictureTarget)
        return AgentNewsDigestPictures(shown.map(headlines::get), shown.indexOf(index))
    }
}
