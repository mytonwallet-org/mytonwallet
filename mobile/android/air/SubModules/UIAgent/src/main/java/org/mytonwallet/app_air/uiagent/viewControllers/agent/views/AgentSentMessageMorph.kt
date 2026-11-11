package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.RectF
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.animation.LinearInterpolator
import android.view.animation.PathInterpolator
import android.widget.ImageView
import android.widget.TextView
import androidx.core.animation.doOnEnd
import androidx.core.graphics.ColorUtils
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageCell
import org.mytonwallet.app_air.uicomponents.commonViews.WAgentHintView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

// Telegram's input panel curve, which the morphs into a bubble run on
internal val AGENT_TELEGRAM_CURVE = PathInterpolator(0.38f, 0.7f, 0.125f, 1f)

// UIKit's ease-out and ease-in; the ease-out is also Telegram's `CubicBezierInterpolator.EASE_OUT`
internal val AGENT_EASE_OUT = PathInterpolator(0f, 0f, 0.58f, 1f)
internal val AGENT_EASE_IN = PathInterpolator(0.42f, 0f, 1f, 1f)

private const val SENT_SOURCE_LIFETIME_MS = 1000L

// Telegram's `ChatListItemAnimator.DEFAULT_DURATION`, the send transition's own time
private const val SEND_DURATION_MS = 250L

// A new chat's question may wait a moment longer for its chat to show it
private const val OPENING_SOURCE_LIFETIME_MS = 3000L

// Telegram's `ChatListItemAnimator.DEFAULT_INTERPOLATOR`, on which its list moves a sent message's
// row, and its send transition takes the text and the bubble up or down with it
private val SEND_LIST_CURVE = PathInterpolator(0.19919473f, 0.010644531f, 0.27920938f, 0.9102539f)

// Telegram's `CubicBezierInterpolator.EASE_OUT_QUINT`, which, eased out again, takes them across
// and sizes them
private val SEND_EASE_OUT_QUINT = PathInterpolator(0.23f, 1f, 0.32f, 1f)

// The share of the send transition over which the bubble's colour comes in over the field's and the
// bubble's text takes the place of the field's
private const val SEND_CROSSFADE_SHARE = 0.4f

// Telegram leaves a question of more lines to come in with its row
private const val SEND_MAX_LINES = 10

// In dp, how far inside the bubble's body the texts show
private const val SEND_TEXT_CLIP_INSET = 4
private const val MAX_ALPHA = 255

/**
 * What a question being sent came from, for its bubble to grow out of: its text in the field, or
 * the suggestion tapped, where it stood in the window
 */
internal class AgentSentMessageSource private constructor(
    val kind: Kind,
    val frame: AgentRevealFrame
) {
    sealed interface Kind {
        /**
         * A picture of the question's text in the field, which lines up with the bubble's text, the
         * text's size and colour, and the field's frame in the window
         */
        class Text(
            val picture: Bitmap,
            val textSize: Float,
            val textColor: Int,
            val field: AgentRevealFrame
        ) : Kind

        /**
         * The suggestion tapped, which draws its pill, a picture of its title, where the title
         * stood and its size
         */
        class Suggestion(
            val card: WAgentHintView,
            val title: Bitmap,
            val titleFrame: AgentRevealFrame,
            val titleTextSize: Float
        ) : Kind
    }

    private val time = SystemClock.uptimeMillis()

    /** A source older than a second is not the sent question's any more */
    val isFresh: Boolean
        get() = SystemClock.uptimeMillis() - time < SENT_SOURCE_LIFETIME_MS

    /** Whether a new chat's first bubble may still grow out of the source */
    val isOpeningFresh: Boolean
        get() = SystemClock.uptimeMillis() - time < OPENING_SOURCE_LIFETIME_MS

    companion object {
        /**
         * The text of [textView] as it shows now, where it stands in the window, in the field drawn
         * by [field]
         */
        fun makeText(textView: TextView, field: View): AgentSentMessageSource? {
            if (!canMorph(textView)) return null
            val frame = getAgentTextFrame(textView) ?: return null
            val picture = makeAgentTextPicture(textView, frame) ?: return null
            val origin = getAgentWindowOrigin(textView)
            val fieldOrigin = getAgentWindowOrigin(field)
            val fieldFrame = AgentRevealFrame(
                fieldOrigin.x,
                fieldOrigin.y,
                fieldOrigin.x + field.width,
                fieldOrigin.y + field.height
            )
            return AgentSentMessageSource(
                Kind.Text(picture, textView.textSize, textView.currentTextColor, fieldFrame),
                frame.offsetBy(origin.x, origin.y)
            )
        }

        /**
         * The suggestion [card] as it is laid out in the window, its title drawn without a press it
         * may be in
         */
        fun makeSuggestion(card: WAgentHintView): AgentSentMessageSource? {
            if (!canMorph(card)) return null
            val title = card.titleView
            val titleText = getAgentTextFrame(title) ?: return null
            val picture = makeAgentTextPicture(title, titleText) ?: return null
            val titleOffset = getAgentLaidOutOffset(title, card) ?: return null
            val parent = card.parent as? View ?: return null
            val parentOrigin = getAgentWindowOrigin(parent)
            val left = parentOrigin.x + card.left - parent.scrollX
            val top = parentOrigin.y + card.top - parent.scrollY
            return AgentSentMessageSource(
                Kind.Suggestion(
                    card,
                    picture,
                    titleText.offsetBy(left + titleOffset.x, top + titleOffset.y),
                    title.textSize
                ),
                AgentRevealFrame(left, top, left + card.width, top + card.height)
            )
        }

        private fun canMorph(view: View) = WGlobalStorage.getAreAnimationsActive() &&
            view.isAttachedToWindow && view.isShown && view.width > 0 && view.height > 0
    }
}

