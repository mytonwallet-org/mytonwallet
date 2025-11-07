package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.graphics.drawable.ShapeDrawable
import android.os.Build
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import androidx.appcompat.R
import androidx.appcompat.content.res.AppCompatResources
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.ViewHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

open class SwapSearchEditText @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = R.attr.editTextStyle,
) : WFloatingHintEditText(context, attrs, defStyle), WThemedView {

    private val backgroundDrawable: ShapeDrawable =
        ViewHelpers.roundedShapeDrawable(0, 24f.dp)
    private val searchDrawable: Drawable? =
        AppCompatResources.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_search_24
        )?.apply {
            setTint(WColor.SecondaryText.color)
        }

    init {
        setPaddingDp(52, 0, 16, 0)

        background = backgroundDrawable
        typeface = WFont.Regular.typeface
        isSingleLine = true
        isHorizontalFadingEdgeEnabled = true

        hint = LocaleController.getString("Search...")
        floatingHintGravity = Gravity.CENTER_HORIZONTAL or Gravity.CENTER_VERTICAL

        setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 22f)
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
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        canvas.translate(scrollX.toFloat(), 0f)
        searchDrawable?.draw(canvas)
        canvas.restore()
    }

    override fun updateTheme() {
        setHintTextColor(WColor.SecondaryText.color)
        setTextColor(WColor.PrimaryText.color)
        backgroundDrawable.paint.color = WColor.SearchFieldBackground.color
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
}
