package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.graphics.Color
import android.text.Editable
import android.text.Spanned
import android.text.TextPaint
import android.text.style.CharacterStyle
import android.text.style.UpdateAppearance
import android.view.Choreographer
import android.view.animation.AnimationUtils
import android.widget.EditText
import androidx.core.graphics.ColorUtils
import java.text.BreakIterator
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

/**
 * A transcript brought into [field] character by character, as iOS's `AgentDictationTextReveal` brings it: each
 * character comes out of a blur in the accent colour, transparent and blurred, sharp within 150 ms, and then turns to
 * the text colour over 500 ms. Its characters, spaces among them, come 6 ms apart, closer for a long transcript so the
 * last starts within 0.8 s, and the field grows with them. Until the last character is in, the field takes no other
 * edits.
 */
internal class AgentTranscriptReveal(private val field: EditText) : Choreographer.FrameCallback {
    private val glyphs = ArrayList<Glyph>()
    private var appendedCount = 0
    private var startTime = 0L
    private var stepMs = 0f
    private var isFrameScheduled = false

    /** The reveal is putting its own characters in, which the field's filters let through */
    var isAppending = false
        private set

    /** Called once the reveal has ended, its last character settled or the rest put in at once */
    var onFinished: (() -> Unit)? = null

    /** Characters are coming in or settling */
    val isRunning: Boolean
        get() = glyphs.isNotEmpty()

    private val isRevealing: Boolean
        get() = appendedCount < glyphs.size

    /** Keeps the field's text as it is while characters are still to come */
    fun filterEdit(original: Spanned, start: Int, end: Int): CharSequence? =
        if (isRevealing) original.subSequence(start, end) else null

    /** Replaces the field's text with [text], character by character */
    fun start(text: String) {
        finish()
        val characters = BreakIterator.getCharacterInstance()
        characters.setText(text)
        var characterStart = characters.first()
        var characterEnd = characters.next()
        while (characterEnd != BreakIterator.DONE) {
            glyphs.add(Glyph(text.substring(characterStart, characterEnd)))
            characterStart = characterEnd
            characterEnd = characters.next()
        }
        if (glyphs.isEmpty()) return
        stepMs = if (glyphs.size > 1) {
            min(CHARACTER_STEP_MS, MAX_REVEAL_MS / (glyphs.size - 1))
        } else {
            0f
        }
        startTime = AnimationUtils.currentAnimationTimeMillis()
        appendGlyphs(count = 1)
        scheduleFrame()
    }

    /** Puts any characters still to come in at once and ends the animation, leaving plain text */
    fun finish() {
        if (glyphs.isEmpty()) return
        appendGlyphs(count = glyphs.size)
        Choreographer.getInstance().removeFrameCallback(this)
        isFrameScheduled = false
        removeSpans()
        glyphs.clear()
        appendedCount = 0
        onFinished?.invoke()
    }

