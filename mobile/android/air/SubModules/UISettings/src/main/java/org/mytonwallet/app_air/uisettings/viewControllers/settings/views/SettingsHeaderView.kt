package org.mytonwallet.app_air.uisettings.viewControllers.settings.views

import android.annotation.SuppressLint
import android.text.SpannableStringBuilder
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uisettings.viewControllers.settings.SettingsVC
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcontext.utils.toString
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt


@SuppressLint("ViewConstructor")
class SettingsHeaderView(
    private val viewController: SettingsVC,
    private var topInset: Int,
) : WView(viewController.context), WThemedView, WProtectedView {

    companion object {
        const val HEIGHT_NORMAL = 168
    }

    private val normalHeight = HEIGHT_NORMAL.dp
    private val minHeight = 64.dp
    private val px10 = 10.dp
    private val px12 = 12.dp
    private val px16 = 16.dp
    private val px20 = 20.dp
    private val px32 = 32.dp
    private val px34 = 34.dp
    private val px52 = 52.dp
    private val px66 = 66.dp
    private val px74 = 74.dp

    private val walletIcon: IconView by lazy {
        val iconView = IconView(context)
        iconView.setSize(80.dp)
        iconView
    }

    private val walletNameLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(22f, WFont.Medium)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
        }
    }

    private val walletDataLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Regular)
        lbl
    }

    override fun setupViews() {
        super.setupViews()

        addView(walletIcon, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(walletNameLabel, LayoutParams(LayoutParams.MATCH_CONSTRAINT, WRAP_CONTENT))
        addView(walletDataLabel)

        setConstraints {
            toStart(walletIcon, 16f)
            toTopPx(walletIcon, topInset + 64.dp)
            toTopPx(walletNameLabel, topInset + 76.dp)
            toStart(walletNameLabel, 112f)
            toEnd(walletNameLabel)
            topToBottom(walletDataLabel, walletNameLabel, 4f)
            startToStart(walletDataLabel, walletNameLabel)
        }

        setOnClickListener {
            viewController.scrollToTop()
        }
        isClickable = false

        configure()

        updateTheme()
    }

    fun viewDidAppear() {
        walletNameLabel.isSelected = true
    }

    fun viewWillDisappear() {
        walletNameLabel.isSelected = true
    }

    @SuppressLint("SetTextI18n")
    fun configure() {
        if (parent == null)
            return

        AccountStore.activeAccount?.let {
            walletIcon.config(it, 28.dp)
        }

        configureDescriptionLabel(updateUILayoutParamsIfRequired = false)
        updateScroll(
            lastY,
            lastY != 0
        ) // Force update to prevent any ui glitches after label resizes!
    }

    fun configureDescriptionLabel(updateUILayoutParamsIfRequired: Boolean = true) {
        if (parent == null)
            return

        AccountStore.activeAccount?.name?.let {
            if (walletNameLabel.text != it)
                walletNameLabel.text = it
        }

        val balance =
            if (WGlobalStorage.getIsSensitiveDataProtectionOn())
                "***"
            else
                if (BalanceStore.getBalances(AccountStore.activeAccountId)?.get("toncoin") != null)
                    BalanceStore.totalBalanceInBaseCurrency(AccountStore.activeAccountId!!)
                        ?.toString(
                            WalletCore.baseCurrency?.decimalsCount ?: 2,
                            WalletCore.baseCurrency?.sign ?: "",
                            WalletCore.baseCurrency?.decimalsCount ?: 9,
                            true
                        ) else null
        val address = AccountStore.activeAccount?.firstAddress?.formatStartEndAddress()
        walletDataLabel.text =
            SpannableStringBuilder(if (balance != null) "$balance • $address" else "$address").apply {
                updateDotsTypeface()
            }

        if (updateUILayoutParamsIfRequired && lastY != 0)
            updateWalletDataLayoutParams() // Force update to prevent any ui glitches after label resizes!
    }

    override fun updateTheme() {
        updateBackgroundColor()
        walletNameLabel.setTextColor(WColor.PrimaryText.color)
        walletDataLabel.setTextColor(WColor.SecondaryText.color)
    }

    override fun updateProtectedView() {
        configureDescriptionLabel()
    }

    private fun updateBackgroundColor() {
        val alpha =
            min(
                1f,
                (contentHeight - minHeight) / ViewConstants.GAP.dp.toFloat()
            )
        if (alpha == 0f || (ThemeManager.uiMode.hasRoundedCorners && alpha == 1f)) {
            background = null
        } else {
            setBackgroundColor(
                (if (ThemeManager.uiMode.hasRoundedCorners) WColor.SecondaryBackground else WColor.Background).color.colorWithAlpha(
                    (alpha * 255).roundToInt()
                )
            )
        }
    }

    private var isFullyCollapsed = false
        set(value) {
            if (field == value)
                return
            field = value
            isClickable = isFullyCollapsed
        }
    private var lastY = 0
    private var expandPercentage = 1f
    private var contentHeight = normalHeight
    fun updateScroll(dy: Int, forceUpdate: Boolean = false) {
        if (lastY == dy && !forceUpdate)
            return
        lastY = dy
        contentHeight =
            (normalHeight - dy).coerceAtLeast(minHeight)
        expandPercentage = (contentHeight - minHeight.toFloat()) / (normalHeight - minHeight)
        val newIsCollapsed = expandPercentage == 0f
        if (isFullyCollapsed && newIsCollapsed)
            return
        isFullyCollapsed = newIsCollapsed

        // Update wallet icon view
        walletIcon.scaleX = min(1f, 0.5f + expandPercentage / 2)
        walletIcon.scaleY = walletIcon.scaleX
        // px20 is the offset, because of scaling the icon
        walletIcon.y = topInset + px12 + expandPercentage * px52 - (1 - expandPercentage) * px20

        if (LocaleController.isRTL) {
            walletIcon.x =
                width - walletIcon.width - (px16 - max(0f, (1 - expandPercentage) * px20))
        } else {
            walletIcon.x = px16 - max(0f, (1 - expandPercentage) * px20)
        }

        // Update wallet name and detail view
        walletNameLabel.scaleX = min(1f, (16 + expandPercentage * (22 - 16)) / 22)
        walletNameLabel.scaleY = walletNameLabel.scaleX
        walletNameLabel.y =
            topInset + px10 + px66 * expandPercentage - (walletNameLabel.height / 2 * (1 - walletNameLabel.scaleY))

        if (LocaleController.isRTL) {
            val labelX =
                width - walletNameLabel.width - (walletIcon.height * walletIcon.scaleY + px32 - (walletNameLabel.width / 2 * (1 - walletNameLabel.scaleX)))
            walletNameLabel.x = labelX
        } else {
            walletNameLabel.x =
                walletIcon.height * walletIcon.scaleY + px32 - (walletNameLabel.width / 2 * (1 - walletNameLabel.scaleX))
        }
        updateWalletDataLayoutParams()

        // update header height
        val lp = layoutParams
        lp.height = topInset + contentHeight
        layoutParams = lp

        updateBackgroundColor()
    }

    private fun updateWalletDataLayoutParams() {
        walletDataLabel.scaleX = min(1f, (14 + expandPercentage * 2) / 16)
        walletDataLabel.scaleY = walletDataLabel.scaleX
        walletDataLabel.y =
            topInset + px34 + px74 * expandPercentage - (walletDataLabel.height / 2 * (1 - walletDataLabel.scaleY))

        if (LocaleController.isRTL) {
            val labelX =
                width - walletDataLabel.width - (walletIcon.height * walletIcon.scaleY + px32 - (walletDataLabel.width / 2 * (1 - walletDataLabel.scaleX)))
            walletDataLabel.x = labelX
        } else {
            walletDataLabel.x =
                walletIcon.height * walletIcon.scaleY + px32 - (walletDataLabel.width / 2 * (1 - walletDataLabel.scaleX))
        }
    }

}
