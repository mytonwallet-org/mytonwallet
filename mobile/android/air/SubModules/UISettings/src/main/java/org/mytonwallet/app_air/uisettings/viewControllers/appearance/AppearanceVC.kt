package org.mytonwallet.app_air.uisettings.viewControllers.appearance

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.View.generateViewId
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.constraintlayout.widget.ConstraintLayout
import java.lang.ref.WeakReference
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SwitchCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.FontFamily
import org.mytonwallet.app_air.uicomponents.helpers.FontManager
import org.mytonwallet.app_air.uicomponents.widgets.WEditableItemView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.palette.AppearancePaletteAndCardView
import org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.theme.AppearanceAppThemeView
import org.mytonwallet.app_air.uisettings.viewControllers.walletCustomization.WalletCustomizationVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MWalletCardTopLine
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.EnvironmentStore

class AppearanceVC(context: Context) :
    WViewController(context),
    WalletCore.EventObserver {
    @Suppress("PropertyName")
    override val TAG = "Appearance"

    override val shouldDisplayBottomBar = true

    private val appThemeView: AppearanceAppThemeView by lazy {
        val v = AppearanceAppThemeView(context)
        v
    }

    private val appPaletteView: AppearancePaletteAndCardView by lazy {
        AppearancePaletteAndCardView(context).apply {
            onCustomizePressed = {
                AccountStore.activeAccountId?.let { accountId ->
                    WalletCustomizationVC.create(context, accountId)?.let {
                        navigationController?.push(it)
                    }
                }
            }
            configure(AccountStore.activeAccount)
        }
    }

    private val paletteHintLabel = WLabel(context).apply {
        setStyle(13f)
        setLineHeight(18f)
        text = LocaleController.getString(
            "Customize the wallet’s card appearance and color accents the way you like."
        )
        gravity = Gravity.START
        setTextColor(WColor.SecondaryText)
    }

    private val showOnCardDropdownView = WEditableItemView(context).apply {
        id = generateViewId()
        drawable = context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_arrows_18)
        setText(WGlobalStorage.getWalletCardTopLine().displayName)
    }
    private val showOnCardRow: KeyValueRowView by lazy {
        KeyValueRowView(
            context,
            LocaleController.getString("Show on Card"),
            "",
            KeyValueRowView.Mode.PRIMARY,
            isLast = false
        ).apply {
            setValueView(showOnCardDropdownView)
            setOnClickListener {
                WMenuPopup.present(
                    showOnCardDropdownView,
                    MWalletCardTopLine.entries.map { topLine ->
                        WMenuPopup.Item(
                            null,
                            topLine.menuTitle,
                            false
                        ) {
                            if (WGlobalStorage.getWalletCardTopLine() != topLine) {
                                Logger.d(
                                    Logger.LogTag.SETTINGS,
                                    "showOnCardRow: topLine=${topLine.value}"
                                )
                                WGlobalStorage.setWalletCardTopLine(topLine)
                                showOnCardDropdownView.setText(topLine.displayName)
                                WalletCore.notifyEvent(WalletEvent.WalletCardTopLineChanged)
                            }
                        }
                    },
                    popupWidth = WRAP_CONTENT,
                    positioning = WMenuPopup.Positioning.BELOW,
                    windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                        showOnCardDropdownView,
                        roundRadius = 18f.dp
                    )
                )
            }
        }
    }

    private val actionButtonsRow = SwitchCell(
        context,
        title = LocaleController.getString("Action Buttons"),
        isChecked = !WGlobalStorage.isActionButtonsRowHidden(),
        isLast = true,
        onChange = { isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "actionButtonsRow: isChecked=$isChecked")
            WGlobalStorage.setIsActionButtonsRowHidden(!isChecked)
            WalletCore.notifyEvent(WalletEvent.ActionButtonsRowChanged)
        }
    )

    private val walletCardHintLabel = WLabel(context).apply {
        setStyle(13f)
        setLineHeight(18f)
        text = LocaleController.getString("\$settings_wallet_card_description")
        gravity = Gravity.START
        setTextColor(WColor.SecondaryText)
    }

    private val appFontDropdownView = WEditableItemView(context).apply {
        id = generateViewId()
        drawable = context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_arrows_18)
        setText(FontManager.activeFont.displayName)
    }
    private val appFontView: KeyValueRowView by lazy {
        KeyValueRowView(
            context,
            LocaleController.getString("App Font"),
            "",
            KeyValueRowView.Mode.PRIMARY,
            isLast = false
        ).apply {
            setValueView(appFontDropdownView)
            setOnClickListener {
                WMenuPopup.present(
                    appFontDropdownView,
                    FontFamily.entries.map {
                        WMenuPopup.Item(
                            null,
                            it.displayName,
                            false
                        ) {
                            if (FontManager.activeFont != it) {
                                Logger.d(
                                    Logger.LogTag.SETTINGS,
                                    "appFontView: fontChanged=${it.displayName}"
                                )
                                FontManager.setActiveFont(context, it)
                                appFontDropdownView.setText(it.displayName)
                                WalletContextManager.delegate?.get()?.restartApp()
                            }
                        }
                    },
                    popupWidth = WRAP_CONTENT,
                    positioning = WMenuPopup.Positioning.BELOW,
                    windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                        appFontDropdownView,
                        roundRadius = 18f.dp
                    )
                )
            }
        }
    }

    private val roundedBalanceFontRow = SwitchCell(
        context,
        title = LocaleController.getString("Rounded Balance Font"),
        isChecked = WGlobalStorage.isRoundedBalanceFontActive(),
        isLast = true,
        onChange = { isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "roundedBalanceFontRow: isChecked=$isChecked")
            WGlobalStorage.setIsRoundedBalanceFontActive(isChecked)
            FontManager.init(context)
            WalletContextManager.delegate?.get()?.restartApp()
        }
    )

    /*private val appIconView: AppearanceAppIconView by lazy {
        val v = AppearanceAppIconView(window!!.applicationContext)
        v
    }*/

    private val topTabsRow = SwitchCell(
        context,
        title = LocaleController.getString("Top Tabs"),
        isChecked = WGlobalStorage.areTopTabsEnabled(),
        isFirst = true,
        onChange = { isChecked ->
            WGlobalStorage.setAreTopTabsEnabled(isChecked)
            WalletContextManager.delegate?.get()?.restartApp()
        }
    )

    private val gradientNavigationBarRow = SwitchCell(
        context,
        title = LocaleController.getString("Gradient Navigation Bar"),
        isChecked = WGlobalStorage.isGradientNavigationBarActive(),
        isFirst = !EnvironmentStore.isTopTabsSettingAvailable,
        onChange = { isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "gradientNavigationBarRow: isChecked=$isChecked")
            WGlobalStorage.setIsGradientNavigationBarActive(isChecked)
            pendingThemeChange = true
            WalletContextManager.delegate?.get()?.themeChanged()
            syncBottomCornerRadius()
            bottomReversedCornerView?.updateTheme()
            refreshBottomCornerRadiusHeight()
            updateScrollingContentBottomPadding()
        }
    )

    private val roundedCornersRow = SwitchCell(
        context,
        title = LocaleController.getString("Rounded Corners"),
        isChecked = WGlobalStorage.getAreRoundedCornersActive(),
        isFirst = false,
        onChange = { isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "roundedCornersRow: isChecked=$isChecked")
            WGlobalStorage.setAreRoundedCornersActive(isChecked)
            if (isChecked) {
                // Re-enable and turn on dependent settings
                roundedToolbarsRow.isEnabled = true
                sideGuttersRow.isEnabled = true
                if (!roundedToolbarsRow.isChecked) roundedToolbarsRow.isChecked = true
                if (!sideGuttersRow.isChecked) sideGuttersRow.isChecked = true
            } else {
                ViewConstants.BLOCK_RADIUS = 0f
                ViewConstants.BLOCK_RADIUS = 0f
                // Turn off and disable dependent settings
                if (roundedToolbarsRow.isChecked) roundedToolbarsRow.isChecked = false
                roundedToolbarsRow.isEnabled = false
                if (sideGuttersRow.isChecked) sideGuttersRow.isChecked = false
                sideGuttersRow.isEnabled = false
            }
            pendingThemeChange = true
            WalletContextManager.delegate?.get()?.themeChanged()
        }
    )

    private var radiusAnimator: ValueAnimator? = null
    private val roundedToolbarsRow = SwitchCell(
        context,
        title = LocaleController.getString("Rounded Toolbars"),
        isChecked = WGlobalStorage.getAreRoundedToolbarsActive(),
        onChange = { isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "roundedToolbarsRow: isChecked=$isChecked")
            val prevBarRounds = topReversedCornerView?.cornerRadius ?: 0f
            WGlobalStorage.setAreRoundedToolbarsActive(isChecked)
            ViewConstants.TOOLBAR_RADIUS = if (isChecked) 24f else 0f
            pendingThemeChange = true
            WalletContextManager.delegate?.get()?.themeChanged()
            topReversedCornerView?.animateRadius(
                prevBarRounds,
                ViewConstants.TOOLBAR_RADIUS.dp
            )
            radiusAnimator?.cancel()
            radiusAnimator = ValueAnimator.ofFloat(prevBarRounds, ViewConstants.TOOLBAR_RADIUS.dp)
                .apply {
                    duration = AnimationConstants.QUICK_ANIMATION
                    interpolator = AccelerateDecelerateInterpolator()

                    addUpdateListener { animator ->
                        val radius = animator.animatedValue as Float
                        val topItem: View = appThemeView
                        topItem.setBackgroundColor(
                            WColor.Background.color,
                            radius,
                            ViewConstants.BLOCK_RADIUS.dp
                        )
                    }

                    addListener(object : AnimatorListenerAdapter() {
                        override fun onAnimationEnd(animation: Animator) {
                            radiusAnimator = null
                        }
                    })

                    start()
                }
        }
    )

    private var sideGuttersAnimator: ValueAnimator? = null
    private val sideGuttersRow = SwitchCell(
        context,
        title = LocaleController.getString("Side Gutters"),
        isChecked = ViewConstants.HORIZONTAL_PADDINGS > 0,
        isLast = true,
        onChange = { isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "sideGuttersRow: isChecked=$isChecked")
            WGlobalStorage.setAreSideGuttersActive(isChecked)
            ViewConstants.HORIZONTAL_PADDINGS = if (isChecked) 10 else 0
            val fromPadding =
                (if (LocaleController.isRTL) scrollView.paddingLeft else scrollView.paddingRight) -
                    systemBarEndInset
            WalletCore.notifyEvent(WalletEvent.SideGuttersChanged)
            sideGuttersAnimator?.cancel()
            if (!WGlobalStorage.getAreAnimationsActive()) {
                val padding = ViewConstants.HORIZONTAL_PADDINGS.dp
                scrollView.setPaddingLocalized(
                    padding + additionalTabletPadding + systemBarStartInset,
                    0,
                    padding + systemBarEndInset,
                    0
                )
                topReversedCornerView?.setHorizontalPadding(padding.toFloat())
                bottomReversedCornerView?.setHorizontalPadding(padding.toFloat())
                return@SwitchCell
            }
            sideGuttersAnimator =
                ValueAnimator.ofInt(fromPadding, ViewConstants.HORIZONTAL_PADDINGS.dp)
                    .apply {
                        duration = AnimationConstants.QUICK_ANIMATION
                        interpolator = AccelerateDecelerateInterpolator()

                        addUpdateListener { animator ->
                            val padding = animator.animatedValue as Int
                            scrollView.setPaddingLocalized(
                                padding + additionalTabletPadding + systemBarStartInset,
                                0,
                                padding + systemBarEndInset,
                                0
                            )
                            topReversedCornerView?.setHorizontalPadding(padding.toFloat())
                            bottomReversedCornerView?.setHorizontalPadding(padding.toFloat())
                        }

                        addListener(object : AnimatorListenerAdapter() {
                            override fun onAnimationEnd(animation: Animator) {
                                sideGuttersAnimator = null
                            }
                        })

                        start()
                    }
        }
    )

    private val blurRow = SwitchCell(
        context,
        title = LocaleController.getString("Blur"),
        isChecked = WGlobalStorage.isBlurEnabled(),
        onChange = { isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "blurRow: isChecked=$isChecked")
            WGlobalStorage.setBlurEnabled(isChecked)
            liquidGlassRow.isEnabled = isChecked
            pendingThemeChange = true
            WalletContextManager.delegate?.get()?.themeChanged()
        }
    )

    private val liquidGlassRow = SwitchCell(
        context,
        title = LocaleController.getString("Liquid Glass"),
        isChecked = WGlobalStorage.isLiquidGlassEnabled(),
        isFirst = true,
        onChange = { isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "liquidGlassRow: isChecked=$isChecked")
            WGlobalStorage.setLiquidGlassEnabled(isChecked)
            pendingThemeChange = true
            WalletContextManager.delegate?.get()?.themeChanged()
        }
    )

    private val animationsRow = SwitchCell(
        context,
        title = LocaleController.getString("Animations"),
        isChecked = WGlobalStorage.getAreAnimationsActive(),
        onChange = { isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "animationsRow: isChecked=$isChecked")
            WGlobalStorage.setAreAnimationsActive(isChecked)
        }
    )

    private val seasonalThemingRow = SwitchCell(
        context,
        title = LocaleController.getString("Seasonal Theming"),
        isChecked = !WGlobalStorage.getIsSeasonalThemingDisabled(),
        isLast = true,
        onChange = { isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "seasonalThemingRow: isChecked=$isChecked")
            WGlobalStorage.setIsSeasonalThemingDisabled(!isChecked)
            WalletCore.notifyEvent(WalletEvent.SeasonalThemeChanged)
        }
    )

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.addView(appThemeView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(appPaletteView, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        v.addView(paletteHintLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(showOnCardRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(actionButtonsRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(walletCardHintLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(appFontView, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(roundedBalanceFontRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(liquidGlassRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(blurRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(animationsRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(seasonalThemingRow, ConstraintLayout.LayoutParams(0, 50.dp))
        if (EnvironmentStore.isTopTabsSettingAvailable) {
            v.addView(topTabsRow, ConstraintLayout.LayoutParams(0, 50.dp))
        }
        v.addView(gradientNavigationBarRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(roundedCornersRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(roundedToolbarsRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(sideGuttersRow, ConstraintLayout.LayoutParams(0, 50.dp))
        // Set initial enabled state based on roundedCornersRow
        if (!roundedCornersRow.isChecked) {
            roundedToolbarsRow.isEnabled = false
            sideGuttersRow.isEnabled = false
        }
        liquidGlassRow.isEnabled = blurRow.isChecked
        v.setConstraints {
            toTop(appThemeView)
            toCenterX(appThemeView)
            topToBottom(appPaletteView, appThemeView, ViewConstants.GAP.toFloat())
            toCenterX(appPaletteView)
            topToBottom(paletteHintLabel, appPaletteView, 8f)
            toCenterX(paletteHintLabel, 16f)
            // Group 1: Show on Card, Action Buttons
            topToBottom(showOnCardRow, paletteHintLabel, (ViewConstants.GAP + 4).toFloat())
            toCenterX(showOnCardRow)
            topToBottom(actionButtonsRow, showOnCardRow)
            toCenterX(actionButtonsRow)
            topToBottom(walletCardHintLabel, actionButtonsRow, 8f)
            toCenterX(walletCardHintLabel, 16f)
            // Group 2: App Font, Rounded Balance Font
            topToBottom(appFontView, walletCardHintLabel, (ViewConstants.GAP + 4).toFloat())
            toCenterX(appFontView)
            topToBottom(roundedBalanceFontRow, appFontView)
            toCenterX(roundedBalanceFontRow)
            // Group 3: Enable Liquid Glass, Enable Blur, Enable Animations, Seasonal Theming
            topToBottom(liquidGlassRow, roundedBalanceFontRow, ViewConstants.GAP.toFloat())
            toCenterX(liquidGlassRow)
            topToBottom(blurRow, liquidGlassRow)
            toCenterX(blurRow)
            topToBottom(animationsRow, blurRow)
            toCenterX(animationsRow)
            topToBottom(seasonalThemingRow, animationsRow)
            toCenterX(seasonalThemingRow)
            // Group 4: Top Tabs, Gradient Navigation Bar, Rounded Corners, Rounded Toolbars,
            // Side Gutters
            if (EnvironmentStore.isTopTabsSettingAvailable) {
                topToBottom(topTabsRow, seasonalThemingRow, ViewConstants.GAP.toFloat())
                toCenterX(topTabsRow)
                topToBottom(gradientNavigationBarRow, topTabsRow)
            } else {
                topToBottom(
                    gradientNavigationBarRow,
                    seasonalThemingRow,
                    ViewConstants.GAP.toFloat()
                )
            }
            toCenterX(gradientNavigationBarRow)
            topToBottom(roundedCornersRow, gradientNavigationBarRow)
            toCenterX(roundedCornersRow)
            topToBottom(roundedToolbarsRow, roundedCornersRow)
            toCenterX(roundedToolbarsRow)
            topToBottom(sideGuttersRow, roundedToolbarsRow)
            toCenterX(sideGuttersRow)
            toBottom(sideGuttersRow)
        }
        v.setPadding(0, 0, 0, navigationController?.bottomInset ?: 0)
        v
    }

    private fun updateScrollingContentBottomPadding() {
        val bottomPadding = navigationController?.bottomInset ?: 0
        if (scrollingContentView.paddingBottom == bottomPadding) return
        scrollingContentView.setPadding(
            scrollingContentView.paddingLeft,
            scrollingContentView.paddingTop,
            scrollingContentView.paddingRight,
            bottomPadding
        )
    }

    private val scrollView: WScrollView by lazy {
        WScrollView(WeakReference(this)).apply {
            isVerticalScrollBarEnabled = false
            addView(scrollingContentView, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            onScrollStateChange = {
                updateBlurViews(scrollView = this)
            }
            setOnScrollChangeListener { _, _, _, _, _ ->
                updateBlurViews(scrollView = this)
            }
        }
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Appearance"))
        setupNavBar(true)

        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.setConstraints {
            topToBottom(scrollView, navigationBar!!)
            toCenterX(scrollView)
            toBottom(scrollView)
        }

        updateTheme()
        WalletCore.registerObserver(this)
    }

    override fun updateTheme() {
        super.updateTheme()

        appFontView.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp, 0f)
        showOnCardRow.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f
        )

        appThemeView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.TOOLBAR_RADIUS.dp,
            ViewConstants.BLOCK_RADIUS.dp
        )

        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            0
        )
        updateScrollingContentBottomPadding()
    }

    override fun onDestroy() {
        super.onDestroy()
        WalletCore.unregisterObserver(this)
        scrollView.setOnScrollChangeListener(null)
        animationsRow.setOnClickListener(null)
        appPaletteView.onCustomizePressed = null
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {
                appPaletteView.configure(AccountStore.activeAccount)
            }

            WalletEvent.NftCardUpdated -> {
                appPaletteView.configure(AccountStore.activeAccount)
            }

            else -> {}
        }
    }
}
