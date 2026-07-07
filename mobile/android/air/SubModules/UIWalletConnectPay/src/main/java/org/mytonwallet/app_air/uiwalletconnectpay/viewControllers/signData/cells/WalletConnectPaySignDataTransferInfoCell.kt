package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.signData.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
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
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat

@SuppressLint("ViewConstructor")
class WalletConnectPaySignDataTransferInfoCell(context: Context) : WCell(context), WThemedView {

    private val titleLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(17f, WFont.Regular)
        text = LocaleController.getString("Transfer Info")
    }

    private val chevron = AppCompatImageView(context).apply {
        id = generateViewId()
    }

    var onTap: (() -> Unit)? = null

    init {
        layoutParams.apply { height = 48.dp }
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(chevron, LayoutParams(24.dp, 24.dp))
        setConstraints {
            toCenterY(titleLabel)
            toStart(titleLabel, 16f)
            toCenterY(chevron)
            toEnd(chevron, 12f)
        }
        setOnClickListener { onTap?.invoke() }
        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            ViewConstants.BLOCK_RADIUS.dp
        )
        addRippleEffect(
            WColor.SecondaryBackground.color,
            ViewConstants.BLOCK_RADIUS.dp,
            ViewConstants.BLOCK_RADIUS.dp
        )
        titleLabel.setTextColor(WColor.PrimaryText.color)
        chevron.setImageDrawable(
            context.getDrawableCompat(
                org.mytonwallet.app_air.icons.R.drawable.ic_arrow_right_24
            )?.apply { setTint(WColor.SecondaryText.color) }
        )
    }
}
