package org.mytonwallet.app_air.uicomponents.widgets.autoComplete

import android.annotation.SuppressLint
import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.resize
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore

@SuppressLint("ViewConstructor")
class WAutoCompleteCell(context: Context, val onRemove: () -> Unit) :
    WCell(context, LayoutParams(MATCH_PARENT, 50.dp)), WThemedView {

    var onTap: ((address: MSavedAddress) -> Unit)? = null

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(15f)
            setTextColor(WColor.PrimaryText)
            isHorizontalFadingEdgeEnabled = true
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isSelected = true
        }
    }

    private val valueLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(15f)
            setTextColor(WColor.SecondaryText)
            setSingleLine()
        }
    }

    private val deleteButton: WImageButton by lazy {
        WImageButton(context).apply {
            val deleteDrawable =
                ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.app_air.uicomponents.R.drawable.ic_close // TODO:: Update this icon
                )?.resize(context, 16.dp, 16.dp)
            setImageDrawable(deleteDrawable)
            isGone = true
            setOnClickListener {
                address?.address?.let {
                    AddressStore.removeAddress(it)
                    onRemove()
                }
            }
        }
    }

    init {
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(valueLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(deleteButton, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        setConstraints {
            toEnd(deleteButton)
            toCenterY(deleteButton)
            toCenterY(valueLabel)
            endToStart(valueLabel, deleteButton, 8f)
            endToStart(titleLabel, valueLabel, 8f)
            setHorizontalBias(titleLabel.id, 0f)
            toCenterY(titleLabel)
            toStart(titleLabel)
        }

        setOnClickListener {
            address?.let { address ->
                onTap?.invoke(address)
            }
        }

        updateTheme()
    }

    private var address: MSavedAddress? = null
    private var isFirst = false
    private var isLast = false
    fun configure(address: MSavedAddress, isFirst: Boolean, isLast: Boolean) {
        this.address = address
        this.isFirst = isFirst
        this.isLast = isLast
        titleLabel.text = address.name
        val valueSpan = SpannableStringBuilder()
        if (AccountStore.activeAccount?.isMultichain == true) {
            MBlockchain.valueOf(address.chain).symbolIcon?.let {
                val drawable = ContextCompat.getDrawable(context, it)!!
                drawable.mutate()
                drawable.setTint(WColor.PrimaryLightText.color)
                val width = 12.dp
                val height = 12.dp
                drawable.setBounds(0, 0, width, height)
                val imageSpan = VerticalImageSpan(drawable)
                valueSpan.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            valueSpan.append(" ")
        }
        valueSpan.append(address.address.formatStartEndAddress(prefix = 6, suffix = 6))
        valueLabel.text = valueSpan
        if (address.isAccountAddress) {
            deleteButton.isGone = true
            setPadding(16.dp, 0, 8.dp, 0)
        } else {
            deleteButton.isGone = false
            setPadding(16.dp, 0, 16.dp, 0)
        }
        updateTheme()
    }

    override fun updateTheme() {
        addRippleEffect(
            WColor.SecondaryBackground.color,
            if (isFirst) ViewConstants.BLOCK_RADIUS.dp else 0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f,
        )
    }

}