/**
 * The clock of a morph that follows views as the chat lays them out. Each of its frames shows on
 * the window's pre-draw pass, after that frame's layout, so the morph keeps up with the views it
 * follows. A morph started before the view it goes to is laid out holds its first frame until it
 * is. It ends once its time is up, or where it stands at [cancel]. In debug builds while system
 * animations are off, it ends as it starts: it has called back and [isFinished] by the time its
 * constructor returns.
 */
internal abstract class AgentMorphClock(private val host: View, val durationMs: Long) {
    private val animator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = durationMs
        interpolator = LinearInterpolator()
        addUpdateListener { host.invalidate() }
        doOnEnd {
            if (!isFinished) {
                step(durationMs)
                finish()
            }
        }
    }
    private var frameBinding: AgentPreDrawBinding? = null
    private val endActions = mutableListOf<() -> Unit>()

    var isFinished = false
        private set

    // Debug builds jump to the end while system animations are off, to keep E2E runs fast
    private val isMoving: Boolean
        get() = !DEBUG_MODE || areSystemAnimatorsEnabled

    private val areSystemAnimatorsEnabled: Boolean
        get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled()

    /**
     * Starts the clock, once the morph shows its first frame. Until [isReady], the morph shows its
     * first frame again on each frame, holding where it starts; once [canHold] no longer allows it,
     * it ends there.
     */
    protected fun start(isReady: () -> Boolean = { true }, canHold: () -> Boolean = { true }) {
        if (!isMoving) {
            step(durationMs)
            finish()
            return
        }
        frameBinding = AgentPreDrawBinding(
            host,
            ViewTreeObserver.OnPreDrawListener {
                when {
                    isFinished -> Unit

                    animator.isStarted ->
                        step(animator.currentPlayTime.coerceAtMost(durationMs))

                    else -> {
                        step(0)
                        if (isReady()) {
                            animator.start()
                        } else if (!canHold()) {
                            finish()
                        }
                    }
                }
                true
            }
        )
        if (isReady()) animator.start()
    }

    fun setPaused(isPaused: Boolean) {
        if (isPaused) animator.pause() else animator.resume()
    }

    fun cancel() = finish()

    /** Runs [action] as the morph ends, at once if it has */
    fun doOnEnd(action: () -> Unit) {
        if (isFinished) action() else endActions += action
    }

    private fun finish() {
        if (isFinished) return
        isFinished = true
        animator.removeAllUpdateListeners()
        animator.removeAllListeners()
        animator.cancel()
        frameBinding?.release()
        frameBinding = null
        onFinish()
        val actions = endActions.toList()
        endActions.clear()
        actions.forEach { it() }
    }

    /** Shows the morph [elapsedMs] into its time */
    protected abstract fun step(elapsedMs: Long)

    /** Puts what the morph showed back as it is without it */
    protected abstract fun onFinish()
}

