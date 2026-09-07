package org.mytonwallet.app_air.uisettings.viewControllers.settings.views

import android.annotation.SuppressLint
import android.text.Spanned
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.SpannableHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WSpacingSpan
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
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

@SuppressLint("ViewConstructor")
class SettingsHeaderView(private val viewController: SettingsVC, private var topInset: Int) :
    WView(viewController.context),
    WThemedView,
    WProtectedView {

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

    private val walletIcon: AccountIconView by lazy {
        AccountIconView(context, AccountIconView.Usage.ViewItem(28f.dp))
    }

    private val walletNameLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(22f, WFont.Medium)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            useCustomEmoji = true
        }
    }

    private val walletBalanceLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.Regular)
            ellipsize = TextUtils.TruncateAt.END
            setSingleLine()
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(walletIcon, LayoutParams(80.dp, 80.dp))
        addView(walletNameLabel, LayoutParams(LayoutParams.MATCH_CONSTRAINT, WRAP_CONTENT))
        addView(walletBalanceLabel, LayoutParams(LayoutParams.MATCH_CONSTRAINT, WRAP_CONTENT))

        setConstraints {
            toStart(walletIcon, 16f)
            toTopPx(walletIcon, topInset + 64.dp)
            startToEnd(walletNameLabel, walletIcon, 16f)
            toEnd(walletNameLabel)
            topToTop(walletNameLabel, walletIcon, 12f)
            startToEnd(walletBalanceLabel, walletIcon, 16f)
            toEnd(walletBalanceLabel, 20f)
            topToBottom(walletBalanceLabel, walletNameLabel, 4f)
        }

        setOnClickListener {
            viewController.scrollToTop()
        }
        isClickable = false

        configure()

        updateTheme()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        if (changed) {
            updateScroll(lastY, forceUpdate = true)
        }
    }

    fun updateTopInset(top: Int) {
        topInset = top
        setConstraints {
            toTopPx(walletIcon, topInset + 64.dp)
        }
        updateScroll(lastY, forceUpdate = true)
    }

    fun viewDidAppear() {
        walletNameLabel.isSelected = true
    }

    fun viewWillDisappear() {
        walletNameLabel.isSelected = false
    }

    @SuppressLint("SetTextI18n")
    fun configure() {
        if (parent == null) return

        configureDescriptionLabel(updateUILayoutParamsIfRequired = false)
        updateScroll(
            lastY,
            lastY != 0
        ) // Force update to prevent any ui glitches after label resizes!
    }

    fun configureDescriptionLabel(updateUILayoutParamsIfRequired: Boolean = true) {
        if (parent == null) return

        val account = AccountStore.activeAccount
        account?.let {
            walletIcon.config(it)
        }
        account?.name?.let {
            if (walletNameLabel.text != it) walletNameLabel.text = it
        }
        updateBalanceLabel(account)

        if (updateUILayoutParamsIfRequired && lastY != 0) {
            // Force an update to prevent glitches after label resizes.
            updateWalletDataLayoutParams()
        }
    }

    private fun updateBalanceLabel(account: MAccount?) {
        val balanceText =
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
        val badges = account?.let {
            SpannableHelpers.accountBadgesSpan(
                context,
                it,
                14.dp,
                4.dp,
                WColor.SecondaryText.color
            )
        }
        walletBalanceLabel.text = if (badges.isNullOrEmpty()) {
            balanceText
        } else {
            badges.apply {
                append(" ", WSpacingSpan(5.dp), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                append(balanceText ?: "")
            }
        }
    }

    override fun updateTheme() {
        updateBackgroundColor()
        walletNameLabel.setTextColor(WColor.PrimaryText.color)
        walletBalanceLabel.setTextColor(WColor.SecondaryText.color)
        updateBalanceLabel(AccountStore.activeAccount)
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
            if (field == value) return
            field = value
            isClickable = isFullyCollapsed
        }
    private var lastY = 0
    private var expandPercentage = 1f
    private var contentHeight = normalHeight
    private var isBackButtonVisible = false

    fun setBackButtonVisible(visible: Boolean) {
        if (isBackButtonVisible == visible) return
        isBackButtonVisible = visible
        updateScroll(lastY, forceUpdate = true)
    }

    fun updateScroll(dy: Int, forceUpdate: Boolean = false) {
        if (lastY == dy && !forceUpdate) return
        lastY = dy
        contentHeight =
            (normalHeight - dy).coerceAtLeast(minHeight)
        expandPercentage = (contentHeight - minHeight.toFloat()) / (normalHeight - minHeight)
        val newIsCollapsed = expandPercentage == 0f
        if (isFullyCollapsed && newIsCollapsed && !forceUpdate) return
        isFullyCollapsed = newIsCollapsed

        val collapsedContentCenterY = topInset + minHeight / 2f

        // Update wallet icon view
        walletIcon.scaleX = min(1f, 0.45f + expandPercentage / 2)
        walletIcon.scaleY = walletIcon.scaleX
        walletIcon.y =
            lerp(
                collapsedContentCenterY - walletIcon.height / 2f,
                (topInset + px16 + px48).toFloat(),
                expandPercentage
            )

        val collapsedStartOffset = if (isBackButtonVisible) {
            min(1f, (1 - expandPercentage)) * px32
        } else {
            0f
        }

        if (LocaleController.isRTL) {
            walletIcon.x =
                width - walletIcon.width -
                (px16 - max(0f, (1 - expandPercentage) * px20)) - collapsedStartOffset
        } else {
            walletIcon.x =
                px16 - max(0f, (1 - expandPercentage) * px20) + collapsedStartOffset
        }

        // Update wallet name and detail view
        walletNameLabel.y =
            lerp(
                collapsedContentCenterY - walletNameLabel.height / 2f - 1.dp,
                (topInset + px20 + px56).toFloat(),
                expandPercentage
            )

        if (LocaleController.isRTL) {
            val labelX =
                width - walletNameLabel.width -
                    (
                        walletIcon.height * walletIcon.scaleY + px32 -
                            (walletNameLabel.width / 2 * (1 - walletNameLabel.scaleX))
                        )
            walletNameLabel.x = labelX - collapsedStartOffset
        } else {
            walletNameLabel.x =
                walletIcon.height * walletIcon.scaleY + px32 -
                (walletNameLabel.width / 2 * (1 - walletNameLabel.scaleX)) +
                collapsedStartOffset
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
        walletBalanceLabel.scaleX = min(1f, (14 + expandPercentage * 2) / 16)
        walletBalanceLabel.scaleY = walletBalanceLabel.scaleX

        walletBalanceLabel.alpha = ((expandPercentage - 0.6f) / 0.4f).coerceIn(0f, 1f)

        walletBalanceLabel.y =
            topInset + px34 + px74 * expandPercentage -
            (walletBalanceLabel.height / 2 * (1 - walletBalanceLabel.scaleY))

        if (LocaleController.isRTL) {
            walletBalanceLabel.x =
                width - walletBalanceLabel.width -
                (
                    walletIcon.height * walletIcon.scaleY + px32 -
                        (walletBalanceLabel.width / 2 * (1 - walletBalanceLabel.scaleX))
                    )
        } else {
            walletBalanceLabel.x =
                walletIcon.height * walletIcon.scaleY + px32 -
                (walletBalanceLabel.width / 2 * (1 - walletBalanceLabel.scaleX))
        }
    }

    private fun updateWalletNamePadding() {
        // Interpolates end padding based on expansion state:
        // - Collapsed: 68dp = 108dp (right-side icons) − 40dp (reduced wallet icon size)
        // - Expanded: 20dp
        // The interpolation factor is walletBalanceLabel.alpha (0 = collapsed, 1 = expanded).
        val endPadding = lerp(68f.dp, px20.toFloat(), walletBalanceLabel.alpha).roundToInt()
        if (LocaleController.isRTL) {
            walletNameLabel.setPadding(endPadding, 0, 0, 0)
        } else {
            walletNameLabel.setPadding(0, 0, endPadding, 0)
        }
        walletNameLabel.isSelected = expandPercentage % 1 == 0f
    }
}
