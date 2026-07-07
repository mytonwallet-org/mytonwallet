package org.mytonwallet.app_air.uisettings.viewControllers.mfa

import android.annotation.SuppressLint
import android.content.Context
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.buildConfirmWithTelegramTitle
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TON_CHAIN
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.AccountMfa
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.max

@SuppressLint("ViewConstructor")
class MfaVC(context: Context) : WViewController(context), WalletCore.EventObserver {
    override val TAG = "MfaVC"
    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = false

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    private val viewModel = MfaFlowViewModel(AccountStore.activeAccountId!!)

    private var pollingJob: Job? = null
    private var stateCollectorJob: Job? = null

    // Animation
    private val animationView: WAnimationView by lazy {
        WAnimationView(context).apply {
            play(R.raw.animation_snitch, true, onStart = {})
        }
    }

    // Title: "Confirm with [TG icon] Telegram"
    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(28f, WFont.Medium)
            gravity = Gravity.CENTER
            text = buildConfirmWithTelegramTitle(context)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 32f)
        }
    }

    // Benefit rows (separate instances per container to avoid view-reparent crash)
    private fun makeBenefit(textKey: String, iconResId: Int?) = MfaBenefitView(
        context,
        iconResId = iconResId,
        markdownText = LocaleController.getString(textKey),
    )

    private val installBenefit1 by lazy {
        makeBenefit(
            "Add an extra layer of security for your wallet in TON network.",
            org.mytonwallet.app_air.uicomponents.R.drawable.ic_tg_security,
        )
    }
    private val installBenefit2 by lazy {
        makeBenefit(
            "Sign transfers and important actions with your passcode, then confirm them in Telegram.",
            org.mytonwallet.app_air.uisettings.R.drawable.ic_tg_sign,
        )
    }
    private val installBenefit3 by lazy {
        makeBenefit(
            "This helps protect your funds even if your recovery phrase or keys are compromised.",
            org.mytonwallet.app_air.uisettings.R.drawable.ic_tg_protect,
        )
    }
    private val configuredBenefit2 by lazy {
        makeBenefit(
            "Sign transfers and important actions with your passcode, then confirm them in Telegram.",
            org.mytonwallet.app_air.uisettings.R.drawable.ic_tg_sign,
        )
    }
    private val configuredBenefit3 by lazy {
        makeBenefit(
            "This helps protect your funds even if your recovery phrase or keys are compromised.",
            org.mytonwallet.app_air.uisettings.R.drawable.ic_tg_protect,
        )
    }

    // Linked-user section (shown when configured)
    private val linkedHeaderCell: HeaderCell by lazy {
        HeaderCell(context).apply {
            id = View.generateViewId()
            configure(
                LocaleController.getString("My Telegram Account"),
                titleColor = WColor.Tint,
                topRounding = HeaderCell.TopRounding.NORMAL,
            )
        }
    }
    private val linkedAccountRow: MfaLinkedAccountView by lazy {
        MfaLinkedAccountView(context)
    }

    // Footer
    private val feeLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f)
            gravity = Gravity.CENTER
            text = "${LocaleController.getString("Connection Fee:")} 0.15 ${
                TokenStore.getToken(TONCOIN_SLUG)?.symbol ?: "GRAM"
            }"
        }
    }

    private val primaryButton: WButton by lazy {
        WButton(context, WButton.Type.PRIMARY).apply {
            text = LocaleController.getString("Connect Telegram")
            setOnClickListener { onPrimaryTapped() }
        }
    }

    // Containers
    private val installContainer: WView by lazy {
        val v = WView(context)
        v.addView(installBenefit1, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(installBenefit2, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(installBenefit3, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints {
            toTop(installBenefit1)
            toCenterX(installBenefit1)
            topToBottom(installBenefit2, installBenefit1, 16f)
            toCenterX(installBenefit2)
            topToBottom(installBenefit3, installBenefit2, 16f)
            toCenterX(installBenefit3)
            toBottom(installBenefit3)
        }
        v
    }

    private val configuredContainer: WView by lazy {
        val v = WView(context)
        v.addView(linkedHeaderCell, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(linkedAccountRow, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(configuredBenefit2, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(configuredBenefit3, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints {
            toTop(linkedHeaderCell)
            toCenterX(linkedHeaderCell)
            topToBottom(linkedAccountRow, linkedHeaderCell)
            toCenterX(linkedAccountRow)
            topToBottom(configuredBenefit2, linkedAccountRow, 12f)
            toCenterX(configuredBenefit2)
            topToBottom(configuredBenefit3, configuredBenefit2, 12f)
            toCenterX(configuredBenefit3)
            toBottom(configuredBenefit3)
        }
        v.visibility = View.GONE
        v
    }

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.addView(animationView, ViewGroup.LayoutParams(124.dp, 124.dp))
        v.addView(titleLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        v.addView(installContainer, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(configuredContainer, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints {
            toTop(animationView, 8f)
            toCenterX(animationView)
            topToBottom(titleLabel, animationView, 16f)
            toCenterX(titleLabel, 8f)
            topToBottom(installContainer, titleLabel, 42f)
            toCenterX(installContainer)
            topToBottom(configuredContainer, titleLabel, 42f)
            toCenterX(configuredContainer)
            toBottom(installContainer, 8f)
        }
        v
    }

    private val scrollView: WScrollView by lazy {
        WScrollView(WeakReference(this)).apply {
            id = View.generateViewId()
            addView(scrollingContentView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            clipToPadding = false
        }
    }

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown by lazy {
        ReversedCornerViewUpsideDown(context, scrollView).apply {
            if (ignoreSideGuttering) setHorizontalPadding(0f)
        }
    }

    override fun setupViews() {
        super.setupViews()
        setNavTitle("")
        setupNavBar(true)

        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomReversedCornerViewUpsideDown,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                ConstraintLayout.LayoutParams.MATCH_CONSTRAINT,
            ),
        )
        view.addView(feeLabel, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(
            primaryButton,
            ConstraintLayout.LayoutParams(ConstraintLayout.LayoutParams.MATCH_CONSTRAINT, 50.dp)
        )

        view.setConstraints {
            toTop(scrollView)
            toCenterX(scrollView)
            toBottom(scrollView)
            toCenterX(feeLabel, 16f)
            bottomToTop(feeLabel, primaryButton, 8f)
            toStartPx(primaryButton, 16.dp + additionalTabletPadding + systemBarStartInset)
            toEndPx(primaryButton, 16.dp + systemBarEndInset)
            toBottomPx(primaryButton, buttonsBottomMargin())
            topToTop(
                bottomReversedCornerViewUpsideDown,
                feeLabel,
                -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS,
            )
            toBottom(bottomReversedCornerViewUpsideDown)
        }
        applyScrollPadding()

        bindViewModel()
        updateForState(viewModel.state, AccountStore.activeAccount?.byChain?.get(TON_CHAIN)?.mfa)
        WalletCore.registerObserver(this)
        updateTheme()
    }

    private fun applyScrollPadding() {
        val topInset = (navigationController?.getSystemBars()?.top ?: 0) +
            WNavigationBar.DEFAULT_HEIGHT.dp
        scrollView.setPadding(
            0,
            topInset,
            0,
            buttonsBottomMargin() +
                primaryButton.buttonHeight +
                40.dp +
                ViewConstants.BLOCK_RADIUS.dp.toInt(),
        )
    }

    private fun bindViewModel() {
        viewModel.onInstallConfirmationRequested = { user ->
            presentConfirm(
                titleText = LocaleController.getString("Confirm Connection"),
                user = user,
                startWithBiometrics = false,
                onSuccess = { showInstalledScreen() },
                task = { passcode -> viewModel.confirmInstall(passcode) },
            )
        }
        viewModel.onRemoveConfirmationRequested = { user ->
            val resolvedUser = user ?: AccountMfa.User(
                name = LocaleController.getString("Telegram Account"),
            )
            presentConfirm(
                titleText = LocaleController.getString("Confirm Disconnection"),
                user = resolvedUser,
                startWithBiometrics = true,
                onSuccess = { popSelf() },
                task = { passcode -> viewModel.confirmRemove(context, passcode) },
            )
        }

        stateCollectorJob = CoroutineScope(Dispatchers.Main).launch {
            viewModel.stateFlow.collect { state ->
                updateForState(state, AccountStore.activeAccount?.byChain?.get(TON_CHAIN)?.mfa)
            }
        }
    }

    private fun updateForState(state: MfaFlowViewModel.State, mfa: AccountMfa?) {
        val configured = mfa != null
        val tonBalance = AccountStore.activeAccountId?.let {
            BalanceStore.getBalances(it)?.get(TONCOIN_SLUG)
        } ?: BigInteger.ZERO
        val installAvailable = tonBalance >= MfaFlowViewModel.INSTALL_FEE

        configuredContainer.visibility = if (configured) View.VISIBLE else View.GONE
        installContainer.visibility = if (configured) View.GONE else View.VISIBLE

        mfa?.user?.let { linkedAccountRow.bind(it) }

        primaryButton.text = when {
            configured -> LocaleController.getString("Unlink Account")
            state.isWaitingForTelegramInstall || installAvailable -> LocaleController.getString("Connect Telegram")
            else -> LocaleController.getString("Insufficient Balance")
        }
        primaryButton.type =
            if (configured) WButton.Type.DESTRUCTIVE else WButton.Type.PRIMARY
        primaryButton.isLoading = state.isWaitingForTelegramRemoval || state.isRefreshingMfa
        primaryButton.setEnabled(
            !state.isRefreshingMfa && (
                if (configured) !state.isWaitingForTelegramRemoval
                else state.isWaitingForTelegramInstall || installAvailable
                ),
            true,
        )

        feeLabel.setTextColor(
            (if (!configured && !installAvailable) WColor.Red else WColor.SecondaryText).color
        )
        feeLabel.visibility = if (configured) View.GONE else View.VISIBLE
    }

    private fun onPrimaryTapped() {
        val mfa = AccountStore.activeAccount?.byChain?.get(TON_CHAIN)?.mfa
        CoroutineScope(Dispatchers.Main).launch {
            try {
                viewModel.primaryAction(context, mfa)
            } catch (e: Throwable) {
                showAlert(null, e.localizedMessage ?: e.toString())
            }
        }
    }

    private fun presentConfirm(
        titleText: String,
        user: AccountMfa.User,
        startWithBiometrics: Boolean,
        onSuccess: () -> Unit,
        task: suspend (String) -> Unit,
    ) {
        if (navigationController?.viewControllers?.lastOrNull() !== this) return
        val headerView = MfaConfirmHeaderView(
            context,
            titleText,
            user,
            AccountStore.activeAccount,
        )
        val confirmVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.CustomHeader(
                headerView,
                navbarTitle = titleText,
                startWithBiometrics = startWithBiometrics,
                showNavbarTitle = false
            ),
            task = { passcode ->
                CoroutineScope(Dispatchers.Main).launch {
                    try {
                        task(passcode)
                        onSuccess()
                    } catch (e: Throwable) {
                        showAlert(null, e.localizedMessage ?: e.toString())
                        popSelf()
                    }
                }
            },
        )
        push(confirmVC)
    }

    private fun showInstalledScreen() {
        val nav = navigationController ?: run {
            popSelf()
            return
        }
        nav.push(MfaInstalledVC(context), true, onCompletion = {
            navigationController?.removePrevViewControllerOnly()
        })
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        CoroutineScope(Dispatchers.Main).launch {
            viewModel.refreshStoredMfa()
            startPolling()
        }
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        stopPolling()
    }

    override fun onDestroy() {
        stopPolling()
        stateCollectorJob?.cancel()
        stateCollectorJob = null
        WalletCore.unregisterObserver(this)
        super.onDestroy()
    }

    private fun startPolling() {
        if (pollingJob?.isActive == true) return
        pollingJob = CoroutineScope(Dispatchers.Main).launch {
            while (isActive) {
                viewModel.pollIfNeeded()
                delay(1000L)
            }
        }
    }

    private fun stopPolling() {
        pollingJob?.cancel()
        pollingJob = null
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        scrollView.setBackgroundColor(WColor.SecondaryBackground.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
        linkedHeaderCell.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setConstraints {
            toStartPx(primaryButton, 16.dp + additionalTabletPadding + systemBarStartInset)
            toEndPx(primaryButton, 16.dp + systemBarEndInset)
            toBottomPx(primaryButton, buttonsBottomMargin())
        }
        scrollingContentView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            0,
        )
        applyScrollPadding()
    }

    private fun buttonsBottomMargin(): Int {
        return 16.dp + max(
            (navigationController?.getSystemBars()?.bottom ?: 0),
            (navigationController?.imeInsetBottom ?: 0),
        )
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.ByChainUpdated,
            is WalletEvent.BalanceChanged -> {
                updateForState(
                    viewModel.state,
                    AccountStore.activeAccount?.byChain?.get(TON_CHAIN)?.mfa,
                )
            }

            else -> {}
        }
    }

    private fun popSelf() {
        navigationController?.pop(true)
    }
}
