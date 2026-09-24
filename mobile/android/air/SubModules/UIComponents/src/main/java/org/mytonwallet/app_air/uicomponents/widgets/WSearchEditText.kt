package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.SystemClock
import android.text.Editable
import android.text.NoCopySpan
import android.text.Spanned
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import androidx.appcompat.content.res.AppCompatResources
import androidx.core.graphics.withSave
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp

open class WSearchEditText @JvmOverloads constructor(
    context: Context,
    delegate: Delegate? = null,
    multilinePaste: Boolean = true
) : WFloatingHintEditText(context, delegate, multilinePaste),
    WThemedView {

    private var viewPropertiesStateSet: ViewPropertiesStateSet = ViewPropertiesStateSet()
    private val searchDrawable: Drawable? =
        AppCompatResources.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_search_22
        )?.mutate()?.apply {
            setTint(WColor.SecondaryText.color)
        }

    var isSearchIconFixed: Boolean = false
        set(value) {
            if (field == value) return
            field = value
            updateHorizontalPaddings()
            invalidate()
        }

    private val clearButtonTouchBounds: RectF = RectF()
    private val clearDrawableCircle: Drawable? =
        AppCompatResources.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_clear_24_circle
        )?.apply {
            setTint(WColor.SecondaryText.color)
        }

    private val clearDrawableCross: Drawable? =
        AppCompatResources.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_clear_24_cross
        )

    init {
        updateHorizontalPaddings()

        typeface = WFont.Regular.typeface
        isSingleLine = true
        isHorizontalFadingEdgeEnabled = true
        textAlignment = TEXT_ALIGNMENT_VIEW_START

        floatingHintGravity = Gravity.CENTER_HORIZONTAL or Gravity.CENTER_VERTICAL

        setTextSize(TypedValue.COMPLEX_UNIT_SP, adaptiveFontSize())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        }

        setOnTouchListener { _, event ->
            if (event.action == android.view.MotionEvent.ACTION_UP) {
                performClick()
                if (viewPropertiesStateSet.current.isClearIconVisible() &&
                    clearButtonTouchBounds.contains(event.x, event.y)
                ) {
                    setText("")
                    return@setOnTouchListener true
                }
                return@setOnTouchListener performClick()
            }
            false
        }

        updateTheme()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        val isRtl = layoutDirection == LAYOUT_DIRECTION_RTL
        val searchX = if (isRtl) measuredWidth - 14.dp - 22.dp else 14.dp
        val y = measuredHeight / 2 - 11.dp
        searchDrawable?.setBounds(
            searchX,
            y,
            searchX + 22.dp,
            y + 22.dp
        )
        if (isRtl) {
            clearButtonTouchBounds.set(0f, 0f, 48f.dp, 48f.dp)
        } else {
            clearButtonTouchBounds.set(measuredWidth - 48f.dp, 0f, measuredWidth.toFloat(), 48f.dp)
        }
        val left = clearButtonTouchBounds.left.roundToInt() + 12.dp
        val top = clearButtonTouchBounds.top.roundToInt() + 12.dp

        clearDrawableCircle?.setBounds(
            left,
            top,
            left + 24.dp,
            top + 24.dp
        )
        clearDrawableCross?.setBounds(
            left,
            top,
            left + 24.dp,
            top + 24.dp
        )
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val viewPropertiesState = viewPropertiesStateSet.current
        val isRtl = layoutDirection == LAYOUT_DIRECTION_RTL
        canvas.withSave {
            val translationMagnitude = viewPropertiesState.iconTranslationX * (12 + 24).dp
            val tx = if (isRtl) translationMagnitude else -translationMagnitude
            translate(tx + scrollX.toFloat(), 0f)
            searchDrawable?.apply {
                alpha = (viewPropertiesState.iconAlpha * 255).roundToInt()
                draw(canvas)
            }
        }
        canvas.withSave {
            translate(scrollX.toFloat(), 0f)
            scale(
                viewPropertiesState.clearIconScale,
                viewPropertiesState.clearIconScale,
                clearButtonTouchBounds.centerX(),
                clearButtonTouchBounds.centerY()
            )
            if (viewPropertiesState.isClearIconVisible()) {
                clearDrawableCircle?.draw(canvas)
                clearDrawableCross?.draw(canvas)
            }
        }
    }

    override fun updateTheme() {
        setHintTextColor(WColor.SecondaryText.color)
        setTextColor(WColor.PrimaryText.color)
    }

    private companion object {
        const val SELECTION_TOUCH_WINDOW_MS = 500L
    }

    private val autoCompleteSuffixMarker = NoCopySpan.Concrete()
    private var autoCompleteSuffix: CharSequence? = null
    private var autoCompleteSuffixSpans: Array<out Any> = emptyArray()

    /**
     * Start of the inline autocomplete suffix, or -1 when none is attached.
     * Typing over the selected suffix stretches the marker span, so it only counts while it
     * still wraps the suffix. An IME rewrite can drop the marker with the suffix still in
     * place, so the suffix stays attached while the text ends with it.
     */
    fun autoCompleteSuffixStart(): Int {
        val editable = text ?: return -1
        val suffix = autoCompleteSuffix?.toString() ?: return -1
        val start = editable.getSpanStart(autoCompleteSuffixMarker)
        val end = editable.getSpanEnd(autoCompleteSuffixMarker)
        if (start >= 0 && end > start && editable.substring(start, end) == suffix) return start
        val restoredStart = editable.length - suffix.length
        if (restoredStart >= 0 && editable.substring(restoredStart) == suffix) {
            attachAutoCompleteSuffixSpans(editable, restoredStart)
            return restoredStart
        }
        clearAutoCompleteSuffixSpans(editable)
        return -1
    }

    /** The text without the autocomplete suffix; an IME can leave typed text after it. */
    fun typedText(): String {
        val editable = text ?: return ""
        val start = autoCompleteSuffixStart()
        if (start < 0) return editable.toString()
        val end = editable.getSpanEnd(autoCompleteSuffixMarker)
        return editable.substring(0, start) + editable.substring(end)
    }

    fun autoCompleteSuffixText(): String? =
        if (autoCompleteSuffixStart() >= 0) autoCompleteSuffix?.toString() else null

    private var lastTouchAt = 0L

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN ||
            event.actionMasked == MotionEvent.ACTION_UP
        ) {
            lastTouchAt = SystemClock.uptimeMillis()
        }
        return super.onTouchEvent(event)
    }

    /** IMEs move the selection on their own while composing; only a touch dismisses the suffix. */
    fun isSelectionChangeFromTouch(): Boolean =
        SystemClock.uptimeMillis() - lastTouchAt <= SELECTION_TOUCH_WINDOW_MS

    private fun attachAutoCompleteSuffixSpans(editable: Editable, start: Int) {
        autoCompleteSuffixSpans.forEach(editable::removeSpan)
        val suffix = autoCompleteSuffix ?: return
        val spanned = suffix as? Spanned
        autoCompleteSuffixSpans = spanned?.getSpans(0, suffix.length, Any::class.java).orEmpty()
        autoCompleteSuffixSpans.forEach { span ->
            editable.setSpan(
                span,
                start + spanned!!.getSpanStart(span),
                start + spanned.getSpanEnd(span),
                spanned.getSpanFlags(span)
            )
        }
        editable.setSpan(
            autoCompleteSuffixMarker,
            start,
            start + suffix.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }

    private fun clearAutoCompleteSuffixSpans(editable: Editable) {
        editable.removeSpan(autoCompleteSuffixMarker)
        autoCompleteSuffixSpans.forEach(editable::removeSpan)
        autoCompleteSuffixSpans = emptyArray()
        autoCompleteSuffix = null
    }

    fun appendAutoCompleteSuffix(suffix: CharSequence) {
        val editable = text ?: return
        removeAutoCompleteSuffix()
        val start = editable.length
        editable.append(suffix.toString())
        autoCompleteSuffix = suffix
        attachAutoCompleteSuffixSpans(editable, start)
        setSelection(start, editable.length)
    }

    fun removeAutoCompleteSuffix() {
        val start = autoCompleteSuffixStart()
        val editable = text ?: return
        if (start < 0) return
        val end = editable.getSpanEnd(autoCompleteSuffixMarker)
        clearAutoCompleteSuffixSpans(editable)
        editable.delete(start, end)
    }

    override fun onStartMoveToState(targetState: ViewState) {
        super.onStartMoveToState(targetState)
        viewPropertiesStateSet = viewPropertiesStateSet.copy(
            source = viewPropertiesStateSet.current.copy(),
            target = buildTargetViewPropertiesState(targetState)
        )
    }

    override fun onViewPropertiesPrimaryAnimationProgress(progress: Float) {
        super.onViewPropertiesPrimaryAnimationProgress(progress)
        viewPropertiesStateSet.applyPrimaryLerp(progress)
    }

    private fun buildTargetViewPropertiesState(targetState: ViewState): ViewPropertiesState {
        if (isSearchIconFixed) {
            return ViewPropertiesState(
                iconAlpha = 1f,
                iconTranslationX = 0f,
                clearIconScale = if (targetState.hasText) 1f else 0f
            )
        }

        return when {
            // initial
            !targetState.hasFocus && !targetState.hasText -> ViewPropertiesState()

            // focus, empty
            targetState.hasFocus && !targetState.hasText -> ViewPropertiesState(
                iconAlpha = 0f,
                iconTranslationX = 1f
            )

            // non-empty
            else -> ViewPropertiesState(
                iconAlpha = 0f,
                iconTranslationX = 1f,
                clearIconScale = 1f
            )
        }
    }

    private fun updateHorizontalPaddings() {
        val startPadding = if (isSearchIconFixed) 44 else 16
        setPaddingDpLocalized(startPadding, 0, 48, 0)
    }

    private data class ViewPropertiesState(
        var iconAlpha: Float = 1f,
        var iconTranslationX: Float = 0f,
        var clearIconScale: Float = 0f
    ) {
        fun isClearIconVisible(): Boolean = clearIconScale > 0.01f
    }

    private data class ViewPropertiesStateSet(
        val current: ViewPropertiesState = ViewPropertiesState(),
        val source: ViewPropertiesState = ViewPropertiesState(),
        val target: ViewPropertiesState = ViewPropertiesState()
    ) {
        fun applyPrimaryLerp(f: Float) {
            with(current) {
                iconAlpha = lerp(source.iconAlpha, target.iconAlpha, f)
                iconTranslationX = lerp(source.iconTranslationX, target.iconTranslationX, f)
                clearIconScale = lerp(source.clearIconScale, target.clearIconScale, f)
            }
        }
    }
}
