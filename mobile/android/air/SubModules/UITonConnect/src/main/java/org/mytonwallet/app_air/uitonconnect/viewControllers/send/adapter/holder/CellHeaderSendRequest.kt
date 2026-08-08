package org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.holder

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.text.Layout
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import kotlin.math.ceil
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.TonConnectItem
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiDappUrlTrustStatus
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.app_air.walletcore.toAmountString

class CellHeaderSendRequest(context: Context) :
    WView(context),
    WThemedView {
    companion object {
        const val PILL_HEIGHT = 48
        const val ICON_SIZE = 32
        private const val AVATAR_SIDE_PADDING = 8
        private const val AVATAR_TEXT_GAP = 6
        private const val TEXT_SIDE_PADDING = 16
        private const val MIN_PILLS_GAP = 16
        private const val CONNECTOR_GAP = 8f
    }

    private val walletContainerView = WView(context)
    private val dappContainerView = WView(context)
    private val connectionView = HeaderConnectionView(context)

    private val accountIconView =
        AccountIconView(context, AccountIconView.Usage.ViewItem())

    private val dappIconView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Round
    }

    private val walletBalanceLabel = WLabel(context).apply {
        setStyle(12f, WFont.Medium)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 16f)
        includeFontPadding = false
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        useCustomEmoji = true
    }

    private val walletNameLabel = WLabel(context).apply {
        setStyle(12f, WFont.Regular)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 16f)
        includeFontPadding = false
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        useCustomEmoji = true
    }

    private val dappNameLabel = WLabel(context).apply {
        setStyle(12f, WFont.Medium)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 16f)
        includeFontPadding = false
        gravity = Gravity.END
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        useCustomEmoji = true
    }

    private val dappAddressLabel = WLabel(context).apply {
        setStyle(12f, WFont.Regular)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 16f)
        includeFontPadding = false
        gravity = Gravity.END
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        compoundDrawablePadding = 4.dp
    }

    init {
        layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, 72.dp)

        addView(walletContainerView, LayoutParams(WRAP_CONTENT, PILL_HEIGHT.dp))
        addView(connectionView, LayoutParams(0, 1.dp))
        addView(dappContainerView, LayoutParams(WRAP_CONTENT, PILL_HEIGHT.dp))

        walletContainerView.addView(
            accountIconView,
            LayoutParams(ICON_SIZE.dp, ICON_SIZE.dp)
        )
        walletContainerView.addView(
            walletBalanceLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                goneStartMargin = TEXT_SIDE_PADDING.dp
            }
        )
        walletContainerView.addView(
            walletNameLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                goneStartMargin = TEXT_SIDE_PADDING.dp
            }
        )

        dappContainerView.addView(
            dappNameLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                goneEndMargin = TEXT_SIDE_PADDING.dp
            }
        )
        dappContainerView.addView(
            dappAddressLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                goneEndMargin = TEXT_SIDE_PADDING.dp
            }
        )
        dappContainerView.addView(
            dappIconView,
            LayoutParams(ICON_SIZE.dp, ICON_SIZE.dp)
        )

        setConstraints {
            toStart(walletContainerView)
            toCenterY(walletContainerView)

            startToEnd(connectionView, walletContainerView, CONNECTOR_GAP)
            endToStart(connectionView, dappContainerView, CONNECTOR_GAP)
            toCenterY(connectionView)

            toEnd(dappContainerView)
            toCenterY(dappContainerView)
        }

        walletContainerView.setConstraints {
            toStart(accountIconView, AVATAR_SIDE_PADDING.toFloat())
            toCenterY(accountIconView)

            startToEnd(walletBalanceLabel, accountIconView, AVATAR_TEXT_GAP.toFloat())
            toEnd(walletBalanceLabel, TEXT_SIDE_PADDING.toFloat())
            toTop(walletBalanceLabel, 8f)
            setHorizontalBias(walletBalanceLabel.id, 0f)

            startToEnd(walletNameLabel, accountIconView, AVATAR_TEXT_GAP.toFloat())
            toEnd(walletNameLabel, TEXT_SIDE_PADDING.toFloat())
            topToBottom(walletNameLabel, walletBalanceLabel)
            setHorizontalBias(walletNameLabel.id, 0f)
        }

        dappContainerView.setConstraints {
            toEnd(dappIconView, AVATAR_SIDE_PADDING.toFloat())
            toCenterY(dappIconView)

            toStart(dappNameLabel, TEXT_SIDE_PADDING.toFloat())
            endToStart(dappNameLabel, dappIconView, AVATAR_TEXT_GAP.toFloat())
            toTop(dappNameLabel, 8f)
            setHorizontalBias(dappNameLabel.id, 1f)

            toStart(dappAddressLabel, TEXT_SIDE_PADDING.toFloat())
            endToStart(dappAddressLabel, dappIconView, AVATAR_TEXT_GAP.toFloat())
            topToBottom(dappAddressLabel, dappNameLabel)
            setHorizontalBias(dappAddressLabel.id, 1f)
        }

        updateTheme()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val availableWidth = MeasureSpec.getSize(widthMeasureSpec)
        val walletDesiredWidth = maxOf(
            walletBalanceLabel.desiredWidth(),
            walletNameLabel.desiredWidth()
        )
        val dappDesiredWidth = maxOf(
            dappNameLabel.desiredWidth(),
            dappAddressLabel.desiredWidth()
        )

        val widthsWithAvatars = distributeLabelWidths(
            availableWidth = availableWidth,
            fixedPillContentWidth = (
                AVATAR_SIDE_PADDING +
                    ICON_SIZE +
                    AVATAR_TEXT_GAP +
                    TEXT_SIDE_PADDING
                ).dp,
            walletDesiredWidth = walletDesiredWidth,
            dappDesiredWidth = dappDesiredWidth
        )
        val shouldHideAvatars =
            walletDesiredWidth > widthsWithAvatars.first ||
                dappDesiredWidth > widthsWithAvatars.second
        accountIconView.visibility = if (shouldHideAvatars) View.GONE else View.VISIBLE
        dappIconView.visibility = if (shouldHideAvatars) View.GONE else View.VISIBLE

        val (walletMaxWidth, dappMaxWidth) = if (shouldHideAvatars) {
            distributeLabelWidths(
                availableWidth = availableWidth,
                fixedPillContentWidth = (TEXT_SIDE_PADDING * 2).dp,
                walletDesiredWidth = walletDesiredWidth,
                dappDesiredWidth = dappDesiredWidth
            )
        } else {
            widthsWithAvatars
        }

        walletBalanceLabel.maxWidth = walletMaxWidth
        walletNameLabel.maxWidth = walletMaxWidth
        dappNameLabel.maxWidth = dappMaxWidth
        dappAddressLabel.maxWidth = dappMaxWidth

        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    private fun distributeLabelWidths(
        availableWidth: Int,
        fixedPillContentWidth: Int,
        walletDesiredWidth: Int,
        dappDesiredWidth: Int
    ): Pair<Int, Int> {
        val availableLabelWidth = (
            availableWidth -
                MIN_PILLS_GAP.dp -
                fixedPillContentWidth * 2
            ).coerceAtLeast(0)

        if (walletDesiredWidth + dappDesiredWidth <= availableLabelWidth) {
            return walletDesiredWidth to dappDesiredWidth
        }

        val halfAvailableWidth = availableLabelWidth / 2
        val walletMaxWidth = when {
            walletDesiredWidth <= halfAvailableWidth -> walletDesiredWidth

            dappDesiredWidth <= halfAvailableWidth ->
                availableLabelWidth - dappDesiredWidth

            else -> halfAvailableWidth
        }
        return walletMaxWidth to availableLabelWidth - walletMaxWidth
    }

    private fun WLabel.desiredWidth(): Int =
        ceil(Layout.getDesiredWidth(text ?: "", paint).toDouble()).toInt() +
            compoundPaddingStart +
            compoundPaddingEnd

    private var update: ApiUpdate.ApiUpdateDappSignRequest? = null
    private var onShowUnverifiedSourceWarning: (() -> Unit)? = null

    fun configure(
        update: ApiUpdate.ApiUpdateDappSignRequest,
        onShowUnverifiedSourceWarning: () -> Unit
    ) {
        this.update = update
        this.onShowUnverifiedSourceWarning = onShowUnverifiedSourceWarning

        update.dapp.iconUrl?.let { iconUrl ->
            dappIconView.set(Content.ofUrl(iconUrl))
        } ?: dappIconView.clear()

        updateContent()
    }

    private fun updateContent() {
        val update = update ?: return
        val account = MAccount(update.accountId, WGlobalStorage.getAccount(update.accountId)!!)

        accountIconView.config(account)
        walletBalanceLabel.text = formatWalletBalance(update.accountId)
        walletNameLabel.text = account.name
        dappNameLabel.text = update.dapp.name ?: ""
        updateDappAddress(update)
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

    private fun updateDappAddress(update: ApiUpdate.ApiUpdateDappSignRequest) {
        val url = update.dapp.url.orEmpty()
        dappAddressLabel.text =
            update.dapp.host
                ?: url.substringAfter("://", url).substringBefore('/').substringBefore('?')

        val shouldShowWarning = update.dapp.shouldShowurlTrustStatusWarning()
        val warningDrawable = if (shouldShowWarning) {
            context.getDrawableCompat(
                if (update.dapp.resolvedUrlTrustStatus == ApiDappUrlTrustStatus.DANGEROUS) {
                    org.mytonwallet.app_air.icons.R.drawable.ic_warning_red_14
                } else {
                    org.mytonwallet.app_air.icons.R.drawable.ic_warning_14
                }
            )?.apply {
                val size = 14.dp
                setBounds(0, 0, size, size)
            }
        } else {
            null
        }

        dappAddressLabel.setCompoundDrawablesRelative(
            null,
            null,
            warningDrawable,
            null
        )
        dappAddressLabel.setOnClickListener(
            if (shouldShowWarning) {
                OnClickListener { onShowUnverifiedSourceWarning?.invoke() }
            } else {
                null
            }
        )
    }

    override fun updateTheme() {
        walletContainerView.setBackgroundColor(WColor.ThumbBackground.color, 24f.dp)
        dappContainerView.setBackgroundColor(WColor.ThumbBackground.color, 24f.dp)
        accountIconView.updateTheme()
        connectionView.updateTheme()
        walletBalanceLabel.setTextColor(WColor.PrimaryText.color)
        walletNameLabel.setTextColor(WColor.SecondaryText.color)
        dappNameLabel.setTextColor(WColor.PrimaryText.color)
        dappAddressLabel.setTextColor(WColor.SecondaryText.color)
    }

    class Holder(parent: ViewGroup) :
        BaseListHolder<TonConnectItem.SendRequestHeader>(
            CellHeaderSendRequest(parent.context).apply {
                layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, 72.dp)
            }
        ) {
        private val view = itemView as CellHeaderSendRequest

        override fun onBind(item: TonConnectItem.SendRequestHeader) {
            view.configure(item.update, item.onShowUnverifiedSourceWarning)
        }
    }

    private class HeaderConnectionView(context: Context) :
        View(context),
        WThemedView {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1f.dp
            pathEffect = DashPathEffect(floatArrayOf(5f.dp, 4f.dp), 0f)
        }

        init {
            id = generateViewId()
            updateTheme()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            canvas.drawLine(0f, height / 2f, width.toFloat(), height / 2f, paint)
        }

        override fun updateTheme() {
            paint.color = WColor.Thumb.color
            invalidate()
        }
    }
}
