package org.mytonwallet.app_air.uisettings.viewControllers.subwallets.cells

import android.content.Context
import android.view.View.GONE
import android.view.View.VISIBLE
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import androidx.core.view.isVisible

class SubwalletsHeaderCell(context: Context) : WCell(context), WThemedView {
    private val titleLabel = WLabel(context).apply {
        text = LocaleController.getString("Subwallets")
        setStyle(14f, WFont.DemiBold)
    }
    private val progressDrawable =
        RoundProgressDrawable(sizeDp = 11.5f, strokeWidthDp = 1f).also {
            it.setBounds(2.dp, 0, it.minimumWidth + 2.dp, it.minimumHeight)
        }
    private val scanningLabel = WLabel(context).apply {
        text = LocaleController.getString("Scanning...")
        setStyle(14f, WFont.Regular)
        setCompoundDrawables(progressDrawable, null, null, null)
        compoundDrawablePadding = 8.dp
        visibility = GONE
    }

    private var standalone = false

    init {
        layoutParams.apply { height = 40.dp }
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(scanningLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toStart(titleLabel, 20f)
            toTop(titleLabel, 16f)
            toEnd(scanningLabel, 20f)
            toTop(scanningLabel, 16f)
        }
        updateTheme()
    }

    override fun updateTheme() {
        val bottomRadius = if (standalone) ViewConstants.BLOCK_RADIUS.dp else 0f
        setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp, bottomRadius)
        titleLabel.setTextColor(WColor.Tint.color)
        titleLabel.isTinted = true
        scanningLabel.setTextColor(WColor.SecondaryText.color)
        progressDrawable.color = WColor.SecondaryText.color
    }

    fun configure(isLoading: Boolean, count: Int) {
        standalone = isLoading && count == 0
        when {
            isLoading -> {
                scanningLabel.animate().cancel()
                scanningLabel.alpha = 1f
                scanningLabel.setCompoundDrawables(progressDrawable, null, null, null)
                scanningLabel.text = LocaleController.getString("Scanning...")
                scanningLabel.visibility = VISIBLE
            }

            count > 0 -> {
                scanningLabel.animate().cancel()
                scanningLabel.alpha = 1f
                scanningLabel.setCompoundDrawables(null, null, null, null)
                scanningLabel.text = LocaleController.getPluralOrFormat("\$subwallets_found", count)
                scanningLabel.visibility = VISIBLE
            }

            scanningLabel.isVisible -> {
                scanningLabel.animate()
                    .alpha(0f)
                    .setDuration(300)
                    .withEndAction { scanningLabel.visibility = GONE; scanningLabel.alpha = 1f }
            }
        }
        layoutParams.height = if (standalone) 52.dp else 40.dp
        requestLayout()
        updateTheme()
    }
}
