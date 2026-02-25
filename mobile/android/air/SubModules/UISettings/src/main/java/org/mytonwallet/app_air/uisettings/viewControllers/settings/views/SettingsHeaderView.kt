package org.mytonwallet.app_air.uisettings.viewControllers.settings.views

import android.annotation.SuppressLint
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WMultichainAddressLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uisettings.viewControllers.settings.SettingsVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
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
        const val HEIGHT_COLLAPSED = 64
    }

    private val normalHeight = HEIGHT_NORMAL.dp
    private val minHeight = HEIGHT_COLLAPSED.dp
    private val px16 = 16.dp
    private val px20 = 20.dp
    private val px32 = 32.dp
    private val px34 = 34.dp
    private val px48 = 48.dp
    private val px56 = 56.dp
    private val px74 = 74.dp
    private val px98 = 98.dp

    private val walletIcon: IconView by lazy {
        val iconView = IconView(context)
        iconView.setSize(80.dp)
        iconView
    }

    private val walletNameLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(22f, WFont.SemiBold)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
        }
    }

    private val walletBalanceLabel: WLabel by lazy {
        object : WLabel(context) {
            override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
                super.onSizeChanged(w, h, oldw, oldh)

                updateWalletNamePadding()
            }
        }.apply {
            setStyle(18f, WFont.Regular)
        }
    }

    private val addressLabel: WMultichainAddressLabel by lazy {
        WMultichainAddressLabel(context).apply {
            setStyle(14f, WFont.Regular)
            ellipsize = TextUtils.TruncateAt.END
            setSingleLine()
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(walletIcon, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(walletNameLabel, LayoutParams(LayoutParams.MATCH_CONSTRAINT, WRAP_CONTENT))
        addView(walletBalanceLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(addressLabel, LayoutParams(LayoutParams.MATCH_CONSTRAINT, WRAP_CONTENT))


        setConstraints {
            toStart(walletIcon, 16f)
            toTopPx(walletIcon, topInset + 64.dp)
            toEnd(walletBalanceLabel, 20f)
            centerYToCenterY(walletBalanceLabel, walletIcon)
            startToEnd(walletNameLabel, walletIcon, 16f)
            toEnd(walletNameLabel)
            topToTop(walletNameLabel, walletIcon, 12f)
            startToEnd(addressLabel, walletIcon, 16f)
            endToStart(addressLabel, walletBalanceLabel, 4f)
            topToBottom(addressLabel, walletNameLabel, 4f)
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
        walletNameLabel.isSelected = false
    }

    @SuppressLint("SetTextI18n")
    fun configure() {
        if (parent == null)
            return

        AccountStore.activeAccount?.let {
            walletIcon.config(it, 28f.dp)
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

        val account = AccountStore.activeAccount
        account?.name?.let {
            if (walletNameLabel.text != it)
                walletNameLabel.text = it
        }
        updateBalanceLabel(account)
        updateAddressLabel(account)

        if (updateUILayoutParamsIfRequired && lastY != 0)
            updateWalletDataLayoutParams() // Force update to prevent any ui glitches after label resizes!
    }

    private fun updateBalanceLabel(account: MAccount?) {
        walletBalanceLabel.text =
            if (WGlobalStorage.getIsSensitiveDataProtectionOn()) {
                "***"
            } else {
                val accountId = account?.accountId
                if (accountId != null &&
                    BalanceStore.getBalances(accountId)?.get("toncoin") != null
                ) {
                    BalanceStore.totalBalanceInBaseCurrency(accountId)?.toString(
                        WalletCore.baseCurrency.decimalsCount,
                        WalletCore.baseCurrency.sign,
                        WalletCore.baseCurrency.decimalsCount,
                        true
                    )
                } else {
                    null
                }
            }
    }

    private fun updateAddressLabel(account: MAccount?) {
        val style = when (account?.accountType) {
            MAccount.AccountType.VIEW -> WMultichainAddressLabel.settingsHeaderWalletViewStyle
            MAccount.AccountType.HARDWARE -> WMultichainAddressLabel.settingsHeaderWalletHardwareStyle
            else -> WMultichainAddressLabel.settingsHeaderWalletStyle
        }
        addressLabel.displayAddresses(account, style)
    }


    override fun updateTheme() {
        updateBackgroundColor()
        walletNameLabel.setTextColor(WColor.PrimaryText.color)
        walletBalanceLabel.setTextColor(WColor.SecondaryText.color)
        addressLabel.setTextColor(WColor.SecondaryText.color)
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
        if (alpha == 0f || alpha == 1f) {
            background = null
        } else {
            setBackgroundColor(
                WColor.SecondaryBackground.color.colorWithAlpha(
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
        walletIcon.scaleX = min(1f, 0.45f + expandPercentage / 2)
        walletIcon.scaleY = walletIcon.scaleX
        // px20 is the offset, because of scaling the icon
        walletIcon.y = topInset + px16 + expandPercentage * px48 - (1 - expandPercentage) * px20

        if (LocaleController.isRTL) {
            walletIcon.x =
                width - walletIcon.width - (px16 - max(0f, (1 - expandPercentage) * px20))
        } else {
            walletIcon.x = px16 - max(0f, (1 - expandPercentage) * px20)
        }

        // Update wallet name and detail view
        walletNameLabel.y =
            topInset + px20 + px56 * expandPercentage - (walletNameLabel.height / 2 * (1 - walletNameLabel.scaleY))

        if (LocaleController.isRTL) {
            val labelX =
                width - walletNameLabel.width - (walletIcon.height * walletIcon.scaleY + px32 - (walletNameLabel.width / 2 * (1 - walletNameLabel.scaleX)))
            walletNameLabel.x = labelX
        } else {
            walletNameLabel.x =
                walletIcon.height * walletIcon.scaleY + px32 - (walletNameLabel.width / 2 * (1 - walletNameLabel.scaleX))
        }
        updateWalletDataLayoutParams()
        updateWalletNamePadding()

        // update header height
        val lp = layoutParams
        lp.height = topInset + contentHeight
        layoutParams = lp

        updateBackgroundColor()
    }

    private fun updateWalletDataLayoutParams() {
        addressLabel.scaleX = min(1f, (14 + expandPercentage * 2) / 16)
        walletBalanceLabel.scaleX = min(1f, (14 + expandPercentage * 2) / 16)

        addressLabel.scaleY = addressLabel.scaleX
        walletBalanceLabel.scaleY = walletBalanceLabel.scaleX

        val alpha = ((expandPercentage - 0.6f) / 0.4f).coerceIn(0f, 1f)
        addressLabel.alpha = alpha
        walletBalanceLabel.alpha = alpha

        addressLabel.y =
            topInset + px34 + px74 * expandPercentage - (addressLabel.height / 2 * (1 - addressLabel.scaleY))
        walletBalanceLabel.translationY = -(1 - expandPercentage) * px74

        if (LocaleController.isRTL) {
            val addressLabelX =
                width - addressLabel.width - (walletIcon.height * walletIcon.scaleY + px32 - (addressLabel.width / 2 * (1 - addressLabel.scaleX)))
            addressLabel.x = addressLabelX
            val walletBalanceLabelX =
                width - walletBalanceLabel.width - (walletIcon.height * walletIcon.scaleY + px32 - (walletBalanceLabel.width / 2 * (1 - walletBalanceLabel.scaleX)))
            walletBalanceLabel.x = walletBalanceLabelX
        } else {
            addressLabel.x =
                walletIcon.height * walletIcon.scaleY + px32 - (addressLabel.width / 2 * (1 - addressLabel.scaleX))
            walletBalanceLabel.translationX = -(1 - expandPercentage) * px98
        }
    }

    private fun updateWalletNamePadding() {
        // Interpolates right padding based on expansion state:
        // - Collapsed: 68dp = 108dp (right-side icons) − 40dp (reduced wallet icon size)
        // - Expanded: walletBalanceLabel.width + 32dp (spacing)
        // The interpolation factor is walletBalanceLabel.alpha (0 = collapsed, 1 = expanded).
        val rightPadding =
            lerp(68f.dp, walletBalanceLabel.width + 32f.dp, walletBalanceLabel.alpha).roundToInt()
        walletNameLabel.setPadding(0, 0, rightPadding, 0)
        walletNameLabel.isSelected = expandPercentage % 1 == 0f
    }
}
