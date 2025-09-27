package org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells

import android.annotation.SuppressLint
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WSwitch
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.math.BigInteger
import kotlin.math.abs

@SuppressLint("ViewConstructor")
class AssetsAndActivitiesTokenCell(
    recyclerView: RecyclerView,
) : WCell(recyclerView.context, LayoutParams(MATCH_PARENT, 64.dp)),
    WThemedView {

    private lateinit var token: MToken

    private val separatorView: WBaseView by lazy {
        val sw = WBaseView(context)
        sw
    }

    private val imageView: IconView by lazy {
        val img = IconView(context)
        img
    }

    private val tokenNameLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.Medium)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isSelected = true
            isHorizontalFadingEdgeEnabled = true
        }
    }

    private val amountLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(13f)
        lbl.layoutDirection = LAYOUT_DIRECTION_LTR
        WSensitiveDataContainer(lbl, WSensitiveDataContainer.MaskConfig(0, 2, Gravity.START))
    }

    private var skipSwitchChangeListener = false
    private val switchView: WSwitch by lazy {
        val sw = WSwitch(context)
        sw.setOnCheckedChangeListener { _, isChecked ->
            if (skipSwitchChangeListener)
                return@setOnCheckedChangeListener
            setTokenVisibility(isChecked)
        }
        sw
    }

    override fun setupViews() {
        super.setupViews()

        addView(separatorView, LayoutParams(0, 1))
        addView(imageView, ViewGroup.LayoutParams(48.dp, 48.dp))
        addView(tokenNameLabel, LayoutParams(0, LayoutParams.WRAP_CONTENT))
        addView(amountLabel)
        addView(switchView)
        setConstraints {
            toTop(separatorView)
            toEnd(separatorView, 16f)
            toStart(separatorView, 72f)
            toCenterY(imageView)
            toStart(imageView, 12f)
            toTop(tokenNameLabel, 10f)
            toStart(tokenNameLabel, 72f)
            endToStart(tokenNameLabel, switchView, 8f)
            toBottom(amountLabel, 10f)
            toStart(amountLabel, 72f)
            toCenterY(switchView)
            toEnd(switchView, 20f)
        }

        setOnClickListener {
            switchView.isChecked = !switchView.isChecked
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isLast) ViewConstants.BIG_RADIUS.dp else 0f
        )
        addRippleEffect(
            WColor.SecondaryBackground.color,
            0f,
            if (isLast) ViewConstants.BIG_RADIUS.dp else 0f
        )
        tokenNameLabel.setTextColor(WColor.PrimaryText.color)
        amountLabel.contentView.setTextColor(WColor.SecondaryText.color)
        separatorView.setBackgroundColor(WColor.Separator.color)
    }

    private var isLast = false
    fun configure(
        token: MToken,
        balance: BigInteger,
        isLast: Boolean
    ) {
        this.token = token
        this.isLast = isLast
        imageView.config(token, AccountStore.activeAccount?.isMultichain == true)
        tokenNameLabel.text = token.name
        amountLabel.setMaskCols(4 + abs(token.slug.hashCode() % 8))
        amountLabel.contentView.setAmount(
            MTokenBalance.fromParameters(token, balance)!!.toBaseCurrency,
            token.decimals,
            WalletCore.baseCurrency.sign,
            WalletCore.baseCurrency.decimalsCount,
            true
        )
        skipSwitchChangeListener = true
        switchView.isChecked = !token.isHidden()
        skipSwitchChangeListener = false

        updateTheme()
    }

    private fun setTokenVisibility(visible: Boolean) {
        val data = AccountStore.assetsAndActivityData
        if (visible) {
            data.hiddenTokens.removeAll { hiddenSlug ->
                hiddenSlug == token.slug
            }
            if (!data.visibleTokens.any { hiddenSlug ->
                    hiddenSlug == token.slug
                }) {
                data.visibleTokens.add(token.slug)
            }
        } else {
            data.visibleTokens.removeAll { hiddenSlug ->
                hiddenSlug == token.slug
            }
            if (!data.hiddenTokens.any { hiddenSlug ->
                    hiddenSlug == token.slug
                }) {
                data.hiddenTokens.add(token.slug)
            }
        }

        AccountStore.updateAssetsAndActivityData(data, notify = true)
    }

}
