package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import androidx.core.text.buildSpannedString
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WMultichainAddressLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MAccount.AccountChain
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class AccountItemView(
    context: Context,
    accountData: AccountData,
    showArrow: Boolean,
    isTrusted: Boolean,
    private val hasSeparator: Boolean,
    onSelect: () -> Unit,
) : FrameLayout(context), WThemedView {

    data class AccountData(
        val accountId: String?,
        val title: CharSequence?,
        val network: MBlockchainNetwork,
        val byChain: Map<String, AccountChain>,
        val accountType: MAccount.AccountType?,
    )

    private val iconView: AccountIconView by lazy {
        AccountIconView(context, AccountIconView.Usage.SelectableItem(14f.dp))
    }

    private val label = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setTextColor(WColor.PrimaryText)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }

    private val subtitleLabel = WMultichainAddressLabel(context).apply {
        setStyle(13f)
        setTextColor(WColor.SecondaryText)
        applyFontOffsetFix = true
    }

    private val arrowView = AppCompatImageView(context)

    private val separatorView = if (hasSeparator) View(context) else null

    private val backgroundDrawable = WRippleDrawable.create(0f).apply {
        rippleColor = WColor.BackgroundRipple.color
    }

    init {
        background = backgroundDrawable
        addView(iconView, LayoutParams(39.dp, 39.dp).apply {
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            marginStart = 10.5f.dp.roundToInt()
            bottomMargin = if (hasSeparator) 1.5f.dp.roundToInt() else 0
        })
        if (showArrow)
            addView(arrowView, LayoutParams(30.dp, 30.dp).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
                marginEnd = 8.dp
                bottomMargin = if (hasSeparator) 1.5f.dp.roundToInt() else 0
            })
        if (hasSeparator)
            addView(separatorView, LayoutParams(MATCH_PARENT, 7.dp).apply {
                gravity = Gravity.BOTTOM
            })
        val byChain = accountData.byChain
        val address = byChain[TONCOIN_SLUG]?.address ?: byChain.values.firstOrNull()?.address ?: ""
        val startMargin = 58.dp
        val endMargin = (if (showArrow) 42 else 8).dp
        accountData.title?.let {
            addView(label, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.START
                topMargin = 8.dp
                bottomMargin = if (hasSeparator) 3.5f.dp.roundToInt() else 0
                marginStart = startMargin
                marginEnd = endMargin
            })
            addView(subtitleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.START
                topMargin = 31.dp
                bottomMargin = if (hasSeparator) 5.5f.dp.roundToInt() else 2.dp
                marginStart = startMargin
                marginEnd = endMargin
            })
            label.text = accountData.title
            val style =
                if (isTrusted) {
                    when (accountData.accountType) {
                        MAccount.AccountType.VIEW -> WMultichainAddressLabel.miniCardWalletViewStyle
                        MAccount.AccountType.HARDWARE -> WMultichainAddressLabel.miniCardWalletHardwareStyle
                        else -> WMultichainAddressLabel.miniCardWalletStyle
                    }
                } else {
                    when (accountData.accountType) {
                        MAccount.AccountType.VIEW -> WMultichainAddressLabel.cardRowWalletViewStyle
                        MAccount.AccountType.HARDWARE -> WMultichainAddressLabel.cardRowWalletHardwareStyle
                        else -> WMultichainAddressLabel.cardRowWalletStyle
                    }
                }
            subtitleLabel.displayAddresses(
                accountData.network,
                accountData.accountId,
                byChain,
                style
            )
        } ?: run {
            addView(label, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                marginStart = startMargin
                marginEnd = endMargin
                bottomMargin = if (hasSeparator) 3.5f.dp.roundToInt() else 0
            })
            label.text = buildSpannedString {
                byChain.values.firstOrNull()?.address?.formatStartEndAddress(6, 6)?.let {
                    append(it)
                    styleDots()
                }
            }
        }
        iconView.config(accountData.accountId, accountData.title, address)
        updateTheme()
        setOnClickListener {
            onSelect()
        }
    }

    override fun updateTheme() {
        backgroundDrawable.rippleColor = WColor.BackgroundRipple.color
        val drawable =
            ContextCompat.getDrawable(context, R.drawable.ic_menu_arrow_right)?.apply {
                setTint(WColor.PrimaryLightText.color)
            }
        arrowView.setImageDrawable(drawable)
        separatorView?.setBackgroundColor(WColor.PopupSeparator.color)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(
            widthMeasureSpec,
            (56 + if (hasSeparator) 7 else 0).dp.exactly
        )
    }
}
