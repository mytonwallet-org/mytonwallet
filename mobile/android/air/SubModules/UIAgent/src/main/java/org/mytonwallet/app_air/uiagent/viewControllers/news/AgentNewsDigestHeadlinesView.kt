package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.MediaViewerVC
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline

/**
 * A digest's top headlines, as its card in the feed and its post at the top of its discussion
 * show them: one row for each, with a bullet, the headline and a gray disclosure arrow, a
 * separator between rows, then the news it leaves out. A row opens its news item's discussion.
 *
 * When a headline has its news item's picture, every row leads with a square in place of the bullet: the picture, a
 * target of its own that opens the digest's pictures in the media viewer, or the News mark for a headline without one
 * or whose picture fails.
 *
 * The view runs from where the bubble's text starts to the bubble's end, so the arrows stand
 * where the Discuss strip's does.
 */
@SuppressLint("ViewConstructor")
internal class AgentNewsDigestHeadlinesView(context: Context) :
    LinearLayout(context),
    WThemedView {
    private val remainderLabel = WLabel(context).apply {
        setStyle(REMAINDER_TEXT_SIZE)
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        setPaddingRelative(BULLET_TEXT_START.dp, REMAINDER_TOP.dp, TEXT_END.dp, 0)
    }
    private val headlineRows = mutableListOf<HeadlineRow>()
    private val separators = mutableListOf<View>()
    private val rows = AgentNewsDigestRows()

    /** A tap on a headline, which opens its news item's discussion */
    var onHeadlineClick: ((AgentV2NewsDigestHeadline) -> Unit)?
        get() = rows.onHeadlineClick
        set(value) {
            rows.onHeadlineClick = value
        }

    /** A tap on a headline's picture, which opens the digest's pictures in the media viewer */
    var onPictureClick: ((AgentNewsDigestPictures) -> Unit)?
        get() = rows.onPictureClick
        set(value) {
            rows.onPictureClick = value
        }

    /** A headline's picture came to show or failed, which changes the pictures TalkBack can open */
    var onPicturesChanged: (() -> Unit)? = null

    init {
        id = generateViewId()
        orientation = VERTICAL
        addView(remainderLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        updateTheme()
    }

    // One row for each headline, a separator between rows; the rows a digest leaves out stay for the next one, without
    // their pictures
    fun configure(headlines: List<AgentV2NewsDigestHeadline>, remainder: String?) {
        rows.update(headlines)
        while (headlineRows.size < headlines.size) {
            if (headlineRows.isNotEmpty()) {
                val separator = View(context).apply { id = generateViewId() }
                separator.setBackgroundColor(WColor.Separator.color)
                separators.add(separator)
                addView(
                    separator,
                    childCount - 1,
                    LayoutParams(MATCH_PARENT, 1).apply { marginEnd = TEXT_END.dp }
                )
            }
            val index = headlineRows.size
            val row = HeadlineRow(context)
            rows.bindRow(row, index)
            row.onPictureLoaded = { isLoaded -> onPictureLoaded(index, isLoaded) }
            headlineRows.add(row)
            addView(row, childCount - 1, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        headlineRows.forEachIndexed { index, row ->
            val headline = headlines.getOrNull(index)
            row.isGone = headline == null
            separators.getOrNull(index - 1)?.isGone = headline == null
            if (headline == null) {
                row.clearPicture()
                return@forEachIndexed
            }
            row.configure(headline, rows.leads[index])
            rows.updateRow(row, index)
        }
        remainderLabel.text = remainder
        remainderLabel.isGone = remainder == null
        val textStart = if (rows.hasPictures) THUMBNAIL_TEXT_START else BULLET_TEXT_START
        remainderLabel.setPaddingRelative(textStart.dp, REMAINDER_TOP.dp, TEXT_END.dp, 0)
    }

    /** Where the media viewer opens from and closes to [headline]'s picture, while its row shows it */
    fun makePictureSource(
        headline: AgentV2NewsDigestHeadline,
        visibleRows: IntRange
    ): MediaViewerVC.Source? {
        val index = rows.headlines.indexOfFirst {
            it.eventId == headline.eventId && it.pictureUrl == headline.pictureUrl
        }
        if (index < 0 || !rows.isPictureTarget(index)) return null
        val row = headlineRows[index]
        val radius = THUMBNAIL_RADIUS.dp.toFloat()
        return MediaViewerVC.Source(
            row.thumbnail,
            radius,
            row.pictureAspectRatio,
            visibleRows,
            radius
        )
    }

    private fun onPictureLoaded(index: Int, isLoaded: Boolean) {
        if (index >= rows.headlines.size) return
        rows.setPictureLoaded(index, isLoaded)
        rows.updateRow(headlineRows[index], index)
        onPicturesChanged?.invoke()
    }

    /** TalkBack's actions that open the pictures that show, for a bubble that reads the headlines as its text */
    fun buildPictureActions(): List<AgentNewsDigestPictureAction> =
        rows.buildPictureActions(LocaleController.getString("Picture"))

    override fun updateTheme() {
        remainderLabel.setTextColor(WColor.SecondaryText)
        headlineRows.forEach(HeadlineRow::updateTheme)
        separators.forEach { it.setBackgroundColor(WColor.Separator.color) }
    }

    /**
     * A headline with its bullet by its first line or its square at the top, the headline centred on the square while
     * shorter than it, and the disclosure arrow, dimmed while pressed. The picture lies over the square apart from the
     * row's content, so a tap on it opens it and not the news item's discussion.
     */
    @SuppressLint("ViewConstructor", "ClickableViewAccessibility")
    private class HeadlineRow(context: Context) :
        WView(context),
        WThemedView,
        AgentNewsDigestRowTargets {
        private val bulletDrawable = GradientDrawable().apply { shape = GradientDrawable.OVAL }
        private val bullet = View(context).apply {
            id = generateViewId()
            background = bulletDrawable
        }
        private val tileDrawable = GradientDrawable().apply {
            cornerRadius = THUMBNAIL_RADIUS.dp.toFloat()
        }
        private val newsMark = AgentNewsIconView(context)
        private val tile = FrameLayout(context).apply {
            id = generateViewId()
            background = tileDrawable
            addView(newsMark, FrameLayout.LayoutParams(NEWS_MARK.dp, NEWS_MARK.dp, Gravity.CENTER))
        }
        val thumbnail = WCustomImageView(context).apply {
            contentDescription = LocaleController.getString("Picture")
        }
        private var pictureUrl: String? = null

        // The colour the picture's placeholder was set with
        private var placeholderColor: Int? = null
        var pictureAspectRatio: Float? = null
            private set
        var onPictureLoaded: ((isLoaded: Boolean) -> Unit)? = null
        private val label = WLabel(context).apply {
            setStyle(HEADLINE_TEXT_SIZE)
            setLineHeight(HEADLINE_LINE_HEIGHT)
            isSingleLine = false
            maxLines = Int.MAX_VALUE
        }
        private val chevron = ImageView(context).apply {
            id = generateViewId()
            setImageResource(R.drawable.ic_menu_arrow_right)
            scaleType = ImageView.ScaleType.CENTER
        }
        private val content = WView(context).apply {
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }

        init {
            minimumHeight = MIN_HEIGHT.dp
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
            isFocusable = true
            isClickable = true
            content.addView(bullet, ConstraintLayout.LayoutParams(BULLET.dp, BULLET.dp))
            content.addView(tile, ConstraintLayout.LayoutParams(THUMBNAIL.dp, THUMBNAIL.dp))
            content.addView(label, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            content.addView(chevron, ConstraintLayout.LayoutParams(CHEVRON_BOX.dp, CHEVRON_BOX.dp))
            content.setConstraints {
                toStart(bullet)
                // The bullet stands by the headline's first line
                toTop(bullet, (HEADLINE_LINE_HEIGHT - BULLET) / 2)
                toStart(tile)
                toTop(tile)
                toStart(label, BULLET_TEXT_START.toFloat())
                endToStart(label, chevron)
                toTop(label)
                toBottom(label)
                toEnd(chevron, CHEVRON_END)
                toCenterY(chevron)
            }
            addView(content, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            addView(thumbnail, ConstraintLayout.LayoutParams(THUMBNAIL.dp, THUMBNAIL.dp))
            setConstraints {
                toStart(content)
                toEnd(content)
                toTop(content, VERTICAL_INSET.toFloat())
                toBottom(content, VERTICAL_INSET.toFloat())
                toStart(thumbnail)
                toTop(thumbnail, VERTICAL_INSET.toFloat())
            }
            setOnTouchListener { _, event ->
                trackPress(event, content, thumbnail)
                false
            }
            thumbnail.setOnTouchListener { _, event ->
                if (thumbnail.isClickable) trackPress(event, thumbnail)
                false
            }
            thumbnail.onFinalImageSet = { info ->
                pictureAspectRatio = info?.takeIf { it.width > 0 && it.height > 0 }
                    ?.let { it.width.toFloat() / it.height }
                onPictureLoaded?.invoke(true)
            }
            thumbnail.onFailure = { onPictureLoaded?.invoke(false) }
            updateTheme()
        }

        // Dims what is under the finger at once and brings it back as the press ends
        private fun trackPress(event: MotionEvent, vararg views: View) {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> views.forEach {
                    it.animate().cancel()
                    it.alpha = PRESSED_ALPHA
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> views.forEach {
                    it.animate().alpha(1f).setDuration(PRESS_RELEASE_MS).start()
                }
            }
        }

        // The same picture binds without loading again, so a row bound again for the same headline keeps it
        fun configure(headline: AgentV2NewsDigestHeadline, lead: AgentNewsDigestLead) {
            label.text = headline.headline
            contentDescription = headline.headline
            val hasSquare = lead != AgentNewsDigestLead.BULLET
            bullet.isGone = hasSquare
            tile.isGone = !hasSquare
            // By its square a headline shorter than it stands centred on it, and a longer one starts at its top, as the
            // row is as tall as the longer of the two
            label.updateLayoutParams<ConstraintLayout.LayoutParams> {
                marginStart = (if (hasSquare) THUMBNAIL_TEXT_START else BULLET_TEXT_START).dp
            }
            val url = headline.pictureUrl
            if (url == pictureUrl) return
            pictureUrl = url
            pictureAspectRatio = null
            if (url == null) {
                thumbnail.clear()
                return
            }
            thumbnail.set(
                Content(
                    Content.Image.Url(url),
                    rounding = Content.Rounding.Radius(THUMBNAIL_RADIUS.dp.toFloat()),
                    placeholder = Content.Placeholder.Color(PICTURE_PLACEHOLDER),
                    decodeSize = THUMBNAIL.dp
                )
            )
            placeholderColor = PICTURE_PLACEHOLDER.color
        }

        /** Lets the picture go, with its load, for a row the digest leaves out */
        fun clearPicture() {
            if (pictureUrl == null) return
            pictureUrl = null
            pictureAspectRatio = null
            thumbnail.clear()
        }

        override fun setOnRowClick(onClick: () -> Unit) {
            setOnClickListener { onClick() }
        }

        override fun setOnPictureClick(onClick: () -> Unit) {
            thumbnail.setOnClickListener { onClick() }
        }

        // The picture lies over its square while it loads and once it shows; the News mark stands for one that fails
        override fun showLead(
            lead: AgentNewsDigestLead,
            state: AgentNewsDigestPictureState,
            isPictureClickable: Boolean
        ) {
            thumbnail.isVisible = lead == AgentNewsDigestLead.PICTURE &&
                state != AgentNewsDigestPictureState.FAILED
            thumbnail.isClickable = isPictureClickable
            thumbnail.importantForAccessibility = if (isPictureClickable) {
                IMPORTANT_FOR_ACCESSIBILITY_YES
            } else {
                IMPORTANT_FOR_ACCESSIBILITY_NO
            }
            newsMark.isVisible = lead == AgentNewsDigestLead.NEWS_MARK ||
                state == AgentNewsDigestPictureState.FAILED
        }

        override fun updateTheme() {
            bulletDrawable.setColor(WColor.Tint.color)
            tileDrawable.setColor(PICTURE_PLACEHOLDER.color)
            label.setTextColor(WColor.PrimaryText)
            chevron.setColorFilter(WColor.SecondaryText.color)
            newsMark.updateTheme()
            // Setting the placeholder's colour loads the picture again, so only a theme that changed it sets it
            val color = PICTURE_PLACEHOLDER.color
            if (pictureUrl != null && color != placeholderColor) {
                placeholderColor = color
                thumbnail.updateTheme()
            }
        }
    }

    companion object {
        // Where the bubble's text, the separators and the remainder end, in dp from its side
        private const val TEXT_END = 16

        private const val REMAINDER_TEXT_SIZE = 15f
        private const val REMAINDER_TOP = 2

        // A headline row: its text after the bullet, the arrow at the end as the Discuss strip's
        private const val MIN_HEIGHT = 44
        private const val VERTICAL_INSET = 10
        private const val HEADLINE_TEXT_SIZE = 16f
        private const val HEADLINE_LINE_HEIGHT = 21f
        private const val BULLET = 6
        private const val BULLET_GAP = 10
        private const val CHEVRON_BOX = 24
        private const val CHEVRON_END = 9f
        private const val PRESSED_ALPHA = 0.4f
        private const val PRESS_RELEASE_MS = 200L

        // A headline's picture or the News mark in its place, 12 from the text, over the fill of a loading picture
        private const val THUMBNAIL = 40
        private const val THUMBNAIL_GAP = 12
        private const val THUMBNAIL_RADIUS = 10
        private const val NEWS_MARK = 20
        private val PICTURE_PLACEHOLDER = WColor.BackgroundRipple

        // Where the headlines' text and the remainder line start
        private const val BULLET_TEXT_START = BULLET + BULLET_GAP
        private const val THUMBNAIL_TEXT_START = THUMBNAIL + THUMBNAIL_GAP
    }
}
