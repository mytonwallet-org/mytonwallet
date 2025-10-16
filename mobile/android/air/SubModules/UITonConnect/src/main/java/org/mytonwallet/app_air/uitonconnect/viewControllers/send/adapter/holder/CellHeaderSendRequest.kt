package org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.holder

import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.method.LinkMovementMethod
import android.text.style.ClickableSpan
import android.text.style.ForegroundColorSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.withGradient
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WAlertLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.TonConnectItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

class CellHeaderSendRequest(context: Context) : LinearLayout(context), WThemedView {
    var onShowUnverifiedSourceWarning: (() -> Unit)? = null

    private val imageView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(20f.dp)
    }

    private val titleTextView = AppCompatTextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 26f)
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
        typeface = WFont.Medium.typeface
        movementMethod = LinkMovementMethod.getInstance()
        highlightColor = android.graphics.Color.TRANSPARENT
    }

    private val dangerousView by lazy {
        WAlertLabel(
            context,
            LocaleController.getString("\$hardware_payload_warning")
                .toProcessedSpannableStringBuilder(),
            WColor.Orange.color
        )
    }

    init {
        setPaddingDp(20, 14, 20, 12)
        orientation = VERTICAL

        addView(imageView, LayoutParams(80.dp, 80.dp).apply { gravity = Gravity.CENTER })
        addView(
            titleTextView,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = 17.dp })
        addView(
            dangerousView,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                topMargin = 14.dp
                leftMargin = 12.dp
                rightMargin = 12.dp
            }
        )
        updateTheme()
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
        updateTitleLabel()
        dangerousView.isGone = !update.isDangerous
    }

    override fun updateTheme() {
        titleTextView.setTextColor(WColor.PrimaryText.color)
    }

    private fun updateTitleLabel() {
        val update = update ?: return
        val account = MAccount(update.accountId, WGlobalStorage.getAccount(update.accountId)!!)

        val builder = SpannableStringBuilder()
        builder.append(account.name)
        builder.append(" ")

        ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.walletcontext.R.drawable.ic_relate_right
        )?.withGradient(listOf(WColor.PrimaryText.color, WColor.Tint.color).toIntArray())
            ?.let { drawable ->
                val width = 6.dp
                val height = 9.dp
                drawable.setBounds(0, 2, width, height)
                val imageSpan = VerticalImageSpan(drawable, LocaleController.isRTL)
                builder.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }

        builder.append(" ")
        builder.append(
            update.dapp.host,
            ForegroundColorSpan(WColor.Tint.color),
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        if (update.dapp.isUrlEnsured != true) {
            builder.append("\u00A0")
            ContextCompat.getDrawable(
                ApplicationContextHolder.applicationContext,
                org.mytonwallet.app_air.walletcontext.R.drawable.ic_warning
            )?.let { drawable ->
                val width = 14.dp
                val height = 26.dp
                drawable.setBounds(0, 0, width, height)
                val imageSpan = VerticalImageSpan(drawable)
                val start = builder.length
                builder.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)

                val clickableSpan = object : ClickableSpan() {
                    override fun onClick(widget: android.view.View) {
                        onShowUnverifiedSourceWarning?.invoke()
                    }
                }
                builder.setSpan(
                    clickableSpan,
                    start,
                    builder.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
        }
        titleTextView.text = builder
    }

    class Holder(parent: ViewGroup) : BaseListHolder<TonConnectItem.SendRequestHeader>(
        CellHeaderSendRequest(parent.context).apply {
            layoutParams = ViewGroup.LayoutParams(
                MATCH_PARENT,
                WRAP_CONTENT
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
