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
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SwitchCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.FontFamily
import org.mytonwallet.app_air.uicomponents.helpers.FontManager
import org.mytonwallet.app_air.uicomponents.widgets.WEditableItemView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.R
import org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.palette.AppearancePaletteItemView
import org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.palette.AppearancePaletteView
import org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.theme.AppearanceAppThemeView
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsItemCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class AppearanceVC(context: Context) : WViewController(context), WalletCore.EventObserver {

    override val shouldDisplayBottomBar = true

    private val switchToLegacyCell = SettingsItemCell(context).apply {
        configure(
            SettingsItem(
                identifier = SettingsItem.Identifier.SWITCH_TO_LEGACY,
                icon = R.drawable.ic_legacy,
                title = LocaleController.getString("Switch to Legacy Version"),
                hasTintColor = false
            ),
            value = null,
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

    private val appPaletteView: AppearancePaletteView by lazy {
        AppearancePaletteView(context).apply {
            updatePaletteView()
            onPaletteSelected = { nftAccentId, state, nft ->
                when (state) {
                    AppearancePaletteItemView.State.LOCKED -> {
                        showAlert(
                            LocaleController.getString("Unlock New Palettes"),
                            LocaleController.getString("Get a unique MyTonWallet Card to unlock new palettes.")
                        )
                    }

                    AppearancePaletteItemView.State.AVAILABLE -> {
                        nftAccentId?.let {
                            WGlobalStorage.setNftAccentColor(
                                AccountStore.activeAccountId!!,
                                nftAccentId,
                                nft?.toDictionary()
                            )
                        } ?: run {
                            WGlobalStorage.setNftAccentColor(
                                AccountStore.activeAccountId!!,
                                null,
                                null
                            )
                        }
                        WalletContextManager.delegate?.themeChanged()
                        appPaletteView.reloadViews()
                    }

                    else -> {}
                }
            }
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
                        /*FontFamily.OPENSANS,
                        FontFamily.NOTOSANS,
                        FontFamily.NUNITOSANS,
                        FontFamily.VAZIR*/
                    ).map {
                        WMenuPopup.Item(
                            null,
                            it.displayName,
                            false
                        ) {
                            if (FontManager.activeFont != it) {
                                FontManager.setActiveFont(context, it)
                                appFontDropdownView.setText(it.displayName)
                                // Font changes require app restart to refresh all cached typefaces
                                WalletContextManager.delegate?.restartApp()
                            }
                        }
                    },
                    popupWidth = WRAP_CONTENT,
                    aboveView = false
                )
            }
        }
    }

    /*private val appIconView: AppearanceAppIconView by lazy {
        val v = AppearanceAppIconView(window!!.applicationContext)
        v
    }*/

    private var radiusAnimator: ValueAnimator? = null
    private val roundedToolbarsRow = SwitchCell(
        context,
        title = LocaleController.getString("Rounded Toolbars"),
        isChecked = ThemeManager.uiMode == ThemeManager.UIMode.BIG_RADIUS,
        isFirst = true,
        onChange = { isChecked ->
            val uiMode = if (isChecked) {
                ThemeManager.UIMode.BIG_RADIUS
            } else {
                ThemeManager.UIMode.COMPOUND
            }
            val prevBarRounds = topReversedCornerView?.cornerRadius ?: 0f
            WGlobalStorage.setActiveUiMode(uiMode)
            ThemeManager.uiMode = uiMode
            WalletContextManager.delegate?.themeChanged()
            topReversedCornerView?.animateRadius(
                prevBarRounds,
                ViewConstants.BAR_ROUNDS.dp
            )
            radiusAnimator?.cancel()
            radiusAnimator = ValueAnimator.ofFloat(prevBarRounds, ViewConstants.BAR_ROUNDS.dp)
                .apply {
                    duration = AnimationConstants.QUICK_ANIMATION
                    interpolator = AccelerateDecelerateInterpolator()

                    addUpdateListener { animator ->
                        val radius = animator.animatedValue as Float
                        switchToLegacyCell.setBackgroundColor(
                            WColor.Background.color,
                            radius,
                            ViewConstants.BIG_RADIUS.dp,
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
        onChange = { isChecked ->
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

    private val animationsRow = SwitchCell(
        context,
        title = LocaleController.getString("Enable Animations"),
        isChecked = WGlobalStorage.getAreAnimationsActive(),
        isLast = true,
        onChange = { isChecked ->
            WGlobalStorage.setAreAnimationsActive(isChecked)
        }
    )

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.addView(switchToLegacyCell, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(appThemeView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(appPaletteView, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        v.addView(appFontView, ConstraintLayout.LayoutParams(0, 56.dp))
        v.addView(roundedToolbarsRow, ConstraintLayout.LayoutParams(0, 56.dp))
        v.addView(sideGuttersRow, ConstraintLayout.LayoutParams(0, 56.dp))
        v.addView(animationsRow, ConstraintLayout.LayoutParams(0, 56.dp))
        v.setConstraints {
            toTop(switchToLegacyCell)
            toCenterX(switchToLegacyCell)
            topToBottom(appThemeView, switchToLegacyCell, ViewConstants.GAP.toFloat())
            toCenterX(appThemeView)
            topToBottom(appPaletteView, appThemeView, ViewConstants.GAP.toFloat())
            toCenterX(appPaletteView)
            topToBottom(appFontView, appPaletteView, ViewConstants.GAP.toFloat())
            toCenterX(appFontView)
            topToBottom(roundedToolbarsRow, appFontView, ViewConstants.GAP.toFloat())
            toCenterX(roundedToolbarsRow)
            topToBottom(sideGuttersRow, roundedToolbarsRow)
            toCenterX(sideGuttersRow)
            topToBottom(animationsRow, sideGuttersRow)
            toCenterX(animationsRow)
            toBottomPx(animationsRow, (navigationController?.getSystemBars()?.bottom ?: 0))
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

        WalletCore.registerObserver(this)

        updateTheme()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        updateBlurViews(scrollView, 0)
    }

    override fun updateTheme() {
        super.updateTheme()

        appFontView.setBackgroundColor(WColor.Background.color, ViewConstants.BIG_RADIUS.dp)

        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            scrollView.setOnScrollChangeListener(null)
        }
        animationsRow.setOnClickListener(null)
        appPaletteView.onPaletteSelected = null
        WalletCore.unregisterObserver(this)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.NftsUpdated, WalletEvent.ReceivedNewNFT -> {
                appPaletteView.updatePaletteView()
            }

            else -> {}
        }
    }


}
