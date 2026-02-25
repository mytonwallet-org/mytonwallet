package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import androidx.appcompat.content.res.AppCompatResources
import androidx.core.graphics.withSave
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import kotlin.math.roundToInt

open class SwapSearchEditText @JvmOverloads constructor(
    context: Context,
    delegate: Delegate? = null,
    multilinePaste: Boolean = true,
) : WFloatingHintEditText(context, delegate, multilinePaste), WThemedView {

    private var viewPropertiesStateSet: ViewPropertiesStateSet = ViewPropertiesStateSet()
    private val searchDrawable: Drawable? =
        AppCompatResources.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_search_24
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

        floatingHintGravity = Gravity.CENTER_HORIZONTAL or Gravity.CENTER_VERTICAL

        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
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
        val x = 12.dp
        val y = measuredHeight / 2 - 12.dp
        searchDrawable?.setBounds(
            x, y,
            x + 24.dp,
            y + 24.dp
        )
        clearButtonTouchBounds.set(measuredWidth - 48f.dp, 0f, measuredWidth.toFloat(), 48f.dp)
        val left = clearButtonTouchBounds.left.roundToInt() + 12.dp
        val top = clearButtonTouchBounds.top.roundToInt() + 12.dp

        clearDrawableCircle?.setBounds(
            left, top,
            left + 24.dp,
            top + 24.dp
        )
        clearDrawableCross?.setBounds(
            left, top,
            left + 24.dp,
            top + 24.dp
        )
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val viewPropertiesState = viewPropertiesStateSet.current
        canvas.withSave {
            val tx = -viewPropertiesState.iconTranslationX * (12 + 24).dp
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

    fun setTextKeepCursor(newText: String) {
        val currentSelectionStart = selectionStart
        val currentSelectionEnd = selectionEnd

        setText(newText)

        if (currentSelectionStart >= 0 && currentSelectionEnd >= 0) {
            val newLength = text?.length ?: 0
            val safeStart = currentSelectionStart.coerceAtMost(newLength)
            val safeEnd = currentSelectionEnd.coerceAtMost(newLength)
            setSelection(safeStart, safeEnd)
        }
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
        val leftPadding = if (isSearchIconFixed) 44 else 16
        setPaddingDp(leftPadding, 0, 48, 0)
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
