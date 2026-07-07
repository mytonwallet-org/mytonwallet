package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.payOptions

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.isVisible
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.commonViews.AccountItemView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.IPopup
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.payOptions.cells.WalletConnectPayEmptyCell
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.payOptions.cells.WalletConnectPayHeaderCell
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.payOptions.cells.WalletConnectPayOptionCell
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.min

@SuppressLint("ViewConstructor")
class WalletConnectPayOptionsVC(
    context: Context,
    private var update: ApiUpdate.ApiUpdateWalletConnectPayOptionSelection? = null
) : WViewController(context), WRecyclerViewAdapter.WRecyclerViewDataSource,
    WalletCore.EventObserver {
    override val TAG = "WalletConnectPayOptions"

    override val topBarConfiguration
        get() = super.topBarConfiguration.copy(blurRootView = recyclerView)

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val OPTION_CELL = WCell.Type(2)
        val EMPTY_CELL = WCell.Type(3)
        val TITLE_CELL = WCell.Type(4)
    }

    private var isConfirmed = false

    private val accountIconView = AccountIconView(context, AccountIconView.Usage.ViewItem()).apply {
        isClickable = false
        isFocusable = false
    }

    private val accountLoadingDrawable = RoundProgressDrawable(18f.dp, 0.75f.dp)
    private val accountLoadingView = object : View(context) {
        val size = 18.dp
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val left = (width - size) / 2
            val top = (height - size) / 2
            accountLoadingDrawable.setBounds(left, top, left + size, top + size)
            accountLoadingDrawable.draw(canvas)
        }

        override fun verifyDrawable(who: Drawable): Boolean {
            if (who == accountLoadingDrawable) return isVisible
            return super.verifyDrawable(who)
        }
    }.apply {
        isVisible = false
        accountLoadingDrawable.callback = this
    }

    private val expandIcon = AppCompatImageView(context)

    private val accountSelectorView = object : WFrameLayout(context), WThemedView {
        init {
            addView(
                accountIconView,
                LayoutParams(40.dp, 40.dp, Gravity.START or Gravity.CENTER_VERTICAL).apply {
                    leftMargin = 4.dp
                }
            )
            addView(
                accountLoadingView,
                LayoutParams(40.dp, 40.dp, Gravity.START or Gravity.CENTER_VERTICAL).apply {
                    leftMargin = 4.dp
                }
            )
            addView(
                expandIcon,
                LayoutParams(18.dp, 18.dp, Gravity.END or Gravity.CENTER_VERTICAL).apply {
                    rightMargin = 14.dp
                }
            )
            setOnClickListener { presentAccountSwitcher() }
            updateTheme()
        }

        override fun updateTheme() {
            setBackgroundColor(WColor.ThumbBackground.color, 24f.dp)
            accountLoadingDrawable.color = WColor.White.color
            expandIcon.setImageDrawable(
                context.getDrawableCompat(
                    org.mytonwallet.app_air.uicomponents.R.drawable.ic_expand
                )?.apply {
                    setTint(WColor.SecondaryText.color)
                }
            )
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            super.onMeasure(
                75.dp.exactly,
                48.dp.exactly
            )
        }
    }

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(HEADER_CELL, OPTION_CELL, EMPTY_CELL, TITLE_CELL)
        )

    private val recyclerView = WRecyclerView(this).apply {
        adapter = rvAdapter
        val layoutManager = LinearLayoutManagerAccurateOffset(context)
        layoutManager.isSmoothScrollbarEnabled = true
        setLayoutManager(layoutManager)
        setItemAnimator(null)
        clipToPadding = false
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                if (dx == 0 && dy == 0) return
                resumeBlurViews()
                updateScroll(
                    recyclerView.computeVerticalScrollOffset()
                )
                updateBlurViews(recyclerView)
            }

            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                super.onScrollStateChanged(recyclerView, newState)
                if (newState == RecyclerView.SCROLL_STATE_IDLE &&
                    recyclerView.computeVerticalScrollOffset() == 0
                ) {
                    pauseBlurViews()
                }
            }
        })
        setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
    }

    override fun setupViews() {
        super.setupViews()

        navigationBar = WNavigationBar(this).apply {
            setTitleGravity(Gravity.START)
        }

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(navigationBar, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.setConstraints {
            allEdges(recyclerView)
        }

        navigationBar?.addCloseButton {
            navigationController?.window?.dismissLastNav()
        }
        navigationBar?.addTrailingView(accountSelectorView)
        topReversedCornerView?.alpha = 0f

        WalletCore.registerObserver(this)

        updateRecyclerViewPadding()
        bindUpdate()
        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        recyclerView.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.reloadData()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        updateRecyclerViewPadding()
    }

    private fun updateRecyclerViewPadding() {
        recyclerView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarStartInset,
            navigationBar?.calculatedMinHeight ?: 0,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            navigationController?.bottomInset ?: 0
        )
    }

    fun setUpdate(update: ApiUpdate.ApiUpdateWalletConnectPayOptionSelection) {
        this.update = update
        if (update.accountId != AccountStore.activeAccountId) return
        loadingAccountId = null
        bindUpdate()
        rvAdapter.reloadData()
        setAccountLoading(false)
        view.unlockView()
    }

    private fun bindUpdate() {
        val update = update ?: return
        navigationBar?.setTitle(update.merchant.name, animated = false)
        AccountStore.accountById(update.accountId)?.let { accountIconView.config(it) }
    }

    private fun setAccountLoading(isLoading: Boolean) {
        accountLoadingView.isVisible = isLoading
        accountIconView.showText = !isLoading
    }

    private var accountSwitcherPopup: IPopup? = null

    private fun presentAccountSwitcher() {
        val update = update ?: return
        val accounts = WalletCore.getAllAccounts().filter { it.supportsWalletConnectPay }
        if (accounts.isEmpty()) return

        lateinit var popup: IPopup
        val items = accounts.mapIndexed { i, account ->
            WMenuPopup.Item(
                config = WMenuPopup.Item.Config.CustomView(
                    AccountItemView(
                        context = context,
                        accountData = AccountItemView.AccountData(
                            accountId = account.accountId,
                            title = account.name,
                            network = account.network,
                            byChain = account.byChain,
                            accountType = account.accountType,
                        ),
                        showArrow = false,
                        isTrusted = true,
                        hasSeparator = false,
                        onSelect = {
                            popup.dismiss()
                            if (account.accountId != update.accountId) {
                                switchAccount(account.accountId)
                            }
                        }
                    )
                ),
                hasSeparator = i < accounts.size - 1
            )
        }

        popup = WMenuPopup.present(
            view = accountSelectorView,
            items = items,
            yOffset = 3.dp,
            positioning = WMenuPopup.Positioning.BELOW,
            windowBackgroundStyle = WMenuPopup.BackgroundStyle.Cutout.fromView(
                accountSelectorView,
                roundRadius = 24f.dp
            )
        )
        accountSwitcherPopup = popup
    }

    private fun switchAccount(accountId: String) {
        setAccountLoading(true)
        view.lockView()
        view.isEnabled = true
        navigationBar?.unlockView()
        WalletCore.ensureAccountActivated(accountId) { accountChanged ->
            if (accountChanged) {
                WalletCore.notifyEvent(
                    WalletEvent.AccountChangedInApp(persistedAccountsModified = false)
                )
            }
        }
    }

    private fun refreshOptionSelection(accountId: String) {
        val update = update ?: return
        window?.lifecycleScope?.launch {
            try {
                WalletCore.call(
                    ApiMethod.DApp.RefreshWalletConnectPayOptionSelection(
                        update.paymentLink,
                        accountId,
                        update.promiseId
                    )
                )
            } catch (_: Throwable) {
            }
        }
    }

    private fun options() = update?.options.orEmpty()

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 3
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            0 -> 1
            1 -> if (options().isEmpty()) 0 else 1
            else -> if (options().isEmpty()) 1 else options().size
        }
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return when (indexPath.section) {
            0 -> HEADER_CELL
            1 -> TITLE_CELL
            else -> if (options().isEmpty()) EMPTY_CELL else OPTION_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            HEADER_CELL -> WalletConnectPayHeaderCell(context)
            EMPTY_CELL -> WalletConnectPayEmptyCell(context)
            TITLE_CELL -> HeaderCell(context)
            else -> WalletConnectPayOptionCell(context)
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val update = update ?: return
        when (indexPath.section) {
            0 -> {
                (cellHolder.cell as WalletConnectPayHeaderCell).configure(
                    update.merchant,
                    update.paymentInfo?.amount
                )
            }

            1 -> {
                (cellHolder.cell as HeaderCell).configure(
                    LocaleController.getString("Choose Token"),
                    titleColor = WColor.Tint,
                    topRounding = HeaderCell.TopRounding.FIRST_ITEM
                )
            }

            else -> {
                val options = options()
                if (options.isEmpty()) {
                    (cellHolder.cell as WalletConnectPayEmptyCell).configure(update.shouldSwitchWallet == true)
                } else {
                    val option = options[indexPath.row]
                    (cellHolder.cell as WalletConnectPayOptionCell).apply {
                        configure(option, isLast = indexPath.row == options.size - 1)
                        onTap = { confirmOption(it.id) }
                    }
                }
            }
        }
    }

    private fun updateScroll(offset: Int) {
        val alpha = min(1f, max(0f, offset / ViewConstants.GAP.dp.toFloat()))
        topReversedCornerView?.alpha = alpha
        if (offset > 0) resumeBlurViews()
    }

    private fun pauseBlurViews() {
        topReversedCornerView?.pauseBlurring(false)
    }

    private fun resumeBlurViews() {
        topReversedCornerView?.resumeBlurring()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        resumeBlurViews()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        pauseBlurViews()
    }

    private fun confirmOption(optionId: String) {
        val promiseId = update?.promiseId ?: return
        isConfirmed = true
        window?.lifecycleScope?.launch {
            try {
                WalletCore.call(
                    ApiMethod.DApp.ConfirmWalletConnectPayOptionSelection(promiseId, optionId)
                )
            } catch (_: Throwable) {
                isConfirmed = false
            }
        }
        window?.dismissLastNav()
    }

    private fun cancel() {
        val promiseId = update?.promiseId ?: return
        window?.lifecycleScope?.launch {
            try {
                WalletCore.call(
                    ApiMethod.DApp.CancelWalletConnectPay(promiseId, "Canceled by the user")
                )
            } catch (_: Throwable) {
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        WalletCore.unregisterObserver(this)
        if (!isConfirmed)
            cancel()
    }

    private var loadingAccountId: String? = null
    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged,
            is WalletEvent.AccountChangedInApp -> {
                val activeAccountId = AccountStore.activeAccountId ?: return
                if (update?.accountId == activeAccountId ||
                    loadingAccountId == activeAccountId
                ) return
                setAccountLoading(true)
                view.lockView()
                view.isEnabled = true
                navigationBar?.unlockView()
                loadingAccountId = AccountStore.activeAccountId
                refreshOptionSelection(activeAccountId)
            }

            else -> {}
        }
    }
}
