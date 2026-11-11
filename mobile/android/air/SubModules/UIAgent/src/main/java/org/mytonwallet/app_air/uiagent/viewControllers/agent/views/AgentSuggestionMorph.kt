package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.core.animation.doOnEnd
import androidx.core.view.drawToBitmap
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageCell
import org.mytonwallet.app_air.uicomponents.commonViews.WAgentHintView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

private const val MORPH_DURATION_MS = 450L

// The part of the morph over which the title gives way to the bubble's text, and the pill's fill to
// the bubble's
private const val CROSSFADE_START = 0.15f
private const val CROSSFADE_END = 0.6f

// The part of the morph over which the bubble's tail grows out of its corner, after the fill has
// become the bubble's
private const val TAIL_GROWTH_START = 0.6f

// The blur of the title as it fades out, and of the text before it fades in, and of the suggestions
// rippling away
private const val CROSSFADE_BLUR_DP = AgentBlurTransition.RADIUS_DP / 2

// How the suggestions beside a tapped one leave as it starts turning into its bubble: each this
// much after the one nearer the tapped suggestion
private const val RIPPLE_DURATION_MS = 200L
private const val RIPPLE_STAGGER_MS = 30L
private const val RIPPLE_END_SCALE = 0.95f
private const val MAX_PICTURE_ALPHA = 255

/**
 * A tapped suggestion turns into its question's bubble, as on iOS: the pill's frame becomes the
 * bubble's body, its glassy fill gives way to the bubble's colour, and its title moves onto the
 * bubble's text, scaling with it from the title's size to the text's, as the one fades into the
 * other. The title keeps the pill's line breaks and the text has the bubble's, so each goes out of
 * focus as it fades: the two never show sharp together. The morph follows the bubble wherever the
 * chat shows it meanwhile, in place or coming up as the chat scrolls. Until the chat lays the
 * bubble out, the pill holds where it was tapped, as long as its source lasts. Once it has the
 * bubble's fill, the bubble's tail grows out of its corner. At its end it is the bubble, and the
 * real bubble, out of sight until then, takes its place at once.
 */
