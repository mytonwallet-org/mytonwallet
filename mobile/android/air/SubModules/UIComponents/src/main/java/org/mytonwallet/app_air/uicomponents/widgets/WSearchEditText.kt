package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.graphics.drawable.ShapeDrawable
import android.os.Build
import android.util.AttributeSet
import android.util.TypedValue
import androidx.appcompat.R
import androidx.appcompat.content.res.AppCompatResources
import androidx.appcompat.widget.AppCompatEditText
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.ViewHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color

class SwapSearchEditText @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = R.attr.editTextStyle,
) : AppCompatEditText(context, attrs, defStyle), WThemedView {

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

        setHint(LocaleController.getString("Search..."))

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
        searchDrawable?.draw(canvas)
    }

    override fun updateTheme() {
        setHintTextColor(WColor.SecondaryText.color)
        setTextColor(WColor.PrimaryText.color)
        backgroundDrawable.paint.color = WColor.SearchFieldBackground.color
    }
}
