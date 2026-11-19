package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.View.MeasureSpec.EXACTLY
import android.view.animation.PathInterpolator
import androidx.core.view.doOnPreDraw
import kotlin.math.max
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationHoldZone
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationPhase
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationState
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * The field's content while a question is recorded or recognized, as on iOS: while the finger holds the microphone,
 * what letting go there does; for a hands-free recording, the voice as a thread of light out of the stop button; and
 * "Recognizing…" while the recording becomes text, which nothing cancels.
 */
@SuppressLint("ViewConstructor")
internal class AgentDictationStrip(context: Context) :
    WFrameLayout(context),
    WThemedView {

    /** The recognition's status, for TalkBack to move to */
    val statusView: View get() = hintLabel

    /**
     * From the strip's leading edge to the centre of the recording circle, the stop button of a hands-free recording,
     * in px: the hint keeps clear of the circle, and the thread comes out of the stop button
     */
    var stopCenter = 0f
        set(value) {
            if (field == value) return
            field = value
            requestLayout()
        }

    private var state = AgentDictationState()
    private var slide = 0f
    private var slideAnimator: ValueAnimator? = null

    private val hintLabel = WLabel(context).apply {
        setStyle(TEXT_SIZE, WFont.Regular)
        gravity = Gravity.CENTER_VERTICAL or Gravity.START
        ellipsize = TextUtils.TruncateAt.END
        setSingleLine()
    }

    // It reaches past the strip's end, which the field's end clips, so it can slide on into Send
    private val ribbonView = AgentVoiceRibbonView(context)

    init {
        minimumHeight = HEIGHT.dp
        clipChildren = false
        clipToPadding = false
        addView(ribbonView, LayoutParams(LayoutParams.MATCH_PARENT, HEIGHT.dp))
        addView(hintLabel, LayoutParams(LayoutParams.WRAP_CONTENT, HEIGHT.dp))
        updateTheme()
    }

    fun render(newState: AgentDictationState) {
        val previous = state
        state = newState
        val isHolding = newState.isHolding
        val isRecognizing = newState.phase == AgentDictationPhase.RECOGNIZING
        hintLabel.visibility = if (isHolding || isRecognizing) VISIBLE else GONE
        // A held microphone tells what letting go does where the finger is
        hintLabel.text = LocaleController.getString(
            when {
                isRecognizing -> "\$agent_dictation_recognizing"
                newState.holdZone == AgentDictationHoldZone.CANCEL -> RELEASE_TO_CANCEL
                newState.holdZone == AgentDictationHoldZone.SEND -> RELEASE_TO_SEND
                else -> RELEASE_TO_STOP
            }
        )
        updateRibbon(previous)
        requestLayout()
        val isRecognitionStarting =
            isRecognizing && previous.phase != AgentDictationPhase.RECOGNIZING
        when {
            // "Recognizing…" fades in over what letting go said, as the field starts to glow
            isRecognitionStarting && isShown && isMotionOn -> fadeHintIn()

            // Its fade goes on as the recognition's state changes
            isRecognizing && !isRecognitionStarting -> Unit

            !isHolding -> {
                slideAnimator?.cancel()
                hintLabel.animate().cancel()
                applySlide(0f, alpha = 1f)
            }

            // Starts from its first frame, once the strip is laid out
            !previous.isHolding && isAttachedToWindow && isShown && isMotionOn ->
                doOnPreDraw { slideHintIn() }
        }
    }

    /**
     * The thread comes out of the stop button as a hands-free recording starts. As it ends, the thread gathers back
     * into the button for a transcript to go into the field, slides into Send for one to be sent, or fades otherwise.
     */
    private fun updateRibbon(previous: AgentDictationState) {
        ribbonView.setLevel(state.peakLevel)
        val wasHandsFree = previous.isHandsFreeRecording
        val isHandsFree = state.isHandsFreeRecording
        if (wasHandsFree == isHandsFree) return
        when {
            isHandsFree -> ribbonView.start()
            state.phase != AgentDictationPhase.RECOGNIZING -> ribbonView.cancel()
            state.isSending -> ribbonView.send()
            else -> ribbonView.stop()
        }
    }

    // Once the touch is a hold, the hint comes in from behind the recording circle at the trailing end, as on iOS
    private fun slideHintIn() {
        if (!state.isHolding || !isAttachedToWindow) return
        hintLabel.animate().cancel()
        val travel = HINT_TRAVEL.dp.toFloat() * LocaleController.rtlMultiplier
        slideAnimator?.cancel()
        slideAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = HINT_SLIDE_MS
            interpolator = TELEGRAM_CURVE
            addUpdateListener {
                val progress = it.animatedValue as Float
                val elapsed = it.currentPlayTime.toFloat()
                val fade = (elapsed / HINT_FADE_MS).coerceIn(0f, 1f)
                applySlide(travel * (1 - progress), alpha = fade)
            }
            start()
        }
    }

    private fun fadeHintIn() {
        slideAnimator?.cancel()
        slideAnimator = null
        hintLabel.translationX = 0f
        hintLabel.alpha = 0f
        hintLabel.animate().alpha(1f).setDuration(RECOGNIZING_FADE_MS).start()
    }

    private fun applySlide(value: Float, alpha: Float) {
        slide = value
        hintLabel.translationX = slide
        hintLabel.alpha = alpha
    }

    private val isMotionOn: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled())

    override fun onDetachedFromWindow() {
        slideAnimator?.cancel()
        hintLabel.animate().cancel()
        applySlide(0f, alpha = 1f)
        super.onDetachedFromWindow()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = HEIGHT.dp
        val exactHeight = MeasureSpec.makeMeasureSpec(height, EXACTLY)
        val ribbonWidth = computeRibbonWidth(width)
        val hintWidth = computeHintWidth(width)
        ribbonView.measure(MeasureSpec.makeMeasureSpec(ribbonWidth, EXACTLY), exactHeight)
        hintLabel.measure(MeasureSpec.makeMeasureSpec(hintWidth, EXACTLY), exactHeight)
        setMeasuredDimension(width, height)
    }

    // To the field's end at least, where Send stands
    private fun computeRibbonWidth(width: Int): Int =
        max(width, (stopCenter + RIBBON_OVERHANG.dp).roundToInt())

    // The hint ends short of the circle the finger holds; "Recognizing…" has the strip to itself
    private fun computeHintWidth(width: Int): Int {
        if (stopCenter <= 0f || state.phase == AgentDictationPhase.RECOGNIZING) return width
        val end = stopCenter - (CIRCLE_RADIUS + CIRCLE_SPACING).dp
        return end.roundToInt().coerceIn(0, width)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val width = right - left
        val height = bottom - top
        val isRtl = LocaleController.isRTL
        fun place(view: View, viewWidth: Int) {
            val start = if (isRtl) width - viewWidth else 0
            view.layout(start, 0, start + viewWidth, height)
        }
        place(ribbonView, ribbonView.measuredWidth)
        place(hintLabel, hintLabel.measuredWidth)
        ribbonView.stopCenter = stopCenter
    }

    override fun updateTheme() {
        hintLabel.setTextColor(WColor.SecondaryText)
        ribbonView.updateTheme()
    }

    private companion object {
        const val HEIGHT = 48
        const val TEXT_SIZE = 15f
        const val RELEASE_TO_STOP = "\$agent_dictation_release_to_stop"
        const val RELEASE_TO_CANCEL = "\$agent_dictation_release_to_cancel"
        const val RELEASE_TO_SEND = "\$agent_dictation_release_to_send"

        // The recording circle the finger holds, and the hint's room before it, in dp
        const val CIRCLE_RADIUS = 27
        const val CIRCLE_SPACING = 8

        // Past the stop button's centre, for the thread to slide into Send
        const val RIBBON_OVERHANG = 120

        // The hint comes in from this far, in dp, on Telegram's curve, fading in quickly
        const val HINT_TRAVEL = 100
        const val HINT_SLIDE_MS = 400L
        const val HINT_FADE_MS = 100f

        // As iOS fades the strip's hint
        const val RECOGNIZING_FADE_MS = 200L

        val TELEGRAM_CURVE = PathInterpolator(0.38f, 0.7f, 0.125f, 1f)
    }
}

/** The finger holds the microphone, and the circle follows it */
private val AgentDictationState.isHolding: Boolean
    get() = phase == AgentDictationPhase.RECORDING && !locked

/** A tap's recording, from the moment it waits for the microphone until it stops */
private val AgentDictationState.isHandsFreeRecording: Boolean
    get() = locked &&
        (phase == AgentDictationPhase.PRESSING || phase == AgentDictationPhase.RECORDING)
