package org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.holder

import android.content.Context
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import android.text.TextUtils
import android.text.method.LinkMovementMethod
import android.text.style.ClickableSpan
import android.text.style.ForegroundColorSpan
import android.util.TypedValue
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WSpacingSpan
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setRoundedOutline
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.TonConnectItem
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.app_air.walletcore.toAmountString

class CellHeaderSendRequest(context: Context) : WView(context) {
    var onShowUnverifiedSourceWarning: (() -> Unit)? = null

    private val backgroundImageView = AppCompatImageView(context).apply {
        id = generateViewId()
        scaleType = ImageView.ScaleType.CENTER_CROP
        setImageResource(org.mytonwallet.app_air.uicomponents.R.drawable.img_banner_bg)
        setRoundedOutline(24f.dp)
    }

    private val imageView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(12f.dp)
    }

    private val walletNameLabel = WLabel(context).apply {
        setStyle(adaptiveFontSize(), WFont.Medium)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setTextColor(WColor.TextOnTint)
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        useCustomEmoji = true
    }

    private val walletBalanceLabel = WLabel(context).apply {
        setStyle(13f, WFont.Regular)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 19f)
        setTextColor(WColor.SecondaryTextOnTint)
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        useCustomEmoji = true
    }

    private val dappNameLabel = WLabel(context).apply {
        setStyle(adaptiveFontSize(), WFont.Medium)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setTextColor(WColor.TextOnTint)
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        useCustomEmoji = true
    }

    private val dappAddressLabel = WLabel(context).apply {
        setStyle(13f, WFont.Regular)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 19f)
        setTextColor(WColor.SecondaryTextOnTint)
        setLinkTextColor(WColor.SecondaryTextOnTint.color)
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        useCustomEmoji = true
        movementMethod = LinkMovementMethod.getInstance()
        highlightColor = android.graphics.Color.TRANSPARENT
    }

    init {
        layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, 72.dp)
        addView(backgroundImageView, LayoutParams(0, 0))
        addView(imageView, LayoutParams(48.dp, 48.dp))
        addView(walletNameLabel, LayoutParams(0, WRAP_CONTENT))
        addView(walletBalanceLabel, LayoutParams(0, WRAP_CONTENT))
        addView(dappNameLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(dappAddressLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        setConstraints {
            allEdges(backgroundImageView)
            toEnd(imageView, 12f)
            toCenterY(imageView)
            toStart(walletNameLabel, 16f)
            toTop(walletNameLabel, 16f)
            toStart(walletBalanceLabel, 16f)
            toBottom(walletBalanceLabel, 15f)
            toTop(dappNameLabel, 16f)
            endToStart(dappNameLabel, imageView, 12f)
            toBottom(dappAddressLabel, 15f)
            endToStart(dappAddressLabel, imageView, 12f)
            endToStart(walletNameLabel, dappNameLabel, 4f)
            endToStart(walletBalanceLabel, dappAddressLabel, 4f)
        }
    }

    var update: ApiUpdate.ApiUpdateDappSignRequest? = null

    fun configure(
        update: ApiUpdate.ApiUpdateDappSignRequest,
        onShowUnverifiedSourceWarning: () -> Unit
    ) {
        this.update = update
        this.onShowUnverifiedSourceWarning = onShowUnverifiedSourceWarning
        update.dapp.iconUrl?.let { iconUrl ->
            imageView.set(Content.ofUrl(iconUrl))
        } ?: run {
            imageView.clear()
        }
        updateContent()

    }

    private fun updateContent() {
        val update = update ?: return
        val account = MAccount(update.accountId, WGlobalStorage.getAccount(update.accountId)!!)
        walletNameLabel.text = account.name
        walletBalanceLabel.text = formatWalletBalance(update.accountId)
        dappNameLabel.text = update.dapp.name ?: ""
        dappAddressLabel.text = buildDappAddressLabel(update)
    }

    private fun formatWalletBalance(accountId: String): String {
        val operationChain = when (val update = update) {
            is ApiUpdate.ApiUpdateDappSendTransactions -> update.operationChain
            is ApiUpdate.ApiUpdateDappSignData -> update.operationChain
            else -> null
        } ?: return ""

        val nativeSlug = MBlockchain.valueOfOrNull(operationChain)?.nativeSlug ?: return ""
        val nativeToken = TokenStore.getToken(nativeSlug) ?: return ""
        val balance = BalanceStore.getBalances(accountId)?.get(nativeSlug) ?: return ""

        return balance.toAmountString(nativeToken)
    }

    private fun buildDappAddressLabel(update: ApiUpdate.ApiUpdateDappSignRequest): CharSequence {
        return buildSpannedString {
            inSpans(ForegroundColorSpan(WColor.SecondaryTextOnTint.color)) {
                append(update.dapp.host ?: "")
            }

            if (update.dapp.isUrlEnsured != true) {
                ApplicationContextHolder.applicationContext.getDrawableCompat(
                    org.mytonwallet.app_air.walletcontext.R.drawable.ic_warning_14
                )?.let { drawable ->
                    val width = 14.dp
                    val height = 14.dp
                    drawable.setBounds(0, 0, width, height)

                    inSpans(WSpacingSpan(4.dp)) { append(" ") }
                    inSpans(
                        VerticalImageSpan(
                            drawable,
                            verticalAlignment = VerticalImageSpan.VerticalAlignment.TOP_BOTTOM
                        ),
                        object : ClickableSpan() {
                            override fun onClick(widget: android.view.View) {
                                onShowUnverifiedSourceWarning?.invoke()
                            }
                        }
                    ) { append(" ") }
                }
            }
        }
    }

    class Holder(parent: ViewGroup) : BaseListHolder<TonConnectItem.SendRequestHeader>(
        CellHeaderSendRequest(parent.context).apply {
            layoutParams = ViewGroup.LayoutParams(
                MATCH_PARENT,
                72.dp
            )
        }) {
        private val view: CellHeaderSendRequest = itemView as CellHeaderSendRequest
        override fun onBind(item: TonConnectItem.SendRequestHeader) {
            view.configure(
                item.update,
                item.onShowUnverifiedSourceWarning
            )
        }
    }
}
