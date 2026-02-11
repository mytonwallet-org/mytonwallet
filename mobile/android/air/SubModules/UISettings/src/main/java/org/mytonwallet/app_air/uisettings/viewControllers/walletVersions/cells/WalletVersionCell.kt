package org.mytonwallet.app_air.uisettings.viewControllers.walletVersions.cells

import android.content.Context
import android.text.SpannableStringBuilder
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class WalletVersionCell(
    context: Context,
) : WCell(context), WThemedView {

    private var identifier: String = ""
    var onTap: ((identifier: String) -> Unit)? = null

    private val topLeftLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
        lbl
    }

    private val bottomLeftLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(14f)
        lbl
    }

    private val rightLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
        lbl
    }

    init {
        layoutParams.apply {
            height = 72.dp
        }
        addView(topLeftLabel)
        addView(bottomLeftLabel)
        addView(rightLabel)
        setConstraints {
            toTop(topLeftLabel, 14f)
            toStart(topLeftLabel, 20f)
            toTop(bottomLeftLabel, 38f)
            toStart(bottomLeftLabel, 20f)
            toBottom(bottomLeftLabel, 14f)
            toCenterY(rightLabel)
            toEnd(rightLabel, 20f)
        }

        setOnClickListener {
            onTap?.invoke(identifier)
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        addRippleEffect(WColor.SecondaryBackground.color)
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        bottomLeftLabel.setTextColor(WColor.SecondaryText.color)
        rightLabel.setTextColor(WColor.SecondaryText.color)
    }

    private var isLast = false
    fun configure(
        walletVersion: ApiUpdate.ApiUpdateWalletVersions.Version,
        isLast: Boolean
    ) {
        this.isLast = isLast
        identifier = walletVersion.version
        topLeftLabel.text = walletVersion.version
        bottomLeftLabel.text =
            SpannableStringBuilder(walletVersion.address.formatStartEndAddress()).apply {
                styleDots()
            }
        val toncoin = TokenStore.getToken(TONCOIN_SLUG)
        toncoin?.price?.let { price ->
            rightLabel.text =
                (walletVersion.balance.doubleAbsRepresentation(toncoin.decimals) * price).toString(
                    WalletCore.baseCurrency.decimalsCount,
                    WalletCore.baseCurrency.sign,
                    WalletCore.baseCurrency.decimalsCount,
                    true
                )
        }
        updateTheme()
    }

}
