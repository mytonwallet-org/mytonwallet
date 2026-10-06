package org.mytonwallet.app_air.uiswap.screens.tokenTrade.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
class TokenTradeKeypadView(
    context: Context,
    private val onInsert: (String) -> Unit,
    private val onDelete: () -> Unit
) : FrameLayout(context),
    WThemedView {

    private val keys = mutableListOf<KeyView>()
    private val deleteKey: KeyView

    private val rows = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
    }

    init {
        id = generateViewId()
        layoutDirection = LAYOUT_DIRECTION_LTR
        for (row in 0 until 4) {
            val columns = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
            for (column in 0 until 3) {
                val isDelete = row == 3 && column == 2
                val key = when {
                    row < 3 -> (row * 3 + column + 1).toString()
                    column == 0 -> "."
                    else -> "0"
                }
                val keyView = KeyView(context, if (isDelete) null else key)
                keyView.contentDescription =
                    if (isDelete) LocaleController.getString("Delete") else key
                keyView.setOnClickListener {
                    if (isDelete) onDelete() else onInsert(key)
                    Haptics.play(this, HapticType.LIGHT_TAP)
                }
                keys.add(keyView)
                columns.addView(
                    keyView,
                    LinearLayout.LayoutParams(0, MATCH_PARENT, 1f).apply {
                        if (column > 0) marginStart = KEY_GAP.dp
                    }
                )
            }
            rows.addView(
                columns,
                LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f).apply {
                    if (row > 0) topMargin = KEY_GAP.dp
                }
            )
        }
        deleteKey = keys.last()
        addView(rows, LayoutParams(MATCH_PARENT, MATCH_PARENT, Gravity.CENTER_HORIZONTAL))
        setDeleteEnabled(false)
        updateTheme()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val rowsWidth = minOf(width - 2 * SIDE_MARGIN.dp, MAX_WIDTH.dp).coerceAtLeast(0)
        (rows.layoutParams as LayoutParams).width = rowsWidth
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    fun setDeleteEnabled(enabled: Boolean) {
        deleteKey.isEnabled = enabled
        deleteKey.alpha = if (enabled) 1f else 0f
        deleteKey.importantForAccessibility = if (enabled) {
            IMPORTANT_FOR_ACCESSIBILITY_YES
        } else {
            IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
    }

    override fun updateTheme() {
        keys.forEach { it.updateTheme() }
    }

    /** Animates the visible key without shrinking its touch target. */
    private class KeyView(context: Context, private val title: String?) : FrameLayout(context) {
        private val pressedBackground = View(context).apply {
            alpha = 0f
        }
        private val content: View = if (title != null) {
            TextView(context).apply {
                text = title
                typeface = WFont.Regular.typeface
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
                gravity = Gravity.CENTER
                includeFontPadding = false
            }
        } else {
            ImageView(context).apply {
                setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_backspace)
                scaleType = ImageView.ScaleType.CENTER_INSIDE
            }
        }

        init {
            addView(pressedBackground, LayoutParams(MATCH_PARENT, MATCH_PARENT))
            addView(
                content,
                if (title != null) {
                    LayoutParams(MATCH_PARENT, MATCH_PARENT)
                } else {
                    LayoutParams(29.dp, 24.dp, Gravity.CENTER)
                }
            )
        }

        fun updateTheme() {
            pressedBackground.background = GradientDrawable().apply {
                cornerRadius = 16f.dp
                setColor(WColor.SecondaryBackground.color)
            }
            (content as? TextView)?.setTextColor(WColor.PrimaryText.color)
            (content as? ImageView)?.setColorFilter(WColor.PrimaryText.color)
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> setPressedAppearance(true)
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> setPressedAppearance(false)
            }
            return super.onTouchEvent(event)
        }

        private fun setPressedAppearance(pressed: Boolean) {
            if (!WGlobalStorage.getAreAnimationsActive()) {
                pressedBackground.alpha = if (pressed) 1f else 0f
                return
            }
            val scale = if (pressed) 0.88f else 1f
            val translation = if (pressed) 2f.dp else 0f
            listOf(content, pressedBackground).forEach {
                it.animate().cancel()
                it.animate()
                    .scaleX(scale)
                    .scaleY(scale)
                    .translationY(translation)
                    .setDuration(if (pressed) 100L else 200L)
                    .start()
            }
            pressedBackground.animate().alpha(if (pressed) 1f else 0f)
        }
    }

    companion object {
        const val KEY_HEIGHT = 80
        const val KEY_GAP = 8
        const val ROWS = 4
        private const val SIDE_MARGIN = 18
        private const val MAX_WIDTH = 420

        // Design height: four 80dp rows with 8dp between them.
        val preferredHeight: Int
            get() = (ROWS * KEY_HEIGHT + (ROWS - 1) * KEY_GAP).dp
    }
}