/**
 * Telegram Android's send transition, after its `TextMessageEnterTransition`: the sent question's
 * bubble comes out of the field. Over 0.25 s, or the time of a screen transition it plays over,
 * the bubble's shape grows out of the field's, in the field's colour, with the bubble's own colour
 * coming in over it in the first 40%, and the text goes from the field onto the bubble's text,
 * from the field's size to the bubble's, as its colour turns into the bubble's text colour and the
 * bubble's text takes its place. Up and down they go on the curve Telegram's list moves the row
 * on; across and in size, on its eased quintic ease-out. They follow the bubble wherever the chat
 * lays it out meanwhile, as when it brings the question up under the header, under which they
 * stay, or as a new chat comes in with it, but never below the field: a row still under it holds
 * the text on its line. Until the chat lays the bubble out, the text holds in the field, as long as
 * its source lasts. The row stays out of sight while the transition draws it.
 */
internal class AgentSentMessageFlight private constructor(
    private val host: ViewGroup,
    private val findCell: () -> AgentMessageCell?,
    private val source: AgentSentMessageSource,
    private val from: AgentSendTransitionEnd,
    private val drawing: Drawing,
    durationMs: Long,
    private val onEnd: () -> Unit
) : AgentMorphClock(host, durationMs) {
    private val isRightToLeft = LocaleController.isRTL

    // Where the bubble was last laid out, which the transition keeps going toward meanwhile
    private var target: AgentSendTransitionEnd? = null

    // The cell whose row the transition keeps out of sight
    private var hiddenCell: AgentMessageCell? = null

    // Telegram leaves a long question to come in with its row
    private val isTooLong: Boolean
        get() = (hiddenCell?.sentTextView?.lineCount ?: 0) > SEND_MAX_LINES

    init {
        host.overlay.add(drawing)
        step(0)
        start(
            isReady = { target != null && !isTooLong },
            canHold = { source.isOpeningFresh && !isTooLong }
        )
    }

    override fun step(elapsedMs: Long) {
        val fraction = elapsedMs.toFloat() / durationMs
        val progress = SEND_LIST_CURVE.getInterpolation(fraction)
        findCell()?.let { cell ->
            updateTarget(cell)
            hideRow(cell)
        }
        if (drawing.width != host.width || drawing.height != host.height) {
            drawing.layout(0, 0, host.width, host.height)
        }
        drawing.state = calculateAgentSendTransitionState(
            from,
            raiseAgentSendTarget(from, target ?: from),
            progress,
            AGENT_EASE_OUT.getInterpolation(SEND_EASE_OUT_QUINT.getInterpolation(fraction)),
            isRightToLeft
        )
        drawing.tailGrowth = progress
        drawing.crossfade = calculateAgentSendCrossfade(elapsedMs, durationMs)
        drawing.invalidate()
    }

    private fun hideRow(cell: AgentMessageCell) {
        if (hiddenCell !== cell) hiddenCell?.sentAppearanceView?.alpha = 1f
        hiddenCell = cell
        cell.sentAppearanceView.alpha = 0f
    }

    // Where the bubble and its text are laid out in the host, without the transforms of the views
    // between them and the cell
    private fun updateTarget(cell: AgentMessageCell) {
        if (!cell.isAttachedToWindow || !cell.isLaidOut || cell.isLayoutRequested) return
        val bubble = cell.sentBubbleView
        val label = cell.sentTextView
        // A long question comes in with its row, so its text, of any length, is not pictured
        if (label.lineCount > SEND_MAX_LINES) return
        val bubbleOffset = getAgentLaidOutOffset(bubble, cell) ?: return
        val labelOffset = getAgentLaidOutOffset(label, cell) ?: return
        val textFrame = getAgentTextFrame(label) ?: return
        if (bubble.width <= 0 || bubble.height <= 0) return
        val origin = getAgentHostOrigin(cell, host)
        val left = origin.x + bubbleOffset.x
        val top = origin.y + bubbleOffset.y
        drawing.showBubble(bubble.background as? AgentBubbleDrawable, label, textFrame)
        target = AgentSendTransitionEnd(
            AgentRevealFrame(left, top, left + bubble.width, top + bubble.height),
            textFrame.offsetBy(origin.x + labelOffset.x, origin.y + labelOffset.y),
            label.textSize
        )
    }

    override fun onFinish() {
        hiddenCell?.sentAppearanceView?.alpha = 1f
        hiddenCell = null
        host.overlay.remove(drawing)
        onEnd()
    }

    /**
     * The bubble, its colour coming in over the field's, and the field's text giving way to the
     * bubble's within it, over the chat below [clipTop]
     */
    @SuppressLint("ViewConstructor")
    private class Drawing(
        context: Context,
        private val fieldText: Bitmap,
        private val fieldTextColor: Int,
        private val clipTop: Float
    ) : View(context) {
        private val fieldShape = AgentBubbleDrawable(isOutgoing = true).apply {
            setBubbleColor(WColor.SearchFieldBackground.color)
        }
        private val bubbleShape = AgentBubbleDrawable(isOutgoing = true)
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        private val pictureFrame = RectF()
        private var bubbleText: Bitmap? = null
        private var picturedTextFrame: AgentRevealFrame? = null
        private var bubbleTextColor = fieldTextColor
        private var bubbleTailProgress = 1f
        var state: AgentSendTransitionState? = null

        /** How far the bubble's tail has grown out of its corner */
        var tailGrowth = 0f

        /** How far the bubble's colour has come in, and its text taken the field's place */
        var crossfade = 0f

        init {
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        /** Takes the colour and tail of the bubble [shape] draws, and [label]'s text at [frame] */
        fun showBubble(shape: AgentBubbleDrawable?, label: TextView, frame: AgentRevealFrame) {
            if (shape != null) {
                bubbleShape.setBubbleColor(shape.bubbleColor)
                bubbleTailProgress = shape.tailProgress
            }
            bubbleTextColor = label.currentTextColor
            val pictured = picturedTextFrame
            if (pictured != null && abs(pictured.width - frame.width) <= 0.5f &&
                abs(pictured.height - frame.height) <= 0.5f
            ) {
                return
            }
            makeAgentTextPicture(label, frame)?.let {
                bubbleText = it
                picturedTextFrame = frame
            }
        }

        override fun onDraw(canvas: Canvas) {
            val state = state ?: return
            val bubble = state.bubble
            canvas.save()
            canvas.clipRect(0f, clipTop, width.toFloat(), height.toFloat())
            val tail = tailGrowth * bubbleTailProgress
            // The field's colour, under the bubble's until it has come in
            if (crossfade < 1f) drawShape(canvas, fieldShape, bubble, tail)
            bubbleShape.alpha = (crossfade * MAX_ALPHA).roundToInt()
            drawShape(canvas, bubbleShape, bubble, tail)
            // The tail hangs out of the body on the trailing side
            val tailWidth = AGENT_BUBBLE_TAIL_WIDTH.dp
            val inset = SEND_TEXT_CLIP_INSET.dp
            val leadingInset = if (LocaleController.isRTL) inset + tailWidth else inset
            val trailingInset = if (LocaleController.isRTL) inset else inset + tailWidth
            canvas.clipRect(
                bubble.left + leadingInset,
                bubble.top + inset,
                bubble.right - trailingInset,
                bubble.bottom - inset
            )
            paint.colorFilter = PorterDuffColorFilter(
                ColorUtils.blendARGB(fieldTextColor, bubbleTextColor, crossfade),
                PorterDuff.Mode.SRC_IN
            )
            paint.alpha = ((1f - crossfade) * MAX_ALPHA).roundToInt()
            drawPicture(canvas, fieldText, state.fieldText)
            bubbleText?.let {
                paint.colorFilter = null
                paint.alpha = (crossfade * MAX_ALPHA).roundToInt()
                drawPicture(canvas, it, state.bubbleText)
            }
            canvas.restore()
        }

        private fun drawShape(
            canvas: Canvas,
            shape: AgentBubbleDrawable,
            frame: AgentRevealFrame,
            tail: Float
        ) {
            shape.setBounds(
                frame.left.roundToInt(),
                frame.top.roundToInt(),
                frame.right.roundToInt(),
                frame.bottom.roundToInt()
            )
            shape.tailProgress = tail
            shape.draw(canvas)
        }

        private fun drawPicture(canvas: Canvas, picture: Bitmap, frame: AgentRevealFrame) {
            if (paint.alpha == 0) return
            pictureFrame.set(frame.left, frame.top, frame.right, frame.bottom)
            canvas.drawBitmap(picture, null, pictureFrame, paint)
        }
    }

    companion object {
        /**
         * Brings the bubble of the cell [findCell] finds, or null while the chat shows none, out
         * of the field of [source], over [host], which shows the transition below [clipTop], the
         * header's bottom in it. It lasts as long as a screen transition of [transitionMs] it plays
         * over, if that is longer than Telegram's own time. [onEnd] runs as the bubble takes over,
         * at the end or at [cancel]. A question of more than ten lines has none.
         */
        fun start(
            host: ViewGroup,
            findCell: () -> AgentMessageCell?,
            source: AgentSentMessageSource,
            clipTop: Float = 0f,
            transitionMs: Long = 0L,
            onEnd: () -> Unit
        ): AgentSentMessageFlight? {
            val kind = source.kind as? AgentSentMessageSource.Kind.Text ?: return null
            if (!host.isAttachedToWindow) return null
            if ((findCell()?.sentTextView?.lineCount ?: 0) > SEND_MAX_LINES) return null
            val origin = getAgentWindowOrigin(host)
            val field = kind.field.offsetBy(-origin.x, -origin.y)
            // The bubble's body starts as the field, its tail growing out of the field's trailing
            // side
            val tailWidth = AGENT_BUBBLE_TAIL_WIDTH.dp
            val bubble = if (LocaleController.isRTL) {
                field.copy(left = field.left - tailWidth)
            } else {
                field.copy(right = field.right + tailWidth)
            }
            val from = AgentSendTransitionEnd(
                bubble,
                source.frame.offsetBy(-origin.x, -origin.y),
                kind.textSize
            )
            val drawing = Drawing(host.context, kind.picture, kind.textColor, clipTop).apply {
                layout(0, 0, host.width, host.height)
            }
            return AgentSentMessageFlight(
                host,
                findCell,
                source,
                from,
                drawing,
                calculateAgentSendDurationMs(transitionMs),
                onEnd
            )
        }
    }
}

/**
 * How long the send transition lasts over a screen transition of [transitionMs]: Telegram's
 * `ChatListItemAnimator.DEFAULT_DURATION`, or the screen transition's time if longer
 */
internal fun calculateAgentSendDurationMs(transitionMs: Long): Long =
    max(SEND_DURATION_MS, transitionMs)

/**
 * How far, [elapsedMs] into the send transition of [durationMs], the bubble's colour has come in
 * and its text taken the field's place: over the first 40% of the transition, as Telegram's does
 */
internal fun calculateAgentSendCrossfade(elapsedMs: Long, durationMs: Long): Float =
    (elapsedMs.toFloat() / (durationMs * SEND_CROSSFADE_SHARE)).coerceIn(0f, 1f)

/**
 * Where the send transition starts or ends: a bubble's bounds, its tail included, and its text,
 * with the text's size
 */
internal class AgentSendTransitionEnd(
    val bubble: AgentRevealFrame,
    val text: AgentRevealFrame,
    val textSize: Float
)

/** The send transition at one moment: the bubble's bounds, and where each text shows */
internal class AgentSendTransitionState(
    val bubble: AgentRevealFrame,
    val fieldText: AgentRevealFrame,
    val bubbleText: AgentRevealFrame
)

/**
 * The send transition from the field at [start] to the bubble at [end], [progress] of the way up or
 * down and [progressX] of the way across and in size, as Telegram's `TextMessageEnterTransition`
 * moves them. The field's text and the bubble's keep their leading top corners together, sized
 * alike from the field's text size to the bubble's.
 */
internal fun calculateAgentSendTransitionState(
    start: AgentSendTransitionEnd,
    end: AgentSendTransitionEnd,
    progress: Float,
    progressX: Float,
    isRightToLeft: Boolean
): AgentSendTransitionState {
    val bubble = AgentRevealFrame(
        interpolate(start.bubble.left, end.bubble.left, progressX),
        interpolate(start.bubble.top, end.bubble.top, progress),
        interpolate(start.bubble.right, end.bubble.right, progressX),
        interpolate(start.bubble.bottom, end.bubble.bottom, progress)
    )
    val leading = interpolate(
        if (isRightToLeft) start.text.right else start.text.left,
        if (isRightToLeft) end.text.right else end.text.left,
        progressX
    )
    val top = interpolate(start.text.top, end.text.top, progress)
    // Of the bubble's text size: the field's at first
    val startScale = start.textSize / end.textSize
    val scale = interpolate(startScale, 1f, progressX)
    return AgentSendTransitionState(
        bubble,
        placeAgentSendText(
            leading,
            top,
            start.text.width * scale / startScale,
            start.text.height * scale / startScale,
            isRightToLeft
        ),
        placeAgentSendText(
            leading,
            top,
            end.text.width * scale,
            end.text.height * scale,
            isRightToLeft
        )
    )
}

/**
 * Where the send transition from the field at [start] heads for the bubble at [target]: the bubble,
 * or, while its text lies below the field's, as a row that comes in under the composer and rises as
 * the chat pins it, the bubble raised so its text stands on the field's line. The text only rises
 * out of the field, holding on its line until the row comes up past it.
 */
internal fun raiseAgentSendTarget(
    start: AgentSendTransitionEnd,
    target: AgentSendTransitionEnd
): AgentSendTransitionEnd {
    val drop = target.text.top - start.text.top
    if (drop <= 0f) return target
    return AgentSendTransitionEnd(
        target.bubble.offsetBy(0f, -drop),
        target.text.offsetBy(0f, -drop),
        target.textSize
    )
}

// A text of [width] × [height] whose leading top corner is at [leading], [top]
private fun placeAgentSendText(
    leading: Float,
    top: Float,
    width: Float,
    height: Float,
    isRightToLeft: Boolean
): AgentRevealFrame {
    val left = if (isRightToLeft) leading - width else leading
    return AgentRevealFrame(left, top, left + width, top + height)
}

internal fun interpolate(from: Float, to: Float, progress: Float) = from + (to - from) * progress

/** Where [view]'s top left corner shows in the window */
internal fun getAgentWindowOrigin(view: View): PointF {
    val location = IntArray(2)
    view.getLocationInWindow(location)
    return PointF(location[0].toFloat(), location[1].toFloat())
}

/** Where [view]'s top left corner shows in [host] */
internal fun getAgentHostOrigin(view: View, host: View): PointF {
    val origin = getAgentWindowOrigin(view)
    val hostOrigin = getAgentWindowOrigin(host)
    return PointF(origin.x - hostOrigin.x, origin.y - hostOrigin.y)
}

/** Where [view] lies in [ancestor] as laid out, without the transforms of the views between them */
internal fun getAgentLaidOutOffset(view: View, ancestor: View): PointF? {
    var x = 0f
    var y = 0f
    var current = view
    while (current !== ancestor) {
        val parent = current.parent as? View ?: return null
        x += current.left - parent.scrollX
        y += current.top - parent.scrollY
        current = parent
    }
    return PointF(x, y)
}

/** Where [textView]'s lines lie in it, within the part of it that shows text */
internal fun getAgentTextFrame(textView: TextView): AgentRevealFrame? {
    val layout = textView.layout ?: return null
    if (layout.lineCount == 0 || textView.text.isNullOrEmpty()) return null
    val originX = (textView.totalPaddingLeft - textView.scrollX).toFloat()
    val originY = (textView.totalPaddingTop - textView.scrollY).toFloat()
    var left = Float.MAX_VALUE
    var right = -Float.MAX_VALUE
    for (line in 0 until layout.lineCount) {
        left = min(left, layout.getLineLeft(line))
        right = max(right, layout.getLineRight(line))
    }
    val frame = AgentRevealFrame(
        max(originX + left, textView.compoundPaddingLeft.toFloat()),
        max(originY + layout.getLineTop(0), textView.extendedPaddingTop.toFloat()),
        min(originX + right, (textView.width - textView.compoundPaddingRight).toFloat()),
        min(
            originY + layout.getLineBottom(layout.lineCount - 1),
            (textView.height - textView.extendedPaddingBottom).toFloat()
        )
    )
    return frame.takeIf { it.width >= 1f && it.height >= 1f }
}

/**
 * A picture of [textView]'s text at [frame], from [getAgentTextFrame], without a cursor or a
 * selection
 */
internal fun makeAgentTextPicture(textView: TextView, frame: AgentRevealFrame): Bitmap? {
    val layout = textView.layout ?: return null
    val width = ceil(frame.width).toInt()
    val height = ceil(frame.height).toInt()
    if (width <= 0 || height <= 0) return null
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.translate(
        textView.totalPaddingLeft - textView.scrollX - frame.left,
        textView.totalPaddingTop - textView.scrollY - frame.top
    )
    textView.paint.color = textView.currentTextColor
    layout.draw(canvas)
    return bitmap
}

/** A view showing [picture] at [frame] in a host's overlay, which lays out nothing itself */
internal fun makeAgentPictureView(
    context: Context,
    picture: Bitmap,
    frame: AgentRevealFrame
): ImageView = ImageView(context).apply {
    scaleType = ImageView.ScaleType.FIT_XY
    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    setImageBitmap(picture)
    val left = frame.left.roundToInt()
    val top = frame.top.roundToInt()
    layout(left, top, left + picture.width, top + picture.height)
}
