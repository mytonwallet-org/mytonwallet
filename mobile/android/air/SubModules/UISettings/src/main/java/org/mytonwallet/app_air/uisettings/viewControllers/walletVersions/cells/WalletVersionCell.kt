package org.mytonwallet.app_air.uisettings.viewControllers.walletVersions.cells

import android.content.Context
import android.text.SpannableStringBuilder
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletcontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcontext.utils.toString
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

    private val separator: WView by lazy {
        val v = WView(context)
        v
    }

    init {
        layoutParams.apply {
            height = 72.dp
        }
        addView(topLeftLabel)
        addView(bottomLeftLabel)
        addView(rightLabel)
        addView(separator, LayoutParams(0, 1))
        setConstraints {
            toTop(topLeftLabel, 14f)
            toStart(topLeftLabel, 20f)
            toTop(bottomLeftLabel, 38f)
            toStart(bottomLeftLabel, 20f)
            toBottom(bottomLeftLabel, 14f)
            toCenterY(rightLabel)
            toEnd(rightLabel, 20f)
            toBottom(separator)
            toCenterX(separator, 20f)
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
            if (isLast) ViewConstants.BIG_RADIUS.dp else 0f
        )
        addRippleEffect(WColor.SecondaryBackground.color)
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        bottomLeftLabel.setTextColor(WColor.SecondaryText.color)
        rightLabel.setTextColor(WColor.SecondaryText.color)
        separator.setBackgroundColor(WColor.Separator.color)
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
                updateDotsTypeface()
            }
        separator.isGone = isLast
        val toncoin = TokenStore.getToken(TONCOIN_SLUG)
        toncoin?.price?.let { price ->
            rightLabel.text =
                (walletVersion.balance.doubleAbsRepresentation(toncoin.decimals) * price).toString(
                    WalletCore.baseCurrency?.decimalsCount ?: 2,
                    WalletCore.baseCurrency?.sign ?: "",
                    WalletCore.baseCurrency?.decimalsCount ?: 2,
                    true
                )
        }
        updateTheme()
    }

}
