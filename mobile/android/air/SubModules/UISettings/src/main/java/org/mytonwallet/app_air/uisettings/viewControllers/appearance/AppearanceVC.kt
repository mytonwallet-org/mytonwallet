package org.mytonwallet.app_air.uisettings.viewControllers.appearance

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.os.Build
import android.view.View.generateViewId
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.ScrollView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SwitchCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.FontFamily
import org.mytonwallet.app_air.uicomponents.helpers.FontManager
import org.mytonwallet.app_air.uicomponents.widgets.WEditableItemView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.R
import org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.palette.AppearancePaletteAndCardView
import org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.theme.AppearanceAppThemeView
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsItemCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.uisettings.viewControllers.walletCustomization.WalletCustomizationVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class AppearanceVC(context: Context) : WViewController(context), WalletCore.EventObserver {
    override val TAG = "Appearance"

    override val shouldDisplayBottomBar = true

    private val switchToLegacyCell = SettingsItemCell(context).apply {
        configure(
            SettingsItem(
                identifier = SettingsItem.Identifier.SWITCH_TO_LEGACY,
                icon = R.drawable.ic_legacy,
                title = LocaleController.getString("Switch to Legacy Version"),
                hasTintColor = false
            ),
            subtitle = null,
            isFirst = false,
            isLast = true,
            onTap = {
                WalletCore.switchingToLegacy()
                WalletContextManager.delegate?.switchToLegacy()
            }
        )
    }

    private val appThemeView: AppearanceAppThemeView by lazy {
        val v = AppearanceAppThemeView(context)
        v
    }

    private val appPaletteView: AppearancePaletteAndCardView by lazy {
        AppearancePaletteAndCardView(context).apply {
            onCustomizePressed = {
                navigationController?.push(
                    WalletCustomizationVC(
                        context,
                        AccountStore.activeAccountId!!
                    )
                )
            }
            configure(AccountStore.activeAccount)
        }
    }

    private val appFontDropdownView = WEditableItemView(context).apply {
        id = generateViewId()
        drawable = ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_arrows_18
        )
        setText(FontManager.activeFont.displayName)
    }
    private val appFontView: KeyValueRowView by lazy {
        KeyValueRowView(
            context,
            LocaleController.getString("App Font"),
            "",
            KeyValueRowView.Mode.PRIMARY,
            isLast = true,
        ).apply {
            setValueView(appFontDropdownView)
            setOnClickListener {
                WMenuPopup.present(
                    appFontDropdownView,
                    listOf(
                        FontFamily.ROBOTO,
                        FontFamily.MISANS,
                    ).map {
                        WMenuPopup.Item(
                            null,
                            it.displayName,
                            false
                        ) {
                            if (FontManager.activeFont != it) {
                                Logger.d(Logger.LogTag.SETTINGS, "appFontView: fontChanged=${it.displayName}")
                                FontManager.setActiveFont(context, it)
                                appFontDropdownView.setText(it.displayName)
                                // Font changes require app restart to refresh all cached typefaces
                                WalletContextManager.delegate?.restartApp()
                            }
                        }
                    },
                    popupWidth = WRAP_CONTENT,
                    positioning = WMenuPopup.Positioning.BELOW,
                    windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                        appFontDropdownView,
                        roundRadius = 16f.dp
                    )
                )
            }
        }
    }

    /*private val appIconView: AppearanceAppIconView by lazy {
        val v = AppearanceAppIconView(window!!.applicationContext)
        v
    }*/

    private val roundedCornersRow = SwitchCell(
        context,
        title = LocaleController.getString("Rounded Corners"),
        isChecked = WGlobalStorage.getAreRoundedCornersActive(),
        isFirst = true,
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
            WalletContextManager.delegate?.themeChanged()
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
            ViewConstants.TOOLBAR_RADIUS = if (isChecked) 24f else 0f
            pendingThemeChange = true
            WalletContextManager.delegate?.themeChanged()
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
                        switchToLegacyCell.setBackgroundColor(
                            WColor.Background.color,
                            radius,
                            ViewConstants.BLOCK_RADIUS.dp,
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
            sideGuttersAnimator?.cancel()
            sideGuttersAnimator =
                ValueAnimator.ofInt(scrollView.paddingLeft, ViewConstants.HORIZONTAL_PADDINGS.dp)
                    .apply {
                        duration = AnimationConstants.QUICK_ANIMATION
                        interpolator = AccelerateDecelerateInterpolator()

                        addUpdateListener { animator ->
                            val padding = animator.animatedValue as Int
                            scrollView.setPadding(padding, 0, padding, 0)
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
        title = LocaleController.getString("Enable Blur"),
        isChecked = WGlobalStorage.isBlurEnabled(),
        isFirst = true,
        onChange = { isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "blurRow: isChecked=$isChecked")
            WGlobalStorage.setBlurEnabled(isChecked)
            pendingThemeChange = true
            WalletContextManager.delegate?.themeChanged()
        }
    )

    private val animationsRow = SwitchCell(
        context,
        title = LocaleController.getString("Enable Animations"),
        isChecked = WGlobalStorage.getAreAnimationsActive(),
        onChange = { isChecked ->
            Logger.d(Logger.LogTag.SETTINGS, "animationsRow: isChecked=$isChecked")
            WGlobalStorage.setAreAnimationsActive(isChecked)
        }
    )

    private val seasonalThemingRow = SwitchCell(
        context,
        title = LocaleController.getString("Enable Seasonal Theming"),
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
        v.addView(switchToLegacyCell, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(appThemeView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(appPaletteView, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        v.addView(roundedCornersRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(roundedToolbarsRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(sideGuttersRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(blurRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(animationsRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(seasonalThemingRow, ConstraintLayout.LayoutParams(0, 50.dp))
        v.addView(appFontView, ConstraintLayout.LayoutParams(0, 50.dp))
        // Set initial enabled state based on roundedCornersRow
        if (!roundedCornersRow.isChecked) {
            roundedToolbarsRow.isEnabled = false
            sideGuttersRow.isEnabled = false
        }
        v.setConstraints {
            toTop(switchToLegacyCell)
            toCenterX(switchToLegacyCell)
            topToBottom(appThemeView, switchToLegacyCell, ViewConstants.GAP.toFloat())
            toCenterX(appThemeView)
            topToBottom(appPaletteView, appThemeView, ViewConstants.GAP.toFloat())
            toCenterX(appPaletteView)
            // Group 1: Rounded Corners, Rounded Toolbars, Side Gutters
            topToBottom(roundedCornersRow, appPaletteView, ViewConstants.GAP.toFloat())
            toCenterX(roundedCornersRow)
            topToBottom(roundedToolbarsRow, roundedCornersRow)
            toCenterX(roundedToolbarsRow)
            topToBottom(sideGuttersRow, roundedToolbarsRow)
            toCenterX(sideGuttersRow)
            // Group 2: Enable Blur, Enable Animations
            topToBottom(blurRow, sideGuttersRow, ViewConstants.GAP.toFloat())
            toCenterX(blurRow)
            topToBottom(animationsRow, blurRow)
            toCenterX(animationsRow)
            topToBottom(seasonalThemingRow, animationsRow)
            toCenterX(seasonalThemingRow)
            // Group 3: App Font
            topToBottom(appFontView, seasonalThemingRow, ViewConstants.GAP.toFloat())
            toCenterX(appFontView)
            toBottomPx(appFontView, (navigationController?.getSystemBars()?.bottom ?: 0))
        }
        v
    }

    private val scrollView: ScrollView by lazy {
        ScrollView(context).apply {
            id = generateViewId()
            isVerticalScrollBarEnabled = false
            addView(scrollingContentView, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                setOnScrollChangeListener { _, _, scrollY, _, _ ->
                    updateBlurViews(scrollView = this, computedOffset = scrollY)
                }
            }
            overScrollMode = ScrollView.OVER_SCROLL_ALWAYS
            setPadding(
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                0,
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                0
            )
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

    override fun viewDidAppear() {
        super.viewDidAppear()
        updateBlurViews(scrollView, 0)
    }

    override fun updateTheme() {
        super.updateTheme()

        appFontView.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)

        view.setBackgroundColor(WColor.SecondaryBackground.color)
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
