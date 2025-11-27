package org.mytonwallet.uihome.walletsTabs

import android.content.Context
import android.graphics.Color
import android.text.SpannableString
import android.text.Spanned
import android.view.Gravity
import android.view.View
import android.view.View.generateViewId
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.core.widget.NestedScrollView
import org.json.JSONArray
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.AccountDialogHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WEvaporateLabel
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WScaleLabel
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItem
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.utils.MarginImageSpan
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.uihome.wallets.WalletsVC
import java.lang.ref.WeakReference
import kotlin.math.min
import kotlin.math.roundToInt

class WalletsTabsVC(context: Context, val defaultMode: MWalletSettingsViewMode) :
    WViewController(context), WalletCore.EventObserver {

    override val isSwipeBackAllowed = false

    companion object {
        const val DEFAULT_HEIGHT = 560
    }

    override val shouldDisplayTopBar = false
    override val topBarConfiguration: ReversedCornerView.Config
        get() = super.topBarConfiguration.copy(blurRootView = scrollView)
    override val shouldDisplayBottomBar = true
    override val ignoreSideGuttering = true

    enum class WalletCategory(val value: String) {
        MY("My"),
        ALL("All"),
        LEDGER("Ledger"),
        VIEW("\$view_mode");

        val localized: String
            get() {
                return LocaleController.getString(value)
            }
    }

    private val tabs =
        listOf(WalletCategory.ALL, WalletCategory.MY, WalletCategory.LEDGER, WalletCategory.VIEW)
    private var isReordering = false

    var allAccounts = WalletCore.getAllAccounts()

    val walletsViewControllers = mutableListOf<WalletsVC>()

    val titleLabel: WScaleLabel by lazy {
        WScaleLabel(context).apply {
            setStyle(20F, WFont.SemiBold)
            view.post {
                animateText(titleText)
                post {
                    setProgress(1f)
                }
            }
        }
    }

    val subtitleLabel: WEvaporateLabel by lazy {
        WEvaporateLabel(context).apply {
            setStyle(12f)
            view.post {
                animateText(subtitleText)
                post {
                    setProgress(1f)
                }
            }
        }
    }

    val totalBalanceContainerView = WSensitiveDataContainer(
        subtitleLabel,
        WSensitiveDataContainer.MaskConfig(
            6,
            2,
            Gravity.CENTER
        )
    )

    private val titleLinearLayout: LinearLayout by lazy {
        LinearLayout(context).apply {
            id = generateViewId()
            clipChildren = false
            clipToPadding = false
            orientation = LinearLayout.VERTICAL
            addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            addView(totalBalanceContainerView, LayoutParams(WRAP_CONTENT, 16.dp))
            gravity = Gravity.CENTER
            z = 1f
        }
    }

    val segmentItems by lazy {
        tabs.mapIndexed { index, tab ->
            val vc = WalletsVC(
                context,
                tab,
                window!!.windowView.width,
                navigationController?.getSystemBars()?.top ?: 0,
                navigationController?.getSystemBars()?.bottom ?: 0
            ).apply {
                onAccountsReordered = { accounts ->
                    WGlobalStorage.setOrderedAccountIds(JSONArray(accounts.map { it.accountId }))
                    WalletCore.notifyEvent(WalletEvent.AccountsReordered)
                    allAccounts = accounts
                }
                onCheckChanged = {
                    updateRemoveWalletButton()
                }
                onToggleReorderTapped = {
                    toggleReorder(true)
                }
                onSwitchAccountInProgress = {
                    WalletCore.unregisterObserver(this@WalletsTabsVC)
                }
            }
            walletsViewControllers.add(vc)
            WSegmentedControllerItem(
                walletsViewControllers[index],
                identifier = tab.value
            )
        }.toMutableList()
    }

    private val segmentedController: WSegmentedController by lazy {
        WSegmentedController(
            navigationController!!,
            segmentItems,
            0,
            applySideGutters = false,
            navTopPadding = 42.dp,
            onOffsetChange = { _, currentOffset ->
                val nearestIndex = currentOffset.roundToInt()
                if (nearestIndex == segmentedController.currentIndex)
                    onTabChanged(nearestIndex)
            }
        ).apply {
            z = 2f
        }
    }

    private val scrollView: NestedScrollView by lazy {
        NestedScrollView(context).apply {
            id = generateViewId()
            addView(
                segmentedController,
                LayoutParams(
                    MATCH_PARENT,
                    MATCH_PARENT
                )
            )
            isFillViewport = true
        }
    }

    private val addNewWalletButton by lazy {
        WButton(context).apply {
            id = generateViewId()
            clickableError = true
            setOnClickListener {
                if (isReordering) {
                    val checkedAccounts =
                        walletsViewControllers[tabs.indexOf(WalletCategory.ALL)].checkedAccounts
                    AccountDialogHelpers.presentSignOut(window!!, checkedAccounts.toList())
                } else {
                    val walletCategory = tabs[selectedTabIndex]
                    val vc = when (walletCategory) {
                        WalletCategory.MY, WalletCategory.ALL -> {
                            WalletContextManager.delegate?.getAddAccountVC()
                        }

                        WalletCategory.LEDGER -> {
                            WalletContextManager.delegate?.getImportLedgerVC()
                        }

                        WalletCategory.VIEW -> {
                            WalletContextManager.delegate?.getAddViewAccountVC()
                        }
                    } as WViewController
                    val nav = WNavigationController(
                        window!!,
                        if (walletCategory == WalletCategory.LEDGER)
                            WNavigationController.PresentationConfig()
                        else
                            WNavigationController.PresentationConfig(
                                overFullScreen = false,
                                isBottomSheet = true,
                                aboveKeyboard = true
                            )
                    ).apply {
                        setRoot(vc)
                    }
                    window?.dismissLastNav {
                        window?.present(nav)
                    }
                }
            }
        }
    }

    private val listButton: WImageButton by lazy {
        WImageButton(context).apply {
            val closeDrawable =
                ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.uihome.R.drawable.ic_list
                )
            setImageDrawable(closeDrawable)
            updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
            setPadding(8.dp)
            setOnClickListener {
                if (isReordering) {
                    toggleReorder(false)
                    switchViewMode(MWalletSettingsViewMode.LIST)
                    WGlobalStorage.setAccountSelectorViewMode(MWalletSettingsViewMode.LIST)
                } else {
                    showMenuPressed(this)
                }
            }
        }
    }

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true, WNavigationBar.DEFAULT_HEIGHT_THICK)

        navigationBar?.addCloseButton(trailingMarginDp = 8f)
        navigationBar?.addLeadingView(listButton)

        view.addView(
            scrollView,
            LayoutParams(
                MATCH_PARENT,
                window!!.windowView.height
            )
        )
        view.addView(addNewWalletButton, ViewGroup.LayoutParams(MATCH_CONSTRAINT, 50.dp))
        view.addView(titleLinearLayout, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.setConstraints {
            toBottom(scrollView)
            toCenterX(titleLinearLayout)
            toTop(titleLinearLayout, 16.5f)
            toCenterX(addNewWalletButton, 20f)
            toBottomPx(
                addNewWalletButton, 16.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        }
        switchViewMode(defaultMode)

        WalletCore.registerObserver(this)
        updateTheme()
        updateAccounts()
        onTabChanged(0)

        view.post {
            // Workaround! Otherwise, the icon doesn't appear correctly!
            updateAddNewWalletButton(animated = false)
        }
    }

    override fun didSetupViews() {
        super.didSetupViews()
        bottomReversedCornerView?.updateLayoutParams {
            height = ViewConstants.BAR_ROUNDS.dp.roundToInt() +
                ViewConstants.GAP.dp +
                50.dp +
                16.dp +
                (navigationController?.getSystemBars()?.bottom ?: 0)
        }
        walletsViewControllers.forEach {
            it.parentTopReversedCornerView = WeakReference(segmentedController.reversedCornerView)
            it.parentBottomReversedCornerView = WeakReference(bottomReversedCornerView)
        }
        addNewWalletButton.bringToFront()
    }

    override fun updateTheme() {
        super.updateTheme()
        updateBackground()
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        walletsViewControllers.firstOrNull()?.insetsUpdated()
    }

    override fun onDestroy() {
        super.onDestroy()
        WalletCore.unregisterObserver(this)
    }

    fun updateAccounts(excludeTabs: List<WalletCategory> = emptyList()) {
        walletsViewControllers.filter { !excludeTabs.contains(it.walletCategory) }
            .forEach { walletViewController ->
                walletViewController.setAccounts(allAccounts.filter { account ->
                    return@filter when (walletViewController.walletCategory) {
                        WalletCategory.MY -> {
                            !account.isViewOnly
                        }

                        WalletCategory.ALL -> {
                            true
                        }

                        WalletCategory.LEDGER -> {
                            account.isHardware
                        }

                        WalletCategory.VIEW -> {
                            account.isViewOnly
                        }

                        else -> {
                            false
                        }
                    }
                })
            }
    }

    private fun updateBackground() {
        val expandProgress = 10f / 3f * (((modalExpandProgress ?: 0f) - 0.7f).coerceIn(0f, 1f))
        val topRadius = (1 - expandProgress) * ViewConstants.BIG_RADIUS.dp
        view.setBackgroundColor(
            WColor.SecondaryBackground.color,
            topRadius,
            0f,
            true
        )
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.BalanceChanged -> {
                walletsViewControllers.forEach {
                    it.notifyBalanceChange(async = true)
                }
            }

            is WalletEvent.AccountChangedInApp -> {
                if (walletEvent.accountsModified)
                    allAccounts = WalletCore.getAllAccounts()
                updateAccounts()
                walletsViewControllers.forEach {
                    it.reloadData()
                }
                if (walletEvent.accountsModified) {
                    updateTitleBar()
                    if (isReordering) {
                        updateRemoveWalletButton()
                    } else {
                        updateAddNewWalletButton()
                    }
                }
            }

            WalletEvent.AccountNameChanged, WalletEvent.NftCardUpdated -> {
                updateAccounts()
                walletsViewControllers.forEach {
                    it.reloadData()
                }
            }

            else -> {}
        }
    }

    private var selectedTabIndex = -1
    private fun onTabChanged(newIndex: Int) {
        if (newIndex == selectedTabIndex) {
            return
        }
        selectedTabIndex = newIndex
        updateAddNewWalletButton()
        updateTitleBar()
    }

    private val titleText: String?
        get() {
            val tabAccounts =
                walletsViewControllers.getOrNull(selectedTabIndex)?.accounts ?: allAccounts
            return LocaleController.getPlural(tabAccounts.size, "\$wallets_amount")
        }
    private val subtitleText: String?
        get() {
            val tabAccounts =
                walletsViewControllers.getOrNull(selectedTabIndex)?.accounts ?: allAccounts
            val baseCurrency = WalletCore.baseCurrency
            val amount = tabAccounts.sumOf {
                BalanceStore.totalBalanceInBaseCurrency(it.accountId) ?: 0.0
            }.toBigInteger(baseCurrency.decimalsCount)
            val amountString = amount?.toString(
                decimals = baseCurrency.decimalsCount,
                currency = baseCurrency.sign,
                currencyDecimals = amount.smartDecimalsCount(baseCurrency.decimalsCount),
                false
            )
            return " " + LocaleController.getStringWithKeyValues(
                "\$total_balance",
                listOf(Pair("%balance%", amountString ?: ""))
            ) + " "
        }

    private fun updateTitleBar() {
        titleLabel.animateText(titleText)
        subtitleLabel.animateText(subtitleText)
    }

    override fun getModalHalfExpandedHeight(): Int? {
        return DEFAULT_HEIGHT.dp
    }

    private var prevExpandProgress = 0f
    override fun onModalSlide(expandOffset: Int, expandProgress: Float) {
        modalExpandOffset = expandOffset
        modalExpandProgress = expandProgress
        topReversedCornerView?.translationZ = navigationBar?.translationZ ?: 0f
        if (expandProgress < 1) {
            topReversedCornerView?.setBackgroundColor(
                Color.TRANSPARENT,
                min(1f, ((1 - expandProgress) * 5)) * ViewConstants.BIG_RADIUS.dp,
                0f,
                true
            )
            if (prevExpandProgress == 1f)
                walletsViewControllers.forEach {
                    if (it != segmentedController.currentItem)
                        it.scrollToTop()
                    it.isModalExpanded = false
                }
        } else {
            walletsViewControllers.forEach {
                it.isModalExpanded = true
            }
            topReversedCornerView?.background = null
        }
        prevExpandProgress = expandProgress
        walletsViewControllers.forEach {
            it.onModalSlide(expandOffset, expandProgress)
        }
        val normalizedExpandProgress = 10 / 3 * ((expandProgress - 0.7f).coerceIn(0f, 1f))
        titleLinearLayout.translationY =
            normalizedExpandProgress * (navigationController?.getSystemBars()?.top ?: 0)
        navigationBar?.translationY =
            -(navigationController?.getSystemBars()?.top?.toFloat() ?: 0f) +
                normalizedExpandProgress * (navigationController?.getSystemBars()?.top ?: 0)
        bottomReversedCornerView?.translationY = DEFAULT_HEIGHT.toFloat().dp -
            (window?.windowView?.height ?: 0) +
            (navigationController?.getSystemBars()?.bottom ?: 0) +
            expandOffset
        addNewWalletButton.translationY = bottomReversedCornerView?.translationY ?: 0f
        val newTopPadding = (normalizedExpandProgress * (navigationController?.getSystemBars()?.top
            ?: 0)).roundToInt()
        if (scrollView.paddingTop != newTopPadding) {
            scrollView.setPadding(0, newTopPadding, 0, 0)
        }
        updateBackground()
    }

    private fun showMenuPressed(view: View) {
        val isShowingList = walletsViewControllers.first().viewMode == MWalletSettingsViewMode.LIST
        WMenuPopup.present(
            view = view,
            items = listOf(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = WMenuPopup.Item.Config.Icon(
                            if (isShowingList)
                                org.mytonwallet.uihome.R.drawable.ic_card
                            else
                                org.mytonwallet.uihome.R.drawable.ic_bullets
                        ),
                        title = LocaleController.getString(
                            if (isShowingList)
                                "View as Cards"
                            else
                                "View as List"
                        ),
                    ),
                    onTap = {
                        val viewMode =
                            if (walletsViewControllers.first().viewMode == MWalletSettingsViewMode.LIST)
                                MWalletSettingsViewMode.GRID
                            else
                                MWalletSettingsViewMode.LIST
                        switchViewMode(viewMode)
                        WGlobalStorage.setAccountSelectorViewMode(viewMode)
                    }
                ),
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = WMenuPopup.Item.Config.Icon(org.mytonwallet.uihome.R.drawable.ic_reorder),
                        title = LocaleController.getString("Reorder"),
                    ),
                    onTap = {
                        toggleReorder(true)
                    }
                )
            ),
            aboveView = false
        )
    }

    private fun switchViewMode(viewMode: MWalletSettingsViewMode) {
        segmentedController.reversedCornerView.isGone =
            viewMode == MWalletSettingsViewMode.LIST
        bottomReversedCornerView?.isGone =
            viewMode == MWalletSettingsViewMode.LIST
        walletsViewControllers.forEach {
            it.viewMode = viewMode
        }
    }

    private fun toggleReorder(reorder: Boolean) {
        isReordering = reorder
        val index = tabs.indexOf(WalletCategory.ALL)
        val changingTab = selectedTabIndex != index
        if (reorder) {
            walletsViewControllers[index].viewMode = MWalletSettingsViewMode.LIST
            if (changingTab) {
                segmentedController.onIndexChanged(index, true)
            }
            segmentedController.lockTab()
        } else {
            segmentedController.unlockTab()
            updateAccounts(listOf(WalletCategory.ALL))
        }
        view.post {
            walletsViewControllers[index].toggleReorder(reorder, !changingTab)
            listButton.setImageDrawable(
                ContextCompat.getDrawable(
                    context, if (isReordering)
                        org.mytonwallet.uihome.R.drawable.ic_check
                    else
                        org.mytonwallet.uihome.R.drawable.ic_list
                )
            )
            listButton.updateColors(
                if (isReordering) WColor.Tint else WColor.SecondaryText,
                WColor.BackgroundRipple
            )
            updateAddNewWalletButton()
        }
    }

    private fun updateAddNewWalletButton(animated: Boolean = true) {
        val text = LocaleController.getString(
            if (isReordering) "Remove Wallet" else {
                when (tabs[selectedTabIndex]) {
                    WalletCategory.MY, WalletCategory.ALL -> {
                        "Add New Wallet"
                    }

                    WalletCategory.LEDGER -> {
                        "Add Ledger Wallet"
                    }

                    WalletCategory.VIEW -> {
                        "Add View Wallet"
                    }
                }
            }
        )

        if (isReordering) {
            addNewWalletButton.setText(text, animated)
        } else {
            val drawable = ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.uisettings.R.drawable.ic_plus
            )?.apply {
                setTint(WColor.TextOnTint.color)
                val size = 20.dp
                setBounds(0, 0, size, size)
            }
            val spannable = SpannableString(" $text")
            drawable?.let {
                val imageSpan = MarginImageSpan(it, -0.5f.dp.roundToInt(), 4.5f.dp.roundToInt())
                spannable.setSpan(imageSpan, 0, 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            addNewWalletButton.setText(spannable, animated)
        }

        addNewWalletButton.isError = isReordering
        addNewWalletButton.isEnabled = !isReordering
    }

    private fun updateRemoveWalletButton() {
        val checkedAccounts =
            walletsViewControllers[tabs.indexOf(WalletCategory.ALL)].checkedAccounts
        val checkedAccountsCount = checkedAccounts.size
        addNewWalletButton.text = LocaleController.getPlural(
            checkedAccountsCount,
            "\$remove_wallets"
        )
        addNewWalletButton.isEnabled = checkedAccountsCount > 0
    }
}