    override fun doFrame(frameTimeNanos: Long) {
        isFrameScheduled = false
        if (glyphs.isEmpty()) return
        val elapsed = (AnimationUtils.currentAnimationTimeMillis() - startTime).toFloat()
        val due = if (stepMs > 0f) 1 + (elapsed / stepMs).toInt() else glyphs.size
        appendGlyphs(count = min(due, glyphs.size))
        val editable = field.text ?: return finish()
        val accent = WColor.Tint.color
        var isSettling = false
        for (index in 0 until appendedCount) {
            val span = glyphs[index].span ?: continue
            val age = elapsed - index * stepMs
            // In iOS's steps: twelfths of the way to sharp, then twentieths of the way to the text colour
            val sharpness = ((age / SHARPEN_MS).coerceIn(0f, 1f) * SHARPNESS_STEPS).roundToInt()
            val toText = (((age - SHARPEN_MS) / TO_TEXT_MS).coerceIn(0f, 1f) * TO_TEXT_STEPS)
                .roundToInt()
            if (toText < TO_TEXT_STEPS) isSettling = true
            if (!span.update(sharpness, toText, accent)) continue
            // Setting the span again redraws its character, which the field's cached text doesn't do by itself
            val start = editable.getSpanStart(span)
            val end = editable.getSpanEnd(span)
            if (start >= 0) editable.setSpan(span, start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        if (isRevealing || isSettling) {
            scheduleFrame()
        } else {
            finish()
        }
    }

    private fun scheduleFrame() {
        if (isFrameScheduled) return
        isFrameScheduled = true
        Choreographer.getInstance().postFrameCallback(this)
    }

    private fun appendGlyphs(count: Int) {
        if (appendedCount >= count) return
        val editable = field.text ?: return
        isAppending = true
        try {
            while (appendedCount < count) {
                val glyph = glyphs[appendedCount]
                // The first character takes the place of the draft
                val start = if (appendedCount == 0) 0 else editable.length
                editable.replace(start, editable.length, glyph.text)
                glyph.span?.let { span ->
                    span.update(sharpness = 0, toText = 0, accent = WColor.Tint.color)
                    editable.setSpan(
                        span,
                        start,
                        start + glyph.text.length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
                appendedCount++
            }
            field.setSelection(editable.length)
        } finally {
            isAppending = false
        }
    }

    private fun removeSpans() {
        val editable: Editable = field.text ?: return
        for (glyph in glyphs) glyph.span?.let(editable::removeSpan)
    }

    // A space shows nothing, so it takes its step without a look of its own
    private class Glyph(val text: String) {
        val span = if (text.isBlank()) null else RevealSpan(blur = BLUR.dp)
    }

    /**
     * A character's look: [sharpness] twelfths of the way out of its blur, transparent and in the accent colour, and
     * then [toText] twentieths of the way to the text colour
     */
    private class RevealSpan(private val blur: Float) :
        CharacterStyle(),
        UpdateAppearance {
        private var sharpness = 0
        private var toText = 0
        private var accent = 0

        /** False when the character looks as it did */
        fun update(sharpness: Int, toText: Int, accent: Int): Boolean {
            if (this.sharpness == sharpness && this.toText == toText && this.accent == accent) {
                return false
            }
            this.sharpness = sharpness
            this.toText = toText
            this.accent = accent
            return true
        }

        override fun updateDrawState(paint: TextPaint) {
            val sharp = sharpness / SHARPNESS_STEPS.toFloat()
            val color = ColorUtils.blendARGB(accent, paint.color, toText / TO_TEXT_STEPS.toFloat())
            val glyphAlpha = MIN_GLYPH_ALPHA + (1 - MIN_GLYPH_ALPHA) * sharp
            paint.color = ColorUtils.setAlphaComponent(
                color,
                (Color.alpha(color) * glyphAlpha).roundToInt()
            )
            // A blur of the character in the accent colour, as strong as the character is opaque: UIKit's shadow
            // blur is twice its gaussian's sigma, and Skia's shadow radius r blurs with a sigma of 0.57735 r + 0.5
            val sigma = blur / 2 * (1 - sharp)
            val radius = (sigma - SKIA_SIGMA_OFFSET) / SKIA_SIGMA_SCALE
            if (radius <= 0f) return
            val shadowAlpha = SHADOW_ALPHA * (1 - sharp) * glyphAlpha * Color.alpha(accent)
            paint.setShadowLayer(
                radius,
                0f,
                0f,
                ColorUtils.setAlphaComponent(accent, shadowAlpha.roundToInt())
            )
        }
    }

    private companion object {
        const val CHARACTER_STEP_MS = 6f
        const val MAX_REVEAL_MS = 800f
        const val SHARPEN_MS = 150f
        const val TO_TEXT_MS = 500f
        const val SHARPNESS_STEPS = 12
        const val TO_TEXT_STEPS = 20

        // The blur's radius at its strongest, in dp, and its colour's opacity
        const val BLUR = 6f
        const val SHADOW_ALPHA = 0.9f

        // A character comes in at this opacity
        const val MIN_GLYPH_ALPHA = 0.15f

        const val SKIA_SIGMA_SCALE = 0.57735f
        const val SKIA_SIGMA_OFFSET = 0.5f
    }
}
