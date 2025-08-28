package org.mytonwallet.app_air.uicomponents.widgets.clearSegmentedControl

import android.content.Context
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import java.lang.Float.max

open class WClearSegmentedControlItemView(context: Context) :
    WCell(context, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT)),
    WThemedView {

    internal val textView: WLabel
    private val arrowImageView: AppCompatImageView
    val arrowDrawable = ContextCompat.getDrawable(context, R.drawable.ic_arrow_bottom_24)

    init {
        if (id == NO_ID) {
            id = generateViewId()
        }

        textView = WLabel(context).apply {
            layoutParams = LayoutParams(
                LayoutParams.WRAP_CONTENT,
                LayoutParams.WRAP_CONTENT
            ).apply {
                setStyle(16f, WFont.Medium)
                setPadding(16.dp, 5.dp, 16.dp, 5.dp)
                setSingleLine()
            }
        }

        arrowImageView = AppCompatImageView(context).apply {
            id = generateViewId()
            layoutParams = LayoutParams(
                20.dp,
                20.dp
            )
            setImageDrawable(arrowDrawable)
            alpha = 0f
            isVisible = false
        }

        addView(textView)
        addView(arrowImageView)

        setConstraints {
            toCenterX(textView)
            toEnd(arrowImageView, 8f)
            toCenterY(arrowImageView)
        }

        updateTheme()
    }

    fun configure(item: String) {
        textView.text = item
        updateTheme()
    }

    var arrowVisibility: Float = 0f
        set(value) {
            field = value

            arrowImageView.apply {
                alpha = max(0f, value - 0.7f) * 10 / 3
                isVisible = value > 0

                val endPadding = if (value > 0) {
                    16.dp + (12.dp * value).toInt()
                } else {
                    16.dp
                }

                textView.setPaddingLocalized(16.dp, 5.dp, endPadding, 5.dp)
            }
        }

    override fun updateTheme() {
        arrowDrawable?.setTint(WColor.PrimaryText.color)
    }

}
