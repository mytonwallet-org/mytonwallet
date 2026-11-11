package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import android.animation.ValueAnimator
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.text.TextPaint
import android.text.TextUtils
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AnimationUtils
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

/**
 * Draws the list's card, which starts at the first row with rounded top corners and ends at the last row with
 * rounded bottom corners, or goes on under the composer while rows below are off screen, and the day header of the
 * topmost visible section pinned right under the top bar. The header floats over a translucent band that reaches
 * from the top of the list to a little past it, so the rows fade out under it. The next section's header pushes it
 * away. While the list gives way to composing, the page's color covers the card, its rows and the header by
 * [coverAlpha], so the chats fade out with their card.
 */
internal class AgentThreadListDecoration(
    // The title of the section a row belongs to, or null for the News row
    private val sectionTitleAt: (position: Int) -> String?,
    private val isHeaderAt: (position: Int) -> Boolean
) : RecyclerView.ItemDecoration() {
    private val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val cornerPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private val card = RectF()
    private val cardPath = Path()
    private val cornerPath = Path()
    private val radii = FloatArray(8)
    private var hasRoundedTop = false
    private var hasRoundedBottom = false
    private val bandPaint = Paint()
    private val bandMatrix = Matrix()
    private var bandShader: LinearGradient? = null
    private var bandColor = 0
    private var bandStickyTop = 0f
    private var bandBottom = 0f
    private var bandAlpha = 0f
    private var pinnedTitle: String? = null
    private var pinnedTop = 0f
    private var pinnedAlpha = 1f
    private val floatingHeaders = ArrayList<View>()
    private val coverPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    var coverAlpha = 0f

    var stickyTop: Int? = null

    // The card's bottom as last drawn, and where it eases up from after rows below the last one went
    private var drawnBottom = Float.NaN
    private var easedFromBottom = Float.NaN
    private var easeStartMs = 0L

    // Debug builds set the bottom at once while system animations are off, to keep E2E runs fast
    private val canEaseBottom: Boolean
        get() = !DEBUG_MODE || areSystemAnimatorsEnabled

    private val areSystemAnimatorsEnabled: Boolean
        get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled()

    private var titleLabel: WLabel? = null
    private val titleBaselines = HashMap<String, Float>()

    override fun onDraw(canvas: Canvas, parent: RecyclerView, state: RecyclerView.State) {
        layoutPinnedHeader(parent, state.itemCount)
        // A list without rows has no card, and shows the page
        if (state.itemCount == 0) return
        val firstRow = parent.findViewHolderForAdapterPosition(0)?.itemView
        hasRoundedTop = firstRow != null
        val top = firstRow?.let { it.top + it.translationY } ?: 0f
        val lastPosition = state.itemCount - 1
        hasRoundedBottom = lastPosition >= 0 &&
            parent.findViewHolderForAdapterPosition(lastPosition) != null
        card.set(
            parent.paddingLeft.toFloat(),
            top,
            (parent.width - parent.paddingRight).toFloat(),
            if (hasRoundedBottom) {
                easeBottom(parent, lastRowBottom(parent, lastPosition))
            } else {
                parent.height.toFloat()
            }
        )
        drawnBottom = card.bottom
        cardPaint.color = WColor.Background.color
        val radius = ViewConstants.BLOCK_RADIUS.dp
        if ((!hasRoundedTop && !hasRoundedBottom) || radius <= 0f) {
            canvas.drawRect(card, cardPaint)
            return
        }
        radii.fill(if (hasRoundedTop) radius else 0f, 0, 4)
        radii.fill(if (hasRoundedBottom) radius else 0f, 4, 8)
        cardPath.rewind()
        cardPath.addRoundRect(card, radii, Path.Direction.CW)
        canvas.drawPath(cardPath, cardPaint)
    }

    /**
     * Makes the card's bottom ease up to where it ends after the next change, as the rows that close up a removed
     * row's place do, rather than jump there when the rows under the last one go
     */
    fun easeBottomOnNextChange() {
        if (drawnBottom.isNaN() || !canEaseBottom) return
        easedFromBottom = drawnBottom
        easeStartMs = AnimationUtils.currentAnimationTimeMillis()
    }

    // The bottom of the last row, which follows it as it moves
    private fun lastRowBottom(parent: RecyclerView, lastPosition: Int): Float {
        val lastRow = parent.findViewHolderForAdapterPosition(lastPosition)?.itemView
            ?: return parent.height.toFloat()
        return lastRow.top + lastRow.translationY + lastRow.height
    }

    private fun easeBottom(parent: RecyclerView, bottom: Float): Float {
        if (easedFromBottom.isNaN()) return bottom
        val progress = (AnimationUtils.currentAnimationTimeMillis() - easeStartMs).toFloat() /
            AgentThreadListItemAnimator.MOVE_DURATION_MS
        if (progress >= 1f || easedFromBottom <= bottom) {
            easedFromBottom = Float.NaN
            return bottom
        }
        parent.postInvalidateOnAnimation()
        val eased = WInterpolator.smooth.getInterpolation(progress)
        return easedFromBottom + (bottom - easedFromBottom) * eased
    }

    override fun onDrawOver(canvas: Canvas, parent: RecyclerView, state: RecyclerView.State) {
        val radius = ViewConstants.BLOCK_RADIUS.dp
        if ((hasRoundedTop || hasRoundedBottom) && radius > 0f) {
            // Keep row highlights inside the card's rounded corners
            cornerPath.rewind()
            if (hasRoundedTop) {
                cornerPath.addRect(
                    card.left,
                    card.top,
                    card.right,
                    card.top + radius,
                    Path.Direction.CW
                )
            }
            if (hasRoundedBottom) {
                cornerPath.addRect(
                    card.left,
                    card.bottom - radius,
                    card.right,
                    card.bottom,
                    Path.Direction.CW
                )
            }
            cornerPath.op(cardPath, Path.Op.DIFFERENCE)
            cornerPaint.color = WColor.SecondaryBackground.color
            canvas.drawPath(cornerPath, cornerPaint)
        }
        drawPinnedHeader(canvas, parent)
        drawCover(canvas)
    }

    fun drawCover(canvas: Canvas) {
        if (coverAlpha <= 0f) return
        coverPaint.color = WColor.SecondaryBackground.color
        coverPaint.alpha = (coverAlpha * coverPaint.alpha).roundToInt()
        if ((hasRoundedTop || hasRoundedBottom) && ViewConstants.BLOCK_RADIUS > 0f) {
            canvas.drawPath(cardPath, coverPaint)
        } else {
            canvas.drawRect(card, coverPaint)
        }
    }

    // Finds the section pinned under the top bar, and the headers of the next sections that ride over its band
    private fun layoutPinnedHeader(parent: RecyclerView, itemCount: Int) {
        pinnedTitle = null
        floatingHeaders.clear()
        val stickyTop = (stickyTop ?: parent.paddingTop).toFloat()
        var topPosition = RecyclerView.NO_POSITION
        var topRowTop = 0f
        for (index in 0 until parent.childCount) {
            val child = parent.getChildAt(index)
            val position = parent.getChildAdapterPosition(child)
            if (position == RecyclerView.NO_POSITION) continue
            val childTop = child.top + child.translationY
            val childBottom = child.bottom + child.translationY
            val isAbove = topPosition == RecyclerView.NO_POSITION || position < topPosition
            if (childBottom > stickyTop && isAbove) {
                topPosition = position
                topRowTop = childTop
            }
        }
        val title = topPosition.takeIf { it != RecyclerView.NO_POSITION }?.let(sectionTitleAt)
        var firstHeader = 0
        while (firstHeader < itemCount && !isHeaderAt(firstHeader)) firstHeader++
        // Only the first day header in full view rests unpinned: above a later one, rows have scrolled away
        val isPinned = title != null && !(topPosition == firstHeader && topRowTop >= stickyTop)
        val headerHeight = AgentThreadSectionMetrics.HEIGHT.dp.toFloat()
        bandBottom = stickyTop + headerHeight + BAND_HEIGHT.dp
        if (isPinned) {
            var nextHeaderTop = Float.MAX_VALUE
            var firstHeaderTop = Float.NEGATIVE_INFINITY
            for (index in 0 until parent.childCount) {
                val child = parent.getChildAt(index)
                val position = parent.getChildAdapterPosition(child)
                val childTop = child.top + child.translationY
                if (position == firstHeader) firstHeaderTop = childTop
                if (position > topPosition && isHeaderAt(position)) {
                    nextHeaderTop = minOf(nextHeaderTop, childTop)
                }
            }
            val restingTop = if (isHeaderAt(topPosition)) maxOf(stickyTop, topRowTop) else stickyTop
            // The next section's header pushes it away, fading it out as it goes
            val offset = minOf(0f, nextHeaderTop - (restingTop + headerHeight))
            pinnedTop = restingTop + offset
            pinnedAlpha = (1f + offset / headerHeight).coerceIn(0f, 1f)
            // The band fades in over the first 12 dp the first day header travels under the top bar, and stays
            bandAlpha = ((stickyTop - firstHeaderTop) / BAND_FADE_IN_DISTANCE.dp).coerceIn(0f, 1f)
            pinnedTitle = title
        }
        for (index in 0 until parent.childCount) {
            val child = parent.getChildAt(index)
            val cell = child as? AgentThreadSectionCell ?: continue
            val position = parent.getChildAdapterPosition(child)
            val top = child.top + child.translationY
            // A header entering the band rides over it, so it stays as clear as the one it pushes
            val isFloating = isPinned && position > topPosition && top < bandBottom
            if (isFloating) floatingHeaders.add(child)
            cell.isTitleHidden = isPinned && position != RecyclerView.NO_POSITION &&
                (position <= topPosition || isFloating)
        }
    }

    private fun drawPinnedHeader(canvas: Canvas, parent: RecyclerView) {
        val title = pinnedTitle ?: return
        canvas.save()
        canvas.clipRect(card.left, 0f, card.right, parent.height.toFloat())
        drawBand(canvas, (stickyTop ?: parent.paddingTop).toFloat())
        for (child in floatingHeaders) {
            val position = parent.getChildAdapterPosition(child)
            val floatingTitle = sectionTitleAt(position) ?: continue
            drawTitle(canvas, parent, floatingTitle, child.top + child.translationY, child.alpha)
        }
        drawTitle(canvas, parent, title, pinnedTop, pinnedAlpha)
        canvas.restore()
    }

    // From the top of the list to a little past the pinned header the rows fade out under a translucent band
    private fun drawBand(canvas: Canvas, stickyTop: Float) {
        if (bandAlpha <= 0f || bandBottom <= 0f) return
        val color = WColor.Background.color
        val shader = bandShader?.takeIf { bandColor == color && bandStickyTop == stickyTop }
            ?: makeBandShader(color, stickyTop).also {
                bandShader = it
                bandColor = color
                bandStickyTop = stickyTop
                bandPaint.shader = it
            }
        bandMatrix.setScale(1f, bandBottom)
        shader.setLocalMatrix(bandMatrix)
        bandPaint.alpha = (bandAlpha * 255).roundToInt()
        canvas.drawRect(card.left, 0f, card.right, bandBottom, bandPaint)
    }

    // A unit-high gradient, dense down to the pinned header's bottom and easing out a little under it
    private fun makeBandShader(color: Int, stickyTop: Float): LinearGradient {
        val headerBottom = (stickyTop + AgentThreadSectionMetrics.HEIGHT.dp) / bandBottom
        val easing = headerBottom + (1f - headerBottom) * BAND_EASE_STOP
        val dense = color.withAlpha(BAND_ALPHA)
        return LinearGradient(
            0f,
            0f,
            0f,
            1f,
            intArrayOf(dense, dense, color.withAlpha(BAND_ALPHA / 2), color and 0x00FFFFFF),
            floatArrayOf(0f, headerBottom, easing, 1f),
            Shader.TileMode.CLAMP
        )
    }

    private fun Int.withAlpha(alpha: Float): Int =
        (this and 0x00FFFFFF) or ((Color.alpha(this) * alpha).roundToInt() shl 24)

    private fun drawTitle(
        canvas: Canvas,
        parent: RecyclerView,
        title: String,
        headerTop: Float,
        alpha: Float
    ) {
        if (alpha <= 0f) return
        textPaint.typeface = WFont.Medium.typeface
        textPaint.textSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            AgentThreadSectionMetrics.TEXT_SIZE,
            parent.resources.displayMetrics
        )
        val color = WColor.Tint.color
        textPaint.color = color
        textPaint.alpha = (Color.alpha(color) * alpha).roundToInt()
        val inset = AgentThreadSectionMetrics.TEXT_INSET.dp
        val available = card.width() - 2 * inset
        val text = TextUtils.ellipsize(title, textPaint, available, TextUtils.TruncateAt.END)
            .toString()
        val textWidth = textPaint.measureText(text)
        val x = if (LocaleController.isRTL) card.right - inset - textWidth else card.left + inset
        canvas.drawText(text, x, headerTop + getTitleBaseline(parent, text), textPaint)
    }

    private fun getTitleBaseline(parent: RecyclerView, title: String): Float =
        titleBaselines.getOrPut(title) {
            // A label outside any layout needs its parameters to lay out later text
            val label = titleLabel ?: makeAgentThreadSectionLabel(parent.context).also {
                it.layoutParams = ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
                titleLabel = it
            }
            label.text = title
            val unspecified = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
            label.measure(unspecified, unspecified)
            (AgentThreadSectionMetrics.TEXT_TOP.dp + label.baseline).toFloat()
        }

    private companion object {
        const val BAND_HEIGHT = 20
        const val BAND_FADE_IN_DISTANCE = 12
        const val BAND_ALPHA = 0.92f
        const val BAND_EASE_STOP = 0.35f
    }
}
