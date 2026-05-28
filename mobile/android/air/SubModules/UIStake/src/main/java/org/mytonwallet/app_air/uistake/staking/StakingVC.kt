package org.mytonwallet.app_air.uistake.staking

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.lifecycle.ViewModelProvider
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WLinearLayout
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uistake.confirm.ConfirmStakingHeaderView
import org.mytonwallet.app_air.uistake.helpers.StakingMessageHelpers
import org.mytonwallet.app_air.uistake.staking.views.StakeDetailView
import org.mytonwallet.app_air.uistake.staking.views.StakeInputView
import org.mytonwallet.app_air.uistake.staking.views.UnstakeDetailView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcontext.utils.PriceConversionUtils
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.max

@SuppressLint("ViewConstructor")
class StakingVC(
    context: Context,
    tokenSlug: String,
    mode: StakingViewModel.Mode,
) : WViewControllerWithModelStore(context) {
    override val TAG = "Staking"

    private val viewmodelFactory = AddStakeViewModelFactory(tokenSlug, mode)
    private val stakingViewModel by lazy {
        ViewModelProvider(
            this,
            viewmodelFactory
        )[StakingViewModel::class.java]
    }

    override val isSwipeBackAllowed: Boolean = true

    private val stakeInputView by lazy {
        StakeInputView(
            context,
            onClickEquivalentLabel = {
                stakingViewModel.onEquivalentClicked()
            },
            onClickMaxBalanceButton = { onMaxBalanceButtonClicked() }
        )
    }
    private val spacerView = WView(context)
    private val detailHeader = WLabel(context).apply {
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        text = LocaleController.getString("Details")

        setStyle(16f, WFont.Medium)
        setPadding(20.dp, 16.dp, 20.dp, 7.dp)
    }
    private val stakingDetailView by lazy {
        StakeDetailView(context, onWhySafeClick = { showWhySafeAlert() })
    }
    private val unstakingDetailView by lazy { UnstakeDetailView(context) }
    private val linearLayout = WLinearLayout(context).apply {
        addView(stakeInputView)

        addView(spacerView, ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp))
        addView(detailHeader, ViewGroup.LayoutParams(MATCH_PARENT, 48.dp))
        when (mode) {
            StakingViewModel.Mode.STAKE -> {
                addView(stakingDetailView)
            }

            StakingViewModel.Mode.UNSTAKE -> {
                addView(unstakingDetailView)
            }
        }
    }

    private val stakeButton: WButton by lazy {
        val wButton = WButton(context, WButton.Type.PRIMARY)
        wButton.setOnClickListener {
            if (stakingViewModel.canProceedToConfirm()) {
                if (AccountStore.activeAccount?.isHardware == true) {
                    confirmHardware()
                } else {
                    pushConfirmView()
                }
            }
        }
        wButton
    }

    private val scrollView = WScrollView(WeakReference(this))

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown =
        ReversedCornerViewUpsideDown(context, scrollView).apply {
            if (ignoreSideGuttering)
                setHorizontalPadding(0f)
        }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(
            if (stakingViewModel.isStake()) LocaleController.getString("Add Stake")
            else LocaleController.getString("\$unstake_action")
        )
        setupNavBar(true)
        navigationBar?.addCloseButton()

        scrollView.addView(linearLayout, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomReversedCornerViewUpsideDown,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                MATCH_CONSTRAINT
            )
        )
        view.addView(
            stakeButton,
            ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT)
        )

        view.setConstraints {
            topToBottom(scrollView, navigationBar!!)
            toStart(scrollView)
            toEnd(scrollView)
            bottomToTop(scrollView, stakeButton, 20f)

            toStart(stakeButton, 20f)
            toEnd(stakeButton, 20f)
            toBottomPx(
                stakeButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )

            topToTop(
                bottomReversedCornerViewUpsideDown,
                stakeButton,
                -ViewConstants.GAP - ViewConstants.BIG_RADIUS
            )
            toBottom(bottomReversedCornerViewUpsideDown)
        }

        stakeInputView.setAsset(TokenStore.getToken(stakingViewModel.currentToken.unstakedSlug))

        updateTheme()

        initViewModel()
        setupObservers()
    }

    private fun initViewModel() {
        stakingViewModel.apy.value = stakingViewModel.stakingState?.annualYield ?: 0.0f

        stakeInputView.setOnAmountInputListener {
            if (!stakingViewModel.isInputListenerLocked) {
                stakingViewModel.onAmountInputChanged(it)
            }
        }
    }

    private fun setupObservers() {
        collectFlow(stakingViewModel.viewState) { viewState ->
            updateView(viewState)
            stakeInputView.setMaxBalance(viewState.maxAmountString)
        }

        collectFlow(stakingViewModel.eventsFlow) { event ->
            handleViewModelEvent(event)
        }

        collectFlow(stakingViewModel.inputStateFlow) { inputState ->
            if (inputState.isInputCurrencyCrypto) {
                if (stakingViewModel.isInputListenerLocked) {
                    if ((inputState.amountInCrypto?.compareTo(BigInteger.ZERO) ?: 0) > 0) {
                        stakeInputView.amountEditText.setText(
                            CoinUtils.toDecimalString(
                                inputState.amountInCrypto ?: BigInteger.ZERO,
                                stakingViewModel.currentToken.decimals
                            )
                        )
                        stakeInputView.amountEditText.setSelection(
                            stakeInputView.amountEditText.text?.length ?: 0
                        )
                    } else {
                        stakeInputView.amountEditText.setText("")
                    }
                    stakeInputView.amountEditText.hideBaseCurrencySymbol()
                    stakeInputView.setShowingBaseCurrency(false)
                    stakingViewModel.isInputListenerLocked = false
                }

                stakeInputView.getEquivalentLabel().setAmount(
                    inputState.amountInBaseCurrency ?: BigInteger.ZERO,
                    WalletCore.baseCurrency.decimalsCount,
                    WalletCore.baseCurrency.sign,
                    WalletCore.baseCurrency.decimalsCount,
                    true
                )
            } else {
                if (stakingViewModel.isInputListenerLocked) {
                    if ((inputState.amountInBaseCurrency?.compareTo(BigInteger.ZERO) ?: 0) > 0) {
                        stakeInputView.amountEditText.setText(
                            CoinUtils.toDecimalString(
                                inputState.amountInBaseCurrency ?: BigInteger.ZERO,
                                WalletCore.baseCurrency.decimalsCount
                            )
                        )
                        stakeInputView.amountEditText.setSelection(
                            stakeInputView.amountEditText.text?.length ?: 0
                        )
                    } else {
                        stakeInputView.amountEditText.setText("")
                    }

                    stakeInputView.setShowingBaseCurrency(true)
                    stakeInputView.amountEditText.setBaseCurrencySymbol(WalletCore.baseCurrency.sign)
                    stakingViewModel.isInputListenerLocked = false
                }

                stakeInputView.getEquivalentLabel().setAmount(
                    inputState.amountInCrypto ?: BigInteger.ZERO,
                    stakingViewModel.currentToken.decimals,
                    stakingViewModel.tokenSymbol, // Show TON symbol in both Stake and Unstake
                    inputState.amountInCrypto?.smartDecimalsCount(stakingViewModel.currentToken.decimals)
                        ?: 9,
                    true
                )
            }
        }
    }

    private fun updateView(viewState: StakeViewState) {
        stakeButton.isEnabled = viewState.buttonState.isEnabled
        stakeButton.text = when (viewState.buttonState) {
            is StakeButtonState.LowerThanMinAmount -> {
                val minAmountStr = stakingViewModel.minRequiredAmount.toString(
                    stakingViewModel.currentToken.decimals,
                    "",
                    stakingViewModel.minRequiredAmount.smartDecimalsCount(stakingViewModel.currentToken.decimals),
                    showPositiveSign = false,
                    forceCurrencyToRight = true
                )
                viewState.buttonState.getText(
                    minAmountStr,
                    stakingViewModel.tokenSymbol
                )
            }

            is StakeButtonState.InsufficientBalance -> {
                viewState.buttonState.getText(stakingViewModel.tokenSymbol)
            }

            is StakeButtonState.InsufficientFeeAmount -> {
                val minAmountStr = stakingViewModel.minRequiredAmount.toString(
                    stakingViewModel.currentToken.decimals,
                    "",
                    stakingViewModel.minRequiredAmount.smartDecimalsCount(stakingViewModel.currentToken.decimals),
                    false,
                    true
                )
                viewState.buttonState.getText("$minAmountStr ${stakingViewModel.tokenSymbol}")
            }

            is StakeButtonState.EmptyAmount -> {
                viewState.buttonState.getText(
                    stakingViewModel.tokenSymbol,
                    stakingViewModel.mode
                )
            }

            is StakeButtonState.ValidAmount -> {
                viewState.buttonState.getText(
                    stakingViewModel.tokenSymbol,
                    stakingViewModel.mode
                )
            }
        }

        stakeInputView.amountEditText.isError.animatedValue = viewState.isInputTextRed
        // Show TON symbol in both Stake and Unstake
        val feeText =
            if (viewState.currentFee.isNotEmpty()) "${
                LocaleController.getString("\$fee_value_with_colon")
                    .replace("%fee%", "\u202F${viewState.currentFee}")
            } ${MBaseCurrency.TON.sign}" else ""
        stakeInputView.feeLabel.text = feeText
        when (stakingViewModel.mode) {
            StakingViewModel.Mode.STAKE -> {
                stakingDetailView.setEarning(viewState.estimatedEarning)
                stakingDetailView.setApy(viewState.currentApy)
            }

            StakingViewModel.Mode.UNSTAKE -> {
                val state = stakingViewModel.stakingState

                fun show() {
                    detailHeader.fadeIn()
                    unstakingDetailView.fadeIn()
                }

                fun hide() {
                    detailHeader.fadeOut()
                    unstakingDetailView.fadeOut()
                }

                when (state) {
                    is StakingState.Liquid -> {
                        show()
                        val token = TokenStore.getToken(TONCOIN_SLUG)!!
                        val instantAvailableAmount = state.instantAvailable
                        if (stakingViewModel.amount <= instantAvailableAmount) {
                            unstakingDetailView.setInstantWithdrawDetails(
                                instantAvailableAmount.toString(
                                    token.decimals,
                                    token.symbol,
                                    instantAvailableAmount.smartDecimalsCount(token.decimals),
                                    false
                                )
                            )
                        } else {
                            unstakingDetailView.setWithdrawTime(state)
                        }
                    }

                    is StakingState.Nominators -> {
                        show()
                        unstakingDetailView.setWithdrawTime(state)
                    }

                    is StakingState.Jetton -> {
                        show()
                        unstakingDetailView.setInstantWithdrawDetails(null)
                    }

                    is StakingState.Ethena -> {
                        show()
                        unstakingDetailView.setWithdrawTime(
                            LocaleController.getPlural(7, "\$in_days")
                        )
                    }

                    else -> hide()
                }
            }
        }
    }

    private fun updateFieldValue() {
        val fieldValue =
            if (stakingViewModel.switchedToBaseCurrencyInput) stakingViewModel.amountInBaseCurrency else stakingViewModel.amount
        stakeInputView.setAssetAsBaseCurrency(
            stakingViewModel.fieldMaximumFraction,
            if (fieldValue > BigInteger.valueOf(0)) fieldValue.toString(
                stakingViewModel.fieldMaximumFraction,
                "",
                stakingViewModel.fieldMaximumFraction,
                false
            ) else ""
        )
    }

    private fun onMaxBalanceButtonClicked() {
        val maxBalance = stakingViewModel.tokenBalance

        val maxBalanceStr: String =
            if (stakingViewModel.inputStateValue().isInputCurrencyCrypto) {
                CoinUtils.toDecimalString(
                    maxBalance,
                    stakingViewModel.currentToken.decimals
                )
            } else {
                CoinUtils.toDecimalString(
                    PriceConversionUtils.convertTokenToBaseCurrency(
                        maxBalance,
                        stakingViewModel.currentToken.decimals,
                        stakingViewModel.tokenPrice,
                        WalletCore.baseCurrency.decimalsCount
                    ),
                    WalletCore.baseCurrency.decimalsCount
                )
            }
        stakeInputView.amountEditText.setText(maxBalanceStr)
        stakeInputView.amountEditText.setSelection(stakeInputView.amountEditText.text?.length ?: 0)
    }

    private fun handleViewModelEvent(events: StakingViewModel.VmToVcEvents) {
        when (events) {
            is StakingViewModel.VmToVcEvents.SubmitSuccess -> {
                onDone()
            }

            is StakingViewModel.VmToVcEvents.SubmitFailure -> {
                pop()
                showError(events.error?.parsed)
            }

            else -> {}
        }
    }

    private fun pushConfirmView() {
        view.hideKeyboard()
        val passcodeConfirmVC = PasscodeConfirmVC(
            context = context,
            passcodeViewState = PasscodeViewState.CustomHeader(
                headerView = confirmHeaderView,
                navbarTitle = LocaleController.getString("Confirm")
            ),
            task = { passcode ->
                stakingViewModel.onStakeConfirmed(passcode)
            }
        )
        push(passcodeConfirmVC)
    }

    private fun showWhySafeAlert() {
        showAlert(
            title = LocaleController.getString("Why is staking safe?"),
            text = StakingMessageHelpers.whyStakingIsSafeDescription(stakingViewModel.tokenSlug)
                ?: return,
            button = LocaleController.getString("OK"),
            preferPrimary = false,
            allowLinkInText = true
        )
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        spacerView.setBackgroundColor(WColor.SecondaryBackground.color)
        detailHeader.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BIG_RADIUS.dp,
            0f
        )
        detailHeader.setTextColor(WColor.PrimaryText.color)
        when (stakingViewModel.mode) {
            StakingViewModel.Mode.STAKE -> {
                stakingDetailView.setBackgroundColor(
                    WColor.Background.color,
                    0f,
                    ViewConstants.BIG_RADIUS.dp
                )
            }

            StakingViewModel.Mode.UNSTAKE -> {
                unstakingDetailView.setBackgroundColor(
                    WColor.Background.color,
                    0f,
                    ViewConstants.BIG_RADIUS.dp
                )
            }
        }
        stakeInputView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.TOP_RADIUS.dp,
            ViewConstants.BIG_RADIUS.dp
        )
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        linearLayout.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        view.setConstraints {
            toBottomPx(
                stakeButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }
    }

    private fun confirmHardware() {
        view.lockView()
        val account = AccountStore.activeAccount!!
        val ledgerConnectVC = LedgerConnectVC(
            context, LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                account.tonAddress!!,
                LedgerConnectVC.SignData.Staking(
                    isStaking = stakingViewModel.isStake(),
                    accountId = account.accountId,
                    amount = stakingViewModel.getAmountInCrypto() ?: BigInteger.ZERO,
                    stakingState = stakingViewModel.stakingState!!,
                    realFee = stakingViewModel.realFee,
                ),
            ) {
                onDone()
            }, headerView = confirmHeaderView
        )
        push(ledgerConnectVC, onCompletion = {
            view.unlockView()
        })
    }

    private fun onDone() {
        navigationController?.window?.dismissLastNav()
        // TODO display success alert
    }

    private val confirmHeaderView: View
        get() {
            return ConfirmStakingHeaderView(context).apply {
                config(
                    token = stakingViewModel.currentToken,
                    amountInCrypto = stakingViewModel.inputStateValue().amountInCrypto
                        ?: BigInteger.ZERO,
                    showPositiveSignForAmount = !stakingViewModel.isStake(),
                    messageString = if (stakingViewModel.isStake()) LocaleController.getString("Confirm Staking")
                    else LocaleController.getString("Confirm Unstaking")
                )
            }
        }
}
