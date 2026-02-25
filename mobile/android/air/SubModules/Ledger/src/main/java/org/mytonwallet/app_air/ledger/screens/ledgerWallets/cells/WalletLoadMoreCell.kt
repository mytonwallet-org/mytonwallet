package org.mytonwallet.app_air.ledger.screens.ledgerWallets.cells

import android.content.Context
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class LedgerLoadMoreCell(
    context: Context,
) : WCell(context), WThemedView {

    var onTap: (() -> Unit)? = null

    private val ripple =
        WRippleDrawable.create(0f, 0f, ViewConstants.BLOCK_RADIUS.dp, ViewConstants.BLOCK_RADIUS.dp)

    private val imageView = AppCompatImageView(context).apply {
        id = generateViewId()
    }

    private val loadMoreLabel = WLabel(context).apply {
        setStyle(16f)
        setTextColor(WColor.Tint)
        text = LocaleController.getString("Load 5 More Wallets")
    }

    init {
        background = ripple
        layoutParams.apply {
            height = 50.dp
        }
        addView(imageView)
        addView(loadMoreLabel)
        setConstraints {
            toStart(imageView, 25f)
            toCenterY(imageView)
            toCenterY(loadMoreLabel)
            toStart(loadMoreLabel, 72f)
        }

        setOnClickListener {
            onTap?.invoke()
        }

        updateTheme()
    }

    override fun updateTheme() {
        ripple.backgroundColor = WColor.Background.color
        ripple.rippleColor = WColor.SecondaryBackground.color
        imageView.setImageDrawable(
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_24
            )!!.apply {
                setTint(WColor.Tint.color)
            }
        )
    }

    fun configure() {
        updateTheme()
    }

}
