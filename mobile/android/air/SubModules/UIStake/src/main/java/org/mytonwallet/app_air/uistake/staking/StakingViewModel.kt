package org.mytonwallet.app_air.uistake.staking

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uistake.util.getTonStakingFees
import org.mytonwallet.app_air.walletbasecontext.utils.signSpace
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcontext.utils.PriceConversionUtils
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.submitStake
import org.mytonwallet.app_air.walletcore.api.submitUnstake
import org.mytonwallet.app_air.walletcore.tokenSlugToStakingSlug
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

class StakingViewModel(val tokenSlug: String, val mode: Mode) : ViewModel(),
    WalletCore.EventObserver {

    enum class Mode {
        STAKE,
        UNSTAKE
    }

    companion object {
        val ONE_TON: BigInteger = BigInteger.valueOf(1_000_000_000)
        val MINIMUM_REQUIRED_AMOUNT_TON: BigInteger =
            (BigInteger.valueOf(3) * ONE_TON) + (ONE_TON / BigInteger.TEN)
    }

    val token = TokenStore.getToken(tokenSlug)
    val tokenSymbol = token?.symbol ?: ""
    var tokenPrice = token?.price // Updates on events
    val isNativeToken = token?.isBlockchainNative == true
    val nativeBalance: BigInteger
        get() {
            val slug = token?.nativeToken?.slug ?: return BigInteger.ZERO
            return BalanceStore.getBalances(accountId)?.get(slug) ?: BigInteger.ZERO
        }
    var apy = MutableStateFlow(0.0f)
    val minRequiredAmount: BigInteger =
        if (AccountStore.stakingData?.stakingState(tokenSlug) is StakingState.Nominators) {
            BigInteger.valueOf(10001) * ONE_TON
        } else {
            1.0.toBigInteger(TokenStore.getToken(tokenSlug)!!.decimals)!!
        }

    //
    private val _viewState: MutableSharedFlow<StakeViewState> =
        MutableSharedFlow(replay = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val viewState = _viewState.asSharedFlow()
    private fun viewStateValue() = viewState.replayCache.last()

    private var shouldRenderBalanceWithSmallFee = false
    lateinit var tokenBalance: BigInteger

    var isInputListenerLocked = false

    //
    var accountId = AccountStore.activeAccountId
    val stakingState: StakingState?
        get() {
            return AccountStore.stakingData?.stakingState(tokenSlug)
        }
    var currentToken = TokenStore.getToken(if (mode == Mode.STAKE) tokenSlug else stakedTokenSlug)!!
    private val stakedTokenSlug: String get() = tokenSlugToStakingSlug(tokenSlug) ?: throw Exception()
    private val tonOperationFees = getTonStakingFees(stakingState?.stakingType).run {
        if (mode == Mode.UNSTAKE) this["unstake"] else this["stake"]
    }
    private val networkFee: BigInteger = tonOperationFees?.gas ?: ONE_TON
    val realFee: BigInteger = tonOperationFees!!.real

    //
    var amount = BigInteger.valueOf(0)

    // Input State
    private val _inputStateFlow =
        MutableSharedFlow<InputState>(replay = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val inputStateFlow = _inputStateFlow.asSharedFlow()
    fun inputStateValue() = inputStateFlow.replayCache.last()

    data class InputState(
        val tokenToStake: MToken?,
        val isInputCurrencyCrypto: Boolean,
        val amountInCrypto: BigInteger?,
        val amountInBaseCurrency: BigInteger?,
    )

    //
    fun onAmountInputChanged(inputAmount: CharSequence?) {
        val state = inputStateValue()
        val amountInCrypto: BigInteger?
        val amountInBaseCurrency: BigInteger?

        if (state.isInputCurrencyCrypto) {
            amountInCrypto = CoinUtils.fromDecimal(inputAmount?.toString(), currentToken.decimals)
            amountInBaseCurrency = PriceConversionUtils.convertTokenToBaseCurrency(
                inputAmount.toString(),
                currentToken.decimals,
                tokenPrice,
                WalletCore.baseCurrency.decimalsCount
            )
        } else {
            amountInCrypto =
                PriceConversionUtils.convertBaseCurrencyToToken(
                    inputAmount.toString(),
                    currentToken.decimals,
                    tokenPrice,
                    WalletCore.baseCurrency.decimalsCount
                )
            amountInBaseCurrency = CoinUtils.fromDecimal(
                inputAmount?.toString(),
                WalletCore.baseCurrency.decimalsCount
            )
        }
        _inputStateFlow.tryEmit(
            state.copy(
                amountInCrypto = amountInCrypto,
                amountInBaseCurrency = amountInBaseCurrency,
            )
        )

        updateViewStateOnInputChanged()
        //updateFee()
    }

    fun onEquivalentClicked() {
        val isInputCurrencyCrypto = inputStateValue().isInputCurrencyCrypto

        isInputListenerLocked = true
        _inputStateFlow.tryEmit(
            inputStateValue().copy(
                isInputCurrencyCrypto = !isInputCurrencyCrypto
            )
        )

        updateViewStateOnInputChanged() // explicit update
    }

    private fun updateViewStateOnInputChanged() {
        val amountInCrypto = inputStateValue().amountInCrypto ?: BigInteger.ZERO

        if (amountInCrypto == BigInteger.ZERO) {
            _viewState.tryEmit(
                viewStateValue().emptyInput().copy(
                    maxAmountString = createMaxString(),
                    estimatedEarning = createEstimatedEarningString(amountInCrypto)
                )
            )
            return
        }

        val isBalanceSufficient = checkInputAmountIsBalanceSufficient(amountInCrypto)
        val isMoreThanMinRequired = isInputAmountMoreThanMinRequired(amountInCrypto)
        val isInsuffcientFeeAmount = isInsufficientFeeAmount(amountInCrypto)


        val buttonState =
            if (!isMoreThanMinRequired) StakeButtonState.LowerThanMinAmount
            else if (!isBalanceSufficient) StakeButtonState.InsufficientBalance
            else if (isInsuffcientFeeAmount) StakeButtonState.InsufficientFeeAmount
            else StakeButtonState.ValidAmount

        _viewState.tryEmit(
            viewStateValue().copy(
                buttonState = buttonState,
                isInputTextRed = !isBalanceSufficient || !isMoreThanMinRequired || isInsuffcientFeeAmount,
                estimatedEarning = createEstimatedEarningString(amountInCrypto),
                currentApy = apy.value.toString(),
                maxAmountString = createMaxString()
            )
        )

        // TODO withdrawalType
    }

    private fun checkInputAmountIsBalanceSufficient(inputAmount: BigInteger) =
        inputAmount <= tokenBalance

    private fun isInputAmountMoreThanMinRequired(inputAmount: BigInteger) =
        isUnstake() || inputAmount >= minRequiredAmount

    private fun isInsufficientFeeAmount(inputAmount: BigInteger): Boolean {
        return (!isStake() || (isStake() && inputAmount >= minRequiredAmount)) &&
            (nativeBalance < networkFee || (isNativeToken && nativeBalance < amount + networkFee)) &&
            (tokenSlug != TONCOIN_SLUG || !shouldRenderBalanceWithSmallFee)
    }

    private fun calculateEstimatedEarning(amount: BigInteger, apy: Float): BigInteger {
        val apyMultiplier = apy * 1000

        val earnings = amount.multiply(BigInteger.valueOf(apyMultiplier.toLong()))
            .divide(BigInteger.valueOf(100000))

        return earnings
    }

    private fun createMaxString(): String {
        val balanceForMax = tokenBalance
        val symbol = tokenSymbol // Show TON symbol in both Stake and Unstake

        return if (inputStateValue().isInputCurrencyCrypto) {
            balanceForMax.toString(
                decimals = currentToken.decimals,
                currency = symbol,
                currencyDecimals = balanceForMax.smartDecimalsCount(currentToken.decimals),
                showPositiveSign = false
            )
        } else {
            val baseCurrency = WalletCore.baseCurrency
            val maxAmountInBaseCurrency =
                PriceConversionUtils.convertTokenToBaseCurrency(
                    balanceForMax,
                    currentToken.decimals,
                    tokenPrice,
                    baseCurrency?.decimalsCount
                )
            maxAmountInBaseCurrency.toString(
                decimals = baseCurrency?.decimalsCount ?: 2,
                currency = baseCurrency?.sign ?: "",
                currencyDecimals = maxAmountInBaseCurrency.smartDecimalsCount(
                    baseCurrency?.decimalsCount ?: 2
                ),
                showPositiveSign = false
            )
        }
    }

    private fun createEstimatedEarningString(amountInCrypto: BigInteger): String {
        val estimatedEarning = calculateEstimatedEarning(amountInCrypto, apy.value)

        val estimatedEarningsSymbol =
            if (inputStateValue().isInputCurrencyCrypto) currentToken.symbol
            else WalletCore.baseCurrency.sign

        val estimatedEarningStr =
            if (estimatedEarning == BigInteger.ZERO) "0"
            else {
                if (inputStateValue().isInputCurrencyCrypto) {
                    estimatedEarning.toString(
                        currentToken.decimals,
                        "",
                        estimatedEarning.smartDecimalsCount(currentToken.decimals),
                        true
                    )
                } else {
                    "+$signSpace${
                        CoinUtils.toDecimalString(
                            PriceConversionUtils.convertTokenToBaseCurrency(
                                estimatedEarning,
                                currentToken.decimals,
                                tokenPrice,
                                WalletCore.baseCurrency.decimalsCount
                            ),
                            WalletCore.baseCurrency.decimalsCount
                        )
                    }"
                }
            }

        return "$estimatedEarningStr $estimatedEarningsSymbol"
    }

    fun canProceedToConfirm(): Boolean {
        // TODO validate amount
        return true
    }

    fun getAmountInCrypto(): BigInteger? {
        return inputStateValue().amountInCrypto
    }

    fun onStakeConfirmed(passcode: String) {
        if (mode == Mode.STAKE)
            submitStake(passcode)
        else submitUnstake(passcode)
    }

    private fun submitStake(passcode: String) {
        if (stakingState == null) return

        viewModelScope.launch {
            try {
                val result = WalletCore.submitStake(
                    accountId!!,
                    amount = inputStateValue().amountInCrypto ?: BigInteger.ZERO,
                    stakingState!!,
                    passcode = passcode,
                    realFee = realFee
                )
                _eventsFlow.tryEmit(VmToVcEvents.SubmitSuccess(result.activityId))
            } catch (e: JSWebViewBridge.ApiError) {
                e.printStackTrace()
                _eventsFlow.tryEmit(VmToVcEvents.SubmitFailure(e))
            } catch (e: Throwable) {
                e.printStackTrace()
                _eventsFlow.tryEmit(VmToVcEvents.SubmitFailure(null))
            }
        }
    }

    private fun submitUnstake(passcode: String) {
        if (stakingState == null) return

        viewModelScope.launch {
            try {
                val result = WalletCore.submitUnstake(
                    accountId!!,
                    amount = inputStateValue().amountInCrypto ?: BigInteger.ZERO,
                    stakingState!!,
                    passcode = passcode,
                    realFee = realFee
                )
                _eventsFlow.tryEmit(VmToVcEvents.SubmitSuccess(result.activityId))
            } catch (e: JSWebViewBridge.ApiError) {
                e.printStackTrace()
                _eventsFlow.tryEmit(VmToVcEvents.SubmitFailure(e))
            } catch (e: Throwable) {
                e.printStackTrace()
                _eventsFlow.tryEmit(VmToVcEvents.SubmitFailure(null))
            }
        }
    }

    // Wallet State
    private val _walletStateFlow = MutableStateFlow(createWalletState())

    data class WalletState(
        var accountId: String,
        var accountName: String,
        val addressByChain: Map<String, String>,
        val balances: Map<String, BigInteger>,
        val assets: List<MApiSwapAsset>
    )

    private fun createWalletState(): WalletState? {
        val account = AccountStore.activeAccount ?: return null
        val assets = TokenStore.swapAssets2 ?: return null
        return WalletState(
            accountId = account.accountId,
            accountName = account.name,
            addressByChain = account.addressByChain,
            balances = BalanceStore.getBalances(account.accountId) ?: emptyMap(),
            assets = assets
        )
    }

    private val _eventsFlow: MutableSharedFlow<VmToVcEvents> =
        MutableSharedFlow(replay = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val eventsFlow = _eventsFlow.asSharedFlow()

    sealed class VmToVcEvents {
        data class SubmitSuccess(val activityId: String) : VmToVcEvents()
        data class SubmitFailure(val error: JSWebViewBridge.ApiError?) : VmToVcEvents()
        object InitialState : VmToVcEvents()
    }

    // ui state
    data class StakeUiInputState(
        val wallet: WalletState,
        private val input: InputState,
    ) {
        val tokenToStake: MToken? = input.tokenToStake

        internal val tokenToStakeBalance: BigInteger =
            tokenToStake?.let { token -> wallet.balances[token.slug] } ?: BigInteger.ZERO

        val maxAmountFmt: String
            get() {
                val token = tokenToStake ?: return ""
                return tokenToStakeBalance.toString(
                    decimals = token.decimals,
                    currency = token.symbol,
                    currencyDecimals = tokenToStakeBalance.smartDecimalsCount(token.decimals),
                    showPositiveSign = false
                )
            }

    }

    val uiInputStateFlow: Flow<StakeUiInputState> =
        combine(_walletStateFlow, _inputStateFlow, this::buildUiInputStateFlow).filterNotNull()

    private fun buildUiInputStateFlow(
        walletOpt: WalletState?,
        input: InputState
    ): StakeUiInputState? {
        val wallet = walletOpt ?: return null
        return StakeUiInputState(wallet = wallet, input = input)
    }

    init {
        updateBalance()

        WalletCore.registerObserver(this)
        _viewState.tryEmit(StakeViewState.initialState())
        _eventsFlow.tryEmit(VmToVcEvents.InitialState)
        _inputStateFlow.tryEmit(
            InputState(
                tokenToStake = null,
                isInputCurrencyCrypto = true,
                amountInCrypto = null,
                amountInBaseCurrency = null,
            )
        )

        collectFlow(_inputStateFlow) { input ->
            if (input.tokenToStake == null) {
                _inputStateFlow.tryEmit(
                    inputStateValue().copy(
                        tokenToStake = TokenStore.getToken(tokenSlug),
                    )
                )
            }
        }

        collectFlow(apy) {
            //updateFee()
            _viewState.tryEmit(
                viewStateValue().copy(
                    estimatedEarning = createEstimatedEarningString(
                        inputStateValue().amountInCrypto ?: BigInteger.ZERO
                    ),
                    currentApy = apy.value.toString(),
                    currentFee = (tonOperationFees?.real ?: BigInteger.ZERO).toString(
                        decimals = 9,
                        currency = "",
                        currencyDecimals =
                            (tonOperationFees?.real ?: BigInteger.ZERO).smartDecimalsCount(9),
                        showPositiveSign = false,
                        roundUp = true
                    ),
                    maxAmountString = createMaxString()
                )
            )
        }
    }

    private fun updateBalance() {
        var availableBalance: BigInteger

        when (mode) {
            Mode.STAKE -> {
                availableBalance =
                    BalanceStore.getBalances(accountId)?.get(tokenSlug) ?: BigInteger.ZERO
                shouldRenderBalanceWithSmallFee = availableBalance >= MINIMUM_REQUIRED_AMOUNT_TON
                availableBalance = if (shouldRenderBalanceWithSmallFee) {
                    availableBalance - (BigInteger.valueOf(2) * networkFee)
                } else {
                    if (token?.isBlockchainNative == true &&
                        availableBalance > networkFee
                    ) {
                        availableBalance - networkFee
                    } else {
                        availableBalance
                    }
                }
            }

            Mode.UNSTAKE -> {
                availableBalance =
                    AccountStore.stakingData?.stakingState(tokenSlug)?.balance ?: BigInteger.ZERO
            }
        }

        tokenBalance = availableBalance
    }

    fun isStake() = mode == Mode.STAKE
    fun isUnstake() = mode == Mode.UNSTAKE


    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {

            WalletEvent.StakingDataUpdated -> {
                stakingState?.annualYield?.let {
                    apy.value = it
                }
            }

            is WalletEvent.AccountChanged,
            WalletEvent.BalanceChanged,
            WalletEvent.TokensChanged,
            WalletEvent.BaseCurrencyChanged -> {
                accountId = AccountStore.activeAccountId
                updateBalance()
                currentToken =
                    TokenStore.getToken(if (mode == Mode.STAKE) tokenSlug else stakedTokenSlug)!!
                tokenPrice = TokenStore.getToken(tokenSlug)?.price
                _walletStateFlow.value = createWalletState()

                if (inputStateValue().amountInCrypto == null) return
                val inputValue = inputStateValue().run {
                    if (isInputCurrencyCrypto) {
                        CoinUtils.toDecimalString(
                            amountInCrypto!!,
                            currentToken.decimals
                        )
                    } else {
                        CoinUtils.toDecimalString(
                            amountInBaseCurrency ?: BigInteger.ZERO,
                            WalletCore.baseCurrency!!.decimalsCount
                        )
                    }
                }

                isInputListenerLocked = true
                onAmountInputChanged(inputValue) // explicit update
            }

            else -> {}
        }
    }

    override fun onCleared() {
        WalletCore.unregisterObserver(this)

        super.onCleared()
    }

}

class AddStakeViewModelFactory(
    private val tokenSlug: String,
    private val mode: StakingViewModel.Mode
) :
    ViewModelProvider.NewInstanceFactory() {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return StakingViewModel(tokenSlug, mode) as T
    }
}