internal class AgentSuggestionMorph private constructor(
    private val host: ViewGroup,
    private val findCell: () -> AgentMessageCell?,
    private val source: AgentSentMessageSource,
    private val from: AgentSuggestionMorphEnd,
    private val background: Background,
    private val title: ImageView,
    durationMs: Long,
    private val onEnd: () -> Unit
) : AgentMorphClock(host, durationMs) {
    private val isRightToLeft = LocaleController.isRTL
    private val text = ImageView(host.context).apply {
        scaleType = ImageView.ScaleType.FIT_XY
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        pivotX = 0f
        pivotY = 0f
    }

    // Where the bubble was last seen, which the morph keeps going toward while the chat lays it out
    // nowhere
    private var target: AgentSuggestionMorphEnd? = null

    // The bubble's text, in the label, as the text's picture shows it
    private var picturedTextFrame: AgentRevealFrame? = null

    // The cell whose bubble the morph keeps out of sight
    private var hiddenCell: AgentMessageCell? = null

    init {
        host.overlay.add(text)
        step(0)
        start(isReady = { target != null }, canHold = { source.isOpeningFresh })
    }

    override fun step(elapsedMs: Long) {
        val progress = AGENT_TELEGRAM_CURVE.getInterpolation(elapsedMs.toFloat() / durationMs)
        findCell()?.let { cell ->
            updateTarget(cell)
            hideBubble(cell)
        }
        val state = calculateAgentSuggestionMorphState(
            from,
            target ?: from,
            progress,
            isRightToLeft
        )
        background.state = state
        background.invalidate()
        place(title, state.titleFrame)
        place(text, state.textFrame)
        title.alpha = state.titleAlpha
        text.alpha = state.textAlpha
        val blur = CROSSFADE_BLUR_DP.dp
        AgentBlurTransition.setBlur(title, blur * state.titleBlur)
        AgentBlurTransition.setBlur(text, blur * state.textBlur)
    }

    // The bubble stays out of sight until the morph has become it
    private fun hideBubble(cell: AgentMessageCell) {
        if (hiddenCell !== cell) hiddenCell?.sentAppearanceView?.alpha = 1f
        hiddenCell = cell
        cell.sentAppearanceView.alpha = 0f
    }

    // Where the bubble's body and its text are laid out in the host, and a picture of the text
    private fun updateTarget(cell: AgentMessageCell) {
        if (!cell.isAttachedToWindow || !cell.isLaidOut || cell.isLayoutRequested) return
        val bubble = cell.sentBubbleView
        val label = cell.sentTextView
        val bubbleOffset = getAgentLaidOutOffset(bubble, cell) ?: return
        val labelOffset = getAgentLaidOutOffset(label, cell) ?: return
        val textFrame = getAgentTextFrame(label) ?: return
        if (bubble.width <= 0 || bubble.height <= 0) return
        val origin = getAgentHostOrigin(cell, host)
        val left = origin.x + bubbleOffset.x
        val top = origin.y + bubbleOffset.y
        val tailWidth = AGENT_BUBBLE_TAIL_WIDTH.dp
        val body = if (isRightToLeft) {
            AgentRevealFrame(left + tailWidth, top, left + bubble.width, top + bubble.height)
        } else {
            AgentRevealFrame(left, top, left + bubble.width - tailWidth, top + bubble.height)
        }
        val textInHost = textFrame.offsetBy(origin.x + labelOffset.x, origin.y + labelOffset.y)
        val pictured = picturedTextFrame
        if (pictured == null || abs(pictured.width - textFrame.width) > 0.5f ||
            abs(pictured.height - textFrame.height) > 0.5f
        ) {
            makeAgentTextPicture(label, textFrame)?.let { picture ->
                text.setImageBitmap(picture)
                text.layout(0, 0, picture.width, picture.height)
                picturedTextFrame = textFrame
            }
        }
        target = AgentSuggestionMorphEnd(
            frame = body,
            textOffsetX = if (isRightToLeft) {
                body.right - textInHost.right
            } else {
                textInHost.left - body.left
            },
            textOffsetY = textInHost.top - body.top,
            textWidth = textInHost.width,
            textHeight = textInHost.height,
            fontSize = label.textSize
        )
    }

    // Shows [view], laid out at its picture's size from the host's corner, over [frame]
    private fun place(view: ImageView, frame: AgentRevealFrame) {
        if (view.width <= 0 || view.height <= 0) return
        view.scaleX = frame.width / view.width
        view.scaleY = frame.height / view.height
        view.translationX = frame.left
        view.translationY = frame.top
    }

    override fun onFinish() {
        // The real bubble takes over at once: two translucent bubbles would show lighter than
        // either
        hiddenCell?.sentAppearanceView?.alpha = 1f
        hiddenCell = null
        host.overlay.remove(background)
        host.overlay.remove(title)
        host.overlay.remove(text)
        onEnd()
    }

    /** The pill and the bubble's fill with its tail, over the morph's frame */
    @SuppressLint("ViewConstructor")
    private class Background(context: Context, private val card: WAgentHintView) : View(context) {
        private val fill = AgentBubbleDrawable(isOutgoing = true, isTailless = true)
        var state: AgentSuggestionMorphState? = null

        init {
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        override fun onDraw(canvas: Canvas) {
            val state = state ?: return
            val frame = state.frame
            val width = frame.width.roundToInt()
            val height = frame.height.roundToInt()
            if (width <= 0 || height <= 0) return
            canvas.save()
            canvas.translate(frame.left, frame.top)
            if (state.pillAlpha > 0f) {
                val layer = canvas.saveLayerAlpha(
                    0f,
                    0f,
                    width.toFloat(),
                    height.toFloat(),
                    (state.pillAlpha * MAX_ALPHA).roundToInt()
                )
                card.drawPill(canvas, width, height)
                canvas.restoreToCount(layer)
            }
            if (state.fillAlpha > 0f) {
                // The bubble's tail hangs out of the body on the trailing side
                val tailWidth = AGENT_BUBBLE_TAIL_WIDTH.dp
                if (LocaleController.isRTL) {
                    fill.setBounds(-tailWidth, 0, width, height)
                } else {
                    fill.setBounds(0, 0, width + tailWidth, height)
                }
                fill.tailProgress = state.tailGrowth
                fill.alpha = (state.fillAlpha * MAX_ALPHA).roundToInt()
                fill.draw(canvas)
            }
            canvas.restore()
        }
    }

    companion object {
        private const val MAX_ALPHA = 255

        /**
         * Starts the morph of the suggestion of [source] into the bubble of the cell [findCell]
         * finds, or null while the chat shows none, over [host], which shows the morph. It lasts as
         * long as a screen transition of [transitionMs] it plays over, if that is longer than its
         * own time. [onEnd] runs as the bubble takes over, at the end or at [cancel].
         */
        fun start(
            host: ViewGroup,
            findCell: () -> AgentMessageCell?,
            source: AgentSentMessageSource,
            transitionMs: Long = 0L,
            onEnd: () -> Unit = {}
        ): AgentSuggestionMorph? {
            val kind = source.kind as? AgentSentMessageSource.Kind.Suggestion ?: return null
            if (!host.isAttachedToWindow) return null
            val origin = getAgentWindowOrigin(host)
            val frame = source.frame.offsetBy(-origin.x, -origin.y)
            val titleFrame = kind.titleFrame.offsetBy(-origin.x, -origin.y)
            val background = Background(host.context, kind.card).apply {
                layout(0, 0, host.width, host.height)
            }
            val title = makeAgentPictureView(host.context, kind.title, titleFrame).apply {
                layout(0, 0, kind.title.width, kind.title.height)
                pivotX = 0f
                pivotY = 0f
            }
            host.overlay.add(background)
            host.overlay.add(title)
            // The card stays out of sight as the morph takes its place
            kind.card.animate().cancel()
            kind.card.alpha = 0f
            val from = AgentSuggestionMorphEnd(
                frame = frame,
                textOffsetX = if (LocaleController.isRTL) {
                    frame.right - titleFrame.right
                } else {
                    titleFrame.left - frame.left
                },
                textOffsetY = titleFrame.top - frame.top,
                textWidth = titleFrame.width,
                textHeight = titleFrame.height,
                fontSize = kind.titleTextSize
            )
            return AgentSuggestionMorph(
                host,
                findCell,
                source,
                from,
                background,
                title,
                durationMs = max(MORPH_DURATION_MS, transitionMs),
                onEnd = onEnd
            )
        }
    }
}

/**
 * The suggestions beside a tapped one leave as a ripple away from the finger, starting with the
 * nearest: each fades out with a slight blur, shrinking a little toward its own centre. Pictures of
 * them leave in a host's overlay, in their places, while they themselves go out of sight at once,
 * so the list closes up under the pictures as it would.
 */
internal class AgentSuggestionRipple private constructor(
    private val suggestions: List<View>,
    private val animators: List<ValueAnimator>
) {
    private val endActions = mutableListOf<() -> Unit>()

    /** Whether the suggestions have all gone */
    val isFinished: Boolean
        get() = animators.none { it.isStarted }

    init {
        animators.forEach { animator -> animator.doOnEnd { if (isFinished) runEndActions() } }
    }

    /** Runs [action] once the suggestions have all gone, at once if they have */
    fun doOnEnd(action: () -> Unit) {
        if (isFinished) action() else endActions += action
    }

    private fun runEndActions() {
        val actions = endActions.toList()
        endActions.clear()
        actions.forEach { it() }
    }

    /**
     * Ends the ripple at once, for a question that didn't go: the pictures go and the suggestions
     * show again
     */
    fun cancel() {
        animators.forEach { it.end() }
        suggestions.forEach { it.alpha = 1f }
    }

    companion object {
        /**
         * Ripples [suggestions] other than [tapped] away over [host], from [tapped]: the suggestion
         * tapped, or the field a question left
         */
        fun start(suggestions: List<View>, tapped: View, host: ViewGroup): AgentSuggestionRipple {
            val hostOrigin = getAgentWindowOrigin(host)
            val shown = suggestions.filter {
                it !== tapped && it.isShown && it.alpha > 0.01f && it.isLaidOut && it.width > 0
            }
            val frames = shown.map { suggestion ->
                val parent = suggestion.parent as View
                val origin = getAgentWindowOrigin(parent)
                val left = origin.x - hostOrigin.x + suggestion.left - parent.scrollX
                val top = origin.y - hostOrigin.y + suggestion.top - parent.scrollY
                AgentRevealFrame(left, top, left + suggestion.width, top + suggestion.height)
            }
            val tappedFrame = getAgentWindowOrigin(tapped).let {
                val left = it.x - hostOrigin.x
                val top = it.y - hostOrigin.y
                AgentRevealFrame(left, top, left + tapped.width, top + tapped.height)
            }
            val delays = calculateAgentRippleDelays(frames, tappedFrame)
            val animators = shown.mapIndexed { index, suggestion ->
                val picture = makeAgentPictureView(
                    host.context,
                    makeAgentViewPicture(suggestion),
                    frames[index]
                )
                host.overlay.add(picture)
                suggestion.animate().cancel()
                suggestion.alpha = 0f
                ValueAnimator.ofFloat(0f, 1f).apply {
                    duration = RIPPLE_DURATION_MS
                    startDelay = delays[index]
                    interpolator = AGENT_EASE_OUT
                    addUpdateListener {
                        val fraction = it.animatedValue as Float
                        picture.alpha = 1f - fraction
                        val scale = interpolate(1f, RIPPLE_END_SCALE, fraction)
                        picture.scaleX = scale
                        picture.scaleY = scale
                        AgentBlurTransition.setBlur(picture, CROSSFADE_BLUR_DP.dp * fraction)
                    }
                    doOnEnd { host.overlay.remove(picture) }
                    start()
                }
            }
            return AgentSuggestionRipple(shown, animators)
        }
    }
}

/**
 * Where a morph into a bubble starts or ends: its frame, and the text on it, from the frame's
 * leading top corner
 */
internal class AgentSuggestionMorphEnd(
    val frame: AgentRevealFrame,
    val textOffsetX: Float,
    val textOffsetY: Float,
    val textWidth: Float,
    val textHeight: Float,
    val fontSize: Float
)

/** The morph at one moment; the blurs are shares of the crossfade's */
internal class AgentSuggestionMorphState(
    val frame: AgentRevealFrame,
    val pillAlpha: Float,
    val fillAlpha: Float,
    val titleFrame: AgentRevealFrame,
    val titleAlpha: Float,
    val titleBlur: Float,
    val textFrame: AgentRevealFrame,
    val textAlpha: Float,
    val textBlur: Float,
    val tailGrowth: Float
)

/**
 * The morph at [progress] along its curve, from the pill and its title at [start] to the bubble's
 * body and its text at [end]. The title and the text stand on one point, scaled alike from the
 * title's size to the text's, so the one fades into the other in place; halfway through, both are
 * as much out of focus, and by its end the text is sharp.
 */
internal fun calculateAgentSuggestionMorphState(
    start: AgentSuggestionMorphEnd,
    end: AgentSuggestionMorphEnd,
    progress: Float,
    isRightToLeft: Boolean
): AgentSuggestionMorphState {
    val frame = agentRevealMorphFrame(start.frame, end.frame, progress)
    val shift = calculateAgentShare(progress, CROSSFADE_START, CROSSFADE_END)
    val offsetX = interpolate(start.textOffsetX, end.textOffsetX, progress)
    val offsetY = interpolate(start.textOffsetY, end.textOffsetY, progress)
    val textScale = end.fontSize / start.fontSize
    val titleScale = 1f + (textScale - 1f) * progress
    return AgentSuggestionMorphState(
        frame = frame,
        pillAlpha = 1f - shift,
        fillAlpha = shift,
        titleFrame = placeAgentMorphText(
            frame,
            offsetX,
            offsetY,
            start.textWidth * titleScale,
            start.textHeight * titleScale,
            isRightToLeft
        ),
        titleAlpha = 1f - shift,
        titleBlur = shift,
        textFrame = placeAgentMorphText(
            frame,
            offsetX,
            offsetY,
            end.textWidth * titleScale / textScale,
            end.textHeight * titleScale / textScale,
            isRightToLeft
        ),
        textAlpha = shift,
        textBlur = 1f - shift,
        tailGrowth = calculateAgentShare(progress, TAIL_GROWTH_START, 1f)
    )
}

/** How far [value] is from [start] to [end], from 0 before it to 1 after it */
internal fun calculateAgentShare(value: Float, start: Float, end: Float): Float =
    ((value - start) / (end - start)).coerceIn(0f, 1f)

/**
 * The delay of each of the suggestions at [frames] as they ripple away from the one at [tapped],
 * the nearest first
 */
internal fun calculateAgentRippleDelays(
    frames: List<AgentRevealFrame>,
    tapped: AgentRevealFrame
): List<Long> {
    fun getDistance(frame: AgentRevealFrame) = hypot(
        (frame.left + frame.right - tapped.left - tapped.right) / 2,
        (frame.top + frame.bottom - tapped.top - tapped.bottom) / 2
    )
    val ranks = frames.indices.sortedBy { getDistance(frames[it]) }
    val delays = MutableList(frames.size) { 0L }
    ranks.forEachIndexed { rank, index -> delays[index] = rank * RIPPLE_STAGGER_MS }
    return delays
}

// A text of [width] × [height] whose leading top corner stands [offsetX], [offsetY] from [frame]'s
private fun placeAgentMorphText(
    frame: AgentRevealFrame,
    offsetX: Float,
    offsetY: Float,
    width: Float,
    height: Float,
    isRightToLeft: Boolean
): AgentRevealFrame {
    val left = if (isRightToLeft) frame.right - offsetX - width else frame.left + offsetX
    val top = frame.top + offsetY
    return AgentRevealFrame(left, top, left + width, top + height)
}

/**
 * A picture of [view] as it draws, with what the texture views in it show, which a bitmap's canvas
 * leaves out, as the spinning top's
 */
private fun makeAgentViewPicture(view: View): Bitmap {
    val picture = view.drawToBitmap()
    drawAgentTextureFrames(view, view, Canvas(picture))
    return picture
}

private fun drawAgentTextureFrames(view: View, root: View, canvas: Canvas) {
    if (view.visibility != View.VISIBLE) return
    if (view is TextureView) {
        val frame = view.takeIf { it.isAvailable }?.bitmap ?: return
        val offset = getAgentLaidOutOffset(view, root) ?: return
        val paint = Paint(Paint.FILTER_BITMAP_FLAG).apply {
            alpha = (view.alpha * MAX_PICTURE_ALPHA).roundToInt()
        }
        canvas.drawBitmap(frame, offset.x, offset.y, paint)
        frame.recycle()
        return
    }
    val group = view as? ViewGroup ?: return
    for (index in 0 until group.childCount) {
        drawAgentTextureFrames(group.getChildAt(index), root, canvas)
    }
}
