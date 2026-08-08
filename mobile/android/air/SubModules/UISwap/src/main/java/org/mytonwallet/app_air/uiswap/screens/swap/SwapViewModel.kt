@file:Suppress("ktlint:standard:backing-property-naming")

package org.mytonwallet.app_air.uiswap.screens.swap

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.math.BigDecimal
import java.math.BigInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uiswap.screens.swap.helpers.SwapHelpers
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapEstimateRequest
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapEstimateResponse
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapInputState
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapUiInputState
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapWalletState
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.DEFAULT_SWAP_VERSION
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.checkTransactionDraft
import org.mytonwallet.app_air.walletcore.api.swapBuildTransfer
import org.mytonwallet.app_air.walletcore.api.swapCexCreateTransaction
import org.mytonwallet.app_air.walletcore.api.swapCexEstimate
import org.mytonwallet.app_air.walletcore.api.swapCexSubmit
import org.mytonwallet.app_air.walletcore.api.swapGetPairs
import org.mytonwallet.app_air.walletcore.api.swapSubmit
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiTransferPayload
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitTransferOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapBuildRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexCreateTransactionRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexCreateTransactionResponse
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapHistoryItem
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapHistoryItemStatus
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapPairAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapTransactionIds
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.MDieselStatus
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ActivityStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

private const val NEAR_INTENTS_CEX_LABEL = "near-intents"

internal fun SwapInputState.clearingInvalidPair(
    preservedReceivingTokenSlug: String?
): SwapInputState = if (
    preservedReceivingTokenSlug != null &&
    tokenToReceive?.slug == preservedReceivingTokenSlug
) {
    copy(
        tokenToSend = null,
        tokenToSendMaxAmount = null,
        isFromAmountMax = false
    )
} else {
    copy(tokenToReceive = null)
}

class SwapViewModel :
    ViewModel(),
    WalletCore.EventObserver {

    /** Wallet State **/

    private val _walletStateFlow = MutableStateFlow(createWalletState())

    private fun createWalletState(): SwapWalletState? {
        val account = AccountStore.activeAccount ?: return null
        val assets = TokenStore.swapAssets ?: return null
        return SwapWalletState(
            accountId = account.accountId,
            addressByChain = account.addressByChain,
            balances = BalanceStore.getBalances(account.accountId) ?: emptyMap(),
            assets = assets
        )
    }

    /** Input State **/

    private val _inputStateFlow = MutableStateFlow(
        SwapInputState(
            tokenToSend = null,
            tokenToSendMaxAmount = null,
            tokenToReceive = null,
            amount = null,
            reverse = false,
            isFromAmountMax = false,
            slippage = 5f
        )
    )

    private data class DefaultTokensRequest(
        val sendingToken: MApiSwapAsset?,
        val receivingToken: MApiSwapAsset?
    )

    private var defaultTokensRequest: DefaultTokensRequest? = null
    private var didResolveDefaultTokens = false
    private var preservedReceivingTokenSlug: String? = null

    fun setDefaultTokens(sendingToken: MApiSwapAsset?, receivingToken: MApiSwapAsset?) {
        if (defaultTokensRequest == null) {
            defaultTokensRequest = DefaultTokensRequest(sendingToken, receivingToken)
            preservedReceivingTokenSlug = if (sendingToken == null) receivingToken?.slug else null
        }
        resolveDefaultTokensIfNeeded()
    }

    private fun resolveDefaultTokensIfNeeded() {
        if (didResolveDefaultTokens) return
        val request = defaultTokensRequest ?: return
        val wallet = _walletStateFlow.value ?: return
        val defaults = SwapHelpers.resolveDefaultTokens(
            assets = wallet.assets,
            defaultSendingToken = request.sendingToken,
            defaultReceivingToken = request.receivingToken
        )

        didResolveDefaultTokens = true
        _inputStateFlow.value = _inputStateFlow.value.copy(
            tokenToSend = defaults.tokenToSend,
            tokenToSendMaxAmount = maxAvailableAmount(defaults.tokenToSend),
            tokenToReceive = defaults.tokenToReceive,
            isFromAmountMax = false
        )
    }

    /** Tokens UI State **/

    val uiInputStateFlow: Flow<SwapUiInputState> =
        combine(_walletStateFlow, _inputStateFlow, this::buildUiInputStateFlow).filterNotNull()

    private fun buildUiInputStateFlow(
        walletOpt: SwapWalletState?,
        input: SwapInputState
    ): SwapUiInputState? {
        val wallet = walletOpt ?: return null
        return SwapUiInputState(wallet = wallet, input = input)
    }

    private val tokenPairsLoading = mutableSetOf<String>()
    private val tokenPairsCache = mutableMapOf<String, List<MApiSwapPairAsset>>()

    private suspend fun loadPairsIfNeeded(slug: String) {
        if (tokenPairsCache.contains(slug)) return
        if (!tokenPairsLoading.add(slug)) return

        try {
            val pairs = swapGetPairs(slug)

            tokenPairsCache[slug] = pairs.filter { it.slug != slug }
            validatePair()

            if (_loadingStatusFlow.value.needOpenSelectorAfterPairsLoading) {
                openTokenToReceiveSelector()
            }
        } catch (_: JSWebViewBridge.ApiError) {
        } finally {
            tokenPairsLoading.remove(slug)
        }
    }

    private fun maxAvailableAmount(token: IApiToken?): String? {
        val token = token ?: return null
        _walletStateFlow.value?.balances?.get(token.slug).let { available ->
            return available?.toString(
                decimals = token.decimals,
                currency = token.symbol ?: "",
                currencyDecimals = available.smartDecimalsCount(token.decimals),
                showPositiveSign = false,
                roundUp = false
            )
        }
    }

    fun isReverse() = _inputStateFlow.value.reverse

    fun openTokenToSendSelector() {
        cancelScheduledSelectorOpen()

        _walletStateFlow.value?.assets?.let {
            _eventsFlow.tryEmit(Event.ShowSelector(it, mode = Mode.SEND))
        }
    }

    fun openTokenToReceiveSelector() {
        cancelScheduledSelectorOpen()

        val state = _inputStateFlow.value
        val pairs = tokenPairsCache[state.tokenToSend?.slug]

        if (state.tokenToSend == null || _inputStateFlow.value.shouldShowAllPairsToBuy) {
            _walletStateFlow.value?.assets?.let {
                _eventsFlow.tryEmit(Event.ShowSelector(it, mode = Mode.RECEIVE))
            }
        } else if (pairs != null) {
            _walletStateFlow.value?.assetsMap?.let { assets ->
                _eventsFlow.tryEmit(
                    Event.ShowSelector(
                        pairs.mapNotNull { assets[it.slug] },
                        mode = Mode.RECEIVE
                    )
                )
            }
        } else {
            _loadingStatusFlow.value = _loadingStatusFlow.value.copy(
                needOpenSelectorAfterPairsLoading = true
            )
        }
    }

    fun openSwapConfirmation(addressToReceive: String?) {
        val estimated = _simulatedSwapFlow.value ?: return

        if (!estimated.request.tokenToReceiveIsSupported && addressToReceive.isNullOrEmpty()) {
            _eventsFlow.tryEmit(Event.ShowAddressToReceiveInput(estimated))
            return
        }

        _eventsFlow.tryEmit(
            Event.ShowConfirm(
                request = estimated,
                addressToReceive = addressToReceive
            )
        )
    }

    private fun calcSwapMaxBalance(fallbackToMax: Boolean = false): BigInteger =
        SwapHelpers.calcSwapMaxBalance(
            _inputStateFlow.value.tokenToSend,
            _inputStateFlow.value.tokenToReceive,
            _walletStateFlow.value?.addressByChain,
            _walletStateFlow.value?.balances,
            _simulatedSwapFlow.value,
            fallbackToMax
        )

    val tokenToSendMaxAmount: String?
        get() {
            return _inputStateFlow.value.tokenToSendMaxAmount
        }

    val tokenToReceive: IApiToken?
        get() {
            return _inputStateFlow.value.tokenToReceive
        }

    fun tokenToSendSetMaxAmount() {
        cancelScheduledSelectorOpen()

        val token = _inputStateFlow.value.tokenToSend ?: return
        val available = calcSwapMaxBalance(fallbackToMax = true)
        _inputStateFlow.value = _inputStateFlow.value.copy(
            tokenToSendMaxAmount = available.toString(
                decimals = token.decimals,
                currency = token.symbol ?: "",
                currencyDecimals = available.smartDecimalsCount(token.decimals),
                showPositiveSign = false,
                roundUp = false
            ),
            amount = CoinUtils.toDecimalString(available, token.decimals),
            reverse = false,
            isFromAmountMax = true
        )
    }

    fun onTokenToSendAmountInput(amount: CharSequence?) {
        cancelScheduledSelectorOpen()

        val state = _inputStateFlow.value
        _inputStateFlow.value = state.copy(
            amount = amount?.toString(),
            reverse = false,
            isFromAmountMax = false
        )
    }

    fun onTokenToReceiveAmountInput(amount: CharSequence?) {
        cancelScheduledSelectorOpen()

        val state = _inputStateFlow.value
        _inputStateFlow.value = state.copy(
            amount = amount?.toString(),
            reverse = true,
            isFromAmountMax = false
        )
    }

    fun setTokenToSend(asset: IApiToken) {
        cancelScheduledSelectorOpen()

        val state = _inputStateFlow.value
        val keepReverse = state.reverse && (asset.mBlockchain?.canSwapByBuyAmount ?: false)
        val amount = if (state.reverse && !keepReverse) {
            val currentKey = buildUiInputStateFlow(_walletStateFlow.value, state)?.key
            _simulatedSwapFlow.value
                ?.takeIf { it.request.key == currentKey }
                ?.fromAmountDecimalStr
        } else {
            state.amount
        }
        if (asset.slug != state.tokenToReceive?.slug) {
            _inputStateFlow.value = state.copy(
                tokenToSend = asset,
                tokenToSendMaxAmount = maxAvailableAmount(asset),
                amount = amount,
                reverse = keepReverse,
                isFromAmountMax = false
            )
            validatePair()
        } else {
            _inputStateFlow.value = state.copy(
                tokenToSend = asset,
                tokenToSendMaxAmount = maxAvailableAmount(asset),
                tokenToReceive = state.tokenToSend,
                amount = amount,
                reverse = keepReverse,
                isFromAmountMax = false
            )
        }
    }

    fun setSlippage(slippage: Float) {
        _inputStateFlow.value = _inputStateFlow.value.copy(slippage = slippage)
    }

    private fun validatePair() {
        val state = _inputStateFlow.value
        if (state.shouldShowAllPairs) return
        val pairs = tokenPairsCache[state.tokenToSend?.slug]
        if (pairs != null && state.tokenToReceive != null) {
            if (pairs.find { it.slug == state.tokenToReceive.slug } == null) {
                _inputStateFlow.value = state.clearingInvalidPair(preservedReceivingTokenSlug)
                _eventsFlow.tryEmit(Event.ClearEstimateLayout)
            }
        }
    }

    fun setTokenToReceive(asset: IApiToken?) {
        cancelScheduledSelectorOpen()

        _inputStateFlow.value = _inputStateFlow.value.copy(tokenToReceive = asset)
    }

    fun setAmount(amount: Double) {
        _inputStateFlow.value = _inputStateFlow.value.copy(
            amount = BigDecimal(amount).toPlainString(),
            reverse = false
        )
    }

    fun swapTokens() {
        cancelScheduledSelectorOpen()

        val state = _inputStateFlow.value
        val newAmount =
            if (state.isCex) {
                getLastResponse()?.cex?.toAmount?.let {
                    if (it > BigDecimal.ZERO) it.toPlainString() else null
                }
            } else {
                state.amount
            }
        // After swapping, the new sell token is the previous tokenToReceive; only enable
        // reverse (buy-amount) mode if that chain can be estimated from the buy amount.
        val newReverse = !state.isCex && !state.reverse &&
            (state.tokenToReceive?.mBlockchain?.canSwapByBuyAmount ?: false)
        _inputStateFlow.value = state.copy(
            tokenToSend = state.tokenToReceive,
            tokenToSendMaxAmount = maxAvailableAmount(state.tokenToReceive),
            tokenToReceive = state.tokenToSend,
            amount = newAmount,
            reverse = newReverse,
            isFromAmountMax = false
        )
    }

    fun getLastResponse(): SwapEstimateResponse? = _simulatedSwapFlow.value

    val shouldAuthorizeDiesel: Boolean
        get() {
            _simulatedSwapFlow.value?.let {
                return it.request.isDiesel && it.dex?.dieselStatus == MDieselStatus.NOT_AUTHORIZED
            }
            return false
        }

    /** Swap Estimate **/

    private companion object {
        private const val TIME_LIMIT = 1000L
        private const val DELAY_NORMAL = 5000L
        private const val DELAY_ERROR = 1000L
    }

    fun doSend(enclaveToken: String, response: SwapEstimateResponse, addressToReceive: String?) {
        viewModelScope.launch {
            callSubmit(enclaveToken, response, addressToReceive)
        }
    }

    private var lastSimulationTime: Long = 0L
    private var subscriptionScope: CoroutineScope? = null

    private val _simulatedSwapFlow = MutableStateFlow<SwapEstimateResponse?>(null)
    val simulatedSwapFlow = _simulatedSwapFlow.asStateFlow()

    private fun subscribe(state: SwapUiInputState) {
        unsubscribe()
        val tokenToSend = state.tokenToSend
        val tokenToReceive = state.tokenToReceive
        val amount = state.amount
        if (tokenToSend != null && tokenToReceive != null && amount != null) {
            val scope = CoroutineScope(Dispatchers.IO)
            subscriptionScope = scope
            scope.launch {
                val currentTime = System.currentTimeMillis()
                val timeSinceLastSimulation = currentTime - lastSimulationTime
                if (timeSinceLastSimulation < TIME_LIMIT) {
                    delay(TIME_LIMIT - timeSinceLastSimulation)
                }
                while (isActive) {
                    lastSimulationTime = System.currentTimeMillis()

                    try {
                        val request = SwapEstimateRequest.create(
                            key = state.key,
                            tokenToSend = tokenToSend,
                            nativeTokenToSend = state.nativeTokenToSend,
                            nativeTokenToSendBalance = CoinUtils.toDecimalString(
                                state.nativeTokenToSendBalance,
                                state.nativeTokenToSend?.decimals ?: 0
                            ),
                            tokenToReceive = tokenToReceive,
                            wallet = state.wallet,
                            amount = if (state.isFromAmountMax) {
                                if (state.isCex) {
                                    calcSwapMaxBalance(true)
                                } else {
                                    // Send balance, the api will take care of the fee and return correct result
                                    _walletStateFlow.value?.balances?.get(
                                        state.tokenToSend.slug
                                    ) ?: BigInteger.ZERO
                                }
                            } else {
                                amount
                            },
                            reverse = state.reverse,
                            slippage = state.slippage,
                            isFromAmountMax = state.isFromAmountMax,
                            prevEst = _simulatedSwapFlow.value
                        ) ?: run {
                            Logger.e(
                                Logger.LogTag.SWAP,
                                "Estimate skipped: token metadata is incomplete " +
                                    "from=${tokenToSend.slug} to=${tokenToReceive.slug}"
                            )
                            _simulatedSwapFlow.value = null
                            return@launch
                        }

                        val response = callEstimate(request)
                        val wasApplied = withContext(Dispatchers.Main.immediate) {
                            val currentState = buildUiInputStateFlow(
                                _walletStateFlow.value,
                                _inputStateFlow.value
                            )
                            if (!isActive ||
                                subscriptionScope !== scope ||
                                currentState?.wallet?.accountId != request.wallet.accountId ||
                                currentState.key != request.key
                            ) {
                                return@withContext false
                            }

                            _simulatedSwapFlow.value = response
                            val available = calcSwapMaxBalance(fallbackToMax = true)
                            _inputStateFlow.value = _inputStateFlow.value.copy(
                                tokenToSendMaxAmount = available.toString(
                                    decimals = request.tokenToSend.decimals,
                                    currency = request.tokenToSend.symbol ?: "",
                                    currencyDecimals = available.smartDecimalsCount(
                                        request.tokenToSend.decimals
                                    ),
                                    showPositiveSign = false,
                                    roundUp = false
                                )
                            )
                            val inputAmount = CoinUtils.fromDecimal(
                                _inputStateFlow.value.amount,
                                request.tokenToSend.decimals
                            )
                            if (_inputStateFlow.value.isFromAmountMax && inputAmount != available) {
                                tokenToSendSetMaxAmount()
                            }

                            true
                        }
                        if (!wasApplied) return@launch

                        if (response.error != null) {
                            delay(DELAY_ERROR)
                        } else {
                            delay(DELAY_NORMAL)
                        }
                        continue
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        Logger.e(
                            Logger.LogTag.SWAP,
                            "Estimate loop failed from=${tokenToSend.slug} " +
                                "to=${tokenToReceive.slug} error=${e.javaClass.simpleName}"
                        )
                        if (isActive && _simulatedSwapFlow.value?.request?.key != state.key) {
                            _simulatedSwapFlow.value = null
                        }
                    }
                    delay(DELAY_ERROR)
                }
            }
        } else {
            _simulatedSwapFlow.value = null
        }
    }

    private fun unsubscribe() {
        subscriptionScope?.cancel()
        subscriptionScope = null
    }

    /** Loading **/

    data class LoadingState(val needOpenSelectorAfterPairsLoading: Boolean = false)

    private val _loadingStatusFlow = MutableStateFlow(LoadingState())

    private fun cancelScheduledSelectorOpen() {
        if (_loadingStatusFlow.value.needOpenSelectorAfterPairsLoading) {
            _loadingStatusFlow.value = _loadingStatusFlow.value.copy(
                needOpenSelectorAfterPairsLoading = false
            )
        }
    }

    /** Events **/

    private val _eventsFlow =
        MutableSharedFlow<Event>(replay = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val eventsFlow = _eventsFlow.asSharedFlow()

    enum class Mode { SEND, RECEIVE }

    sealed class Event {
        data class ShowSelector(val assets: List<MApiSwapAsset>, val mode: Mode) : Event()

        data class ShowConfirm(val request: SwapEstimateResponse, val addressToReceive: String?) :
            Event()

        data class ShowAddressToReceiveInput(val request: SwapEstimateResponse) : Event()

        data class ShowAddressToSend(
            val estimate: SwapEstimateResponse,
            val response: MApiSwapCexCreateTransactionResponse,
            val cex: MApiSwapHistoryItem.Cex
        ) : Event()

        data class SwapComplete(
            val success: Boolean,
            val activity: MApiTransaction? = null,
            val error: MBridgeError? = null,
            val isOnchain: Boolean = false
        ) : Event()

        data class MfaRequested(
            val requestHash: String,
            val swapId: String?,
            val estimate: SwapEstimateResponse
        ) : Event()

        data object ClearEstimateLayout : Event()
    }

    /** UI Status **/

    data class UiStatus(
        val tokenToSend: FieldState,
        val tokenToReceive: FieldState,
        val button: ButtonState
    )

    data class FieldState(val isError: Boolean = false, val isLoading: Boolean = false)

    enum class ButtonStatus {
        WaitAmount,
        WaitToken,
        WaitNetwork,

        Loading,
        Error,

        LessThanMinCex,
        MoreThanMaxCex,
        AuthorizeDiesel,
        PendingPreviousDiesel,

        NotEnoughNativeToken,
        NotEnoughToken,

        Ready;

        val isEnabled: Boolean
            get() = this == Ready || this == AuthorizeDiesel

        val isLoading: Boolean
            get() = this == Loading

        val isError: Boolean
            get() = this == Error
    }

    data class ButtonState(val status: ButtonStatus, val title: String = "")

    val uiStatusFlow: Flow<UiStatus> =
        combine(uiInputStateFlow, simulatedSwapFlow, _loadingStatusFlow, this::getUiState)

    private fun getUiState(
        assets: SwapUiInputState,
        est: SwapEstimateResponse?,
        loading: LoadingState
    ): UiStatus {
        val buttonState = getButtonState(assets, est, loading)
        val sendAmountError = (!assets.amountInput.isNullOrEmpty() && assets.amount == null) ||
            buttonState.status == ButtonStatus.NotEnoughToken ||
            buttonState.status == ButtonStatus.LessThanMinCex ||
            buttonState.status == ButtonStatus.MoreThanMaxCex

        val inputState = FieldState(
            isError = sendAmountError && !assets.reverse,
            isLoading = false
        )

        val outputState = FieldState(
            isLoading = (est?.let { it.request.key != assets.key } ?: true),
            isError = sendAmountError && assets.reverse
        )

        return UiStatus(
            button = buttonState,
            tokenToSend = if (!assets.reverse) inputState else outputState,
            tokenToReceive = if (assets.reverse) inputState else outputState
        )
    }

    private fun getButtonState(
        state: SwapUiInputState,
        est: SwapEstimateResponse?,
        loading: LoadingState
    ): ButtonState {
        if (loading.needOpenSelectorAfterPairsLoading) {
            return ButtonState(ButtonStatus.Loading)
        }

        val tokenToSend = state.tokenToSend ?: return ButtonState(
            ButtonStatus.WaitToken,
            LocaleController.getString("Select Token")
        )

        val tokenToReceive = state.tokenToReceive ?: return ButtonState(
            ButtonStatus.WaitToken,
            LocaleController.getString("Select Token")
        )

        val inputAmount = state.amount ?: return ButtonState(
            ButtonStatus.WaitAmount,
            LocaleController.getString("Enter Amount")
        )

        if (inputAmount == BigInteger.ZERO) {
            return ButtonState(
                ButtonStatus.WaitAmount,
                LocaleController.getString("Enter Amount")
            )
        }

        val estimated = est ?: run {
            return if (WalletCore.isConnected()) {
                ButtonState(ButtonStatus.Loading)
            } else {
                ButtonState(
                    ButtonStatus.WaitNetwork,
                    LocaleController.getString("Waiting for Network")
                )
            }
        }
        if (estimated.request.key != state.key) {
            return ButtonState(ButtonStatus.Loading)
        }

        val sendAmount = estimated.fromAmount ?: BigInteger.ZERO
        if (estimated.fromAmountMin != null && sendAmount < estimated.fromAmountMin) {
            return ButtonState(
                ButtonStatus.LessThanMinCex,
                LocaleController.getString("\$min_value").replace(
                    "%value%",
                    estimated.fromAmountMin.toString(
                        decimals = tokenToSend.decimals,
                        currency = tokenToSend.symbol ?: "",
                        currencyDecimals = tokenToSend.decimals,
                        showPositiveSign = false
                    )
                )
            )
        }

        estimated.fromAmountMax?.let { maxAmount ->
            if (sendAmount > maxAmount) {
                return ButtonState(
                    ButtonStatus.MoreThanMaxCex,
                    LocaleController.getFormattedString(
                        "Max %1$@",
                        listOf(
                            maxAmount.toString(
                                decimals = tokenToSend.decimals,
                                currency = tokenToSend.symbol ?: "",
                                currencyDecimals = tokenToSend.decimals,
                                showPositiveSign = false
                            )
                        )
                    )
                )
            }
        }

        estimated.error?.let {
            when (it) {
                MBridgeError.Type.AXIOS_ERROR -> return ButtonState(
                    ButtonStatus.WaitNetwork,
                    LocaleController.getString("Waiting for Network")
                )

                else -> return ButtonState(
                    ButtonStatus.Error,
                    when (it) {
                        MBridgeError.Type.INSUFFICIENT_BALANCE -> {
                            val walletBalance =
                                (
                                    est.request.wallet.balances[est.request.tokenToSend.slug]
                                        ?: BigInteger.ZERO
                                    )
                            val requestAmount = estimated.fromAmount ?: estimated.request.amount
                            if (walletBalance >= requestAmount && state.tokenToSendIsSupported) {
                                state.nativeTokenToSend?.symbol?.let { symbol ->
                                    LocaleController.getFormattedString(
                                        "Insufficient %1$@ Balance",
                                        listOf(symbol)
                                    )
                                }
                                    ?: LocaleController.getString("Insufficient Balance")
                            } else {
                                LocaleController.getString("Insufficient Balance")
                            }
                        }

                        MBridgeError.Type.TOO_SMALL_AMOUNT,
                        MBridgeError.Type.PAIR_NOT_FOUND,
                        MBridgeError.Type.SLIPPAGE_ERROR -> it.toShortLocalized ?: ""

                        else -> LocaleController.getString("Error")
                    }
                )
            }
        }

        if (sendAmount > calcSwapMaxBalance() && state.tokenToSendIsSupported) {
            return ButtonState(
                ButtonStatus.NotEnoughToken,
                LocaleController.getString("Insufficient Balance")
            )
        }

        val nativeFee = estimated.fee ?: BigInteger.ZERO
        if (nativeFee > state.nativeTokenToSendBalance && state.tokenToSendIsSupported) {
            if (estimated.request.isDiesel) {
                if (shouldAuthorizeDiesel) {
                    return ButtonState(
                        ButtonStatus.AuthorizeDiesel,
                        LocaleController.getFormattedString(
                            "Authorize %1$@ fee",
                            listOf(tokenToSend.symbol ?: "")
                        )
                    )
                }
                if (_simulatedSwapFlow.value?.dex?.dieselStatus == MDieselStatus.PENDING_PREVIOUS) {
                    return ButtonState(
                        ButtonStatus.PendingPreviousDiesel,
                        LocaleController.getString("Pending previous fee")
                    )
                }
                if (calcSwapMaxBalance(fallbackToMax = false) == BigInteger.ZERO) {
                    // Insufficient Balance in gasless mode
                    return ButtonState(
                        ButtonStatus.NotEnoughNativeToken,
                        LocaleController.getString("Insufficient Balance")
                    )
                }
            } else {
                return ButtonState(
                    ButtonStatus.NotEnoughNativeToken,
                    state.nativeTokenToSend?.symbol?.let {
                        LocaleController.getFormattedString(
                            "Insufficient %1$@ Balance",
                            listOf(it)
                        )
                    } ?: LocaleController.getString("Insufficient Balance")
                )
            }
        }

        return ButtonState(
            ButtonStatus.Ready,
            LocaleController.getFormattedString(
                "Swap %1$@ to %2$@",
                listOf(tokenToSend.symbol ?: "", tokenToReceive.symbol ?: "")
            )
        )
    }

    /** API **/

    private var lastLoggedEstimateError: String? = null

    private suspend fun callEstimate(request: SwapEstimateRequest): SwapEstimateResponse {
        try {
            if (request.isCex) {
                var firstTransactionFee: BigInteger?
                val needEstFee = request.wallet.isSupportedChain(request.tokenToSend.mBlockchain)

                if (needEstFee) { // Must call even when balance is 0 for proper fee estimation
                    val estFeeAddress = request.tokenToSend.mBlockchain?.feeCheckAddress
                        ?: throw NotImplementedError()

                    val estAmount =
                        if (request.tokenToSend.isBlockchainNative &&
                            request.amount > BigInteger.ZERO
                        ) {
                            request.amount
                        } else {
                            BigInteger.ONE
                        }
                    try {
                        firstTransactionFee = WalletCore.Transfer.checkTransactionDraft(
                            request.tokenToSendChain,
                            MApiCheckTransactionDraftOptions(
                                accountId = request.wallet.accountId,
                                toAddress = estFeeAddress,
                                amount = estAmount,
                                stateInit = null,
                                tokenAddress = if (!request.tokenToSend.isBlockchainNative) {
                                    request.tokenToSend.tokenAddress
                                } else {
                                    null
                                },
                                payload = null,
                                allowGasless = null
                            )
                        ).fullNativeFee
                    } catch (apiError: JSWebViewBridge.ApiError) {
                        // TODO: Restore the strict handling below once all chains have a correct
                        //  feeCheckAddress and the SDK no longer throws on fee-estimation draft checks.
                        /*if (apiError.parsed == MBridgeError.Type.INSUFFICIENT_BALANCE &&
                            apiError.parsedResult is MApiCheckTransactionDraftResult
                        ) {
                            firstTransactionFee =
                                (apiError.parsedResult as? MApiCheckTransactionDraftResult)
                                    ?.fullNativeFee ?: BigInteger.ZERO
                        } else {
                            throw apiError
                        }*/
                        firstTransactionFee =
                            (apiError.parsedResult as? MApiCheckTransactionDraftResult)
                                ?.fullNativeFee
                    }
                } else {
                    firstTransactionFee = null
                }

                val cex = WalletCore.Swap.swapCexEstimate(
                    request.wallet.accountId,
                    request.estimateRequestCex
                )
                if (cex.route != null && cex.route != "cex") {
                    return SwapEstimateResponse(
                        request = request,
                        dex = null,
                        cex = null,
                        fee = null,
                        error = MBridgeError.Type.UNKNOWN
                    )
                }
                cex.error?.let {
                    return SwapEstimateResponse(
                        request = request,
                        dex = null,
                        cex = null,
                        fee = null,
                        error = it
                    )
                }
                val res = SwapEstimateResponse(
                    request = request,
                    dex = null,
                    cex = cex,
                    fee = firstTransactionFee,
                    error = null
                )
                return res
            } else {
                val dex = WalletCore.call(
                    ApiMethod.Swap.SwapEstimate(
                        request.wallet.accountId,
                        request.estimateRequestDex
                    )
                )
                val fee = dex.networkFee.toBigInteger(request.nativeTokenToSend.decimals)
                return SwapEstimateResponse(
                    request = request,
                    dex = dex,
                    cex = null,
                    fee = fee,
                    error = null
                )
            }
        } catch (apiError: JSWebViewBridge.ApiError) {
            if (apiError.parsed.type == MBridgeError.Type.UNKNOWN &&
                apiError.message != lastLoggedEstimateError
            ) {
                lastLoggedEstimateError = apiError.message
                Logger.e(Logger.LogTag.SWAP, "Estimate failed: ${apiError.message}")
            }
            return SwapEstimateResponse(
                request = request,
                dex = null,
                cex = null,
                fee = null,
                error = apiError.parsed
            )
        }
    }

    private var swappedEstimateConfig: SwapEstimateResponse? = null

    private var awaitingActivity = false
    private var receivedActivity: MApiTransaction? = null
    private var previousPendingActivities: List<String>? = null
    private suspend fun callSubmit(
        enclaveToken: String,
        estimate: SwapEstimateResponse,
        addressToReceive: String?
    ) {
        val accountId = estimate.request.wallet.accountId
        val accountTonAddress = estimate.request.wallet.tonAddress ?: run {
            failUnexpectedSubmission("missing TON history address")
            return
        }
        val tokenToSend = estimate.request.tokenToSend
        val tokenToReceive = estimate.request.tokenToReceive

        awaitingActivity = false
        receivedActivity = null
        previousPendingActivities =
            ActivityStore.getLocalAndPendingActivities(accountId, null)?.map { it.id }
        try {
            estimate.dex?.let { dex ->
                val fromAddress = tokenToSend.mBlockchain?.name?.let {
                    estimate.request.wallet.addressByChain[it]
                } ?: accountTonAddress
                val build = WalletCore.Swap.swapBuildTransfer(
                    accountId,
                    enclaveToken,
                    MApiSwapBuildRequest(
                        dexLabel = dex.dexLabel?.name?.lowercase(),
                        from = dex.from,
                        fromAddress = fromAddress,
                        historyAddress = accountTonAddress,
                        fromAmount = dex.fromAmount,
                        networkFee = dex.realNetworkFee ?: dex.networkFee,
                        shouldTryDiesel = estimate.request.shouldTryDiesel,
                        slippage = estimate.request.slippage,
                        swapFee = dex.swapFee,
                        to = dex.to,
                        toAmount = dex.toAmount,
                        toMinAmount = dex.toMinAmount,
                        ourFee = dex.ourFee,
                        dexRouterLabel = dex.dexRouterLabel,
                        dieselFee = dex.dieselFee,
                        swapVersion = ConfigStore.swapVersion ?: DEFAULT_SWAP_VERSION,
                        routes = dex.routes
                    )
                )
                val buildId = build.id
                val buildChain = build.chain
                if (build.error != null ||
                    buildId == null ||
                    buildChain == null ||
                    (build.transfers == null && build.transaction == null)
                ) {
                    swappedEstimateConfig = null
                    _eventsFlow.tryEmit(
                        Event.SwapComplete(
                            success = false,
                            error =
                                MBridgeError.Type.entries.firstOrNull {
                                    it.errorName == build.error
                                }
                                    ?: MBridgeError.Type.UNKNOWN
                        )
                    )
                    return
                }

                swappedEstimateConfig = estimate
                val submitResult = WalletCore.Swap.swapSubmit(
                    buildChain,
                    accountId,
                    enclaveToken,
                    build.transfers,
                    MApiSwapHistoryItem(
                        id = buildId,
                        timestamp = System.currentTimeMillis(),
                        lt = null,
                        from = dex.from,
                        fromAddress = fromAddress,
                        fromAmount = dex.fromAmount,
                        to = dex.to,
                        toAmount = dex.toAmount,
                        networkFee = dex.networkFee,
                        swapFee = dex.swapFee,
                        status = MApiSwapHistoryItemStatus.PENDING,
                        transactionIds = MApiSwapTransactionIds(),
                        isCanceled = null,
                        cex = null
                    ),
                    estimate.request.isDiesel,
                    build.transaction
                )
                submitResult.mfaRequestHash?.let { hash ->
                    _eventsFlow.tryEmit(
                        Event.MfaRequested(hash, submitResult.swapId, estimate)
                    )
                } ?: run {
                    if (receivedActivity != null) {
                        _eventsFlow.tryEmit(
                            Event.SwapComplete(
                                success = true,
                                activity = receivedActivity,
                                isOnchain = true
                            )
                        )
                    } else {
                        awaitingActivity = true
                    }
                }
            }

            estimate.cex?.let { cex ->
                cex.error?.let {
                    _eventsFlow.tryEmit(Event.SwapComplete(success = false, error = it))
                    return
                }
                val toUserAddress =
                    estimate.request.wallet.addressByChain[tokenToReceive.mBlockchain?.name]
                        ?: addressToReceive
                        ?: run {
                            failUnexpectedSubmission("missing destination address")
                            return
                        }
                val fromAmount = cex.fromAmount ?: run {
                    failUnexpectedSubmission("missing CEX source amount")
                    return
                }
                val swapFee = cex.swapFee ?: run {
                    failUnexpectedSubmission("missing CEX swap fee")
                    return
                }

                // networkFee is only for the sent TON
                val networkFee = if (tokenToSend.mBlockchain == MBlockchain.ton) {
                    estimate.fee?.toBigDecimal(9)?.toDouble() ?: 0.0
                } else {
                    0.0
                }
                val cexLabel = cex.cexLabel
                val isNearIntents = cexLabel == NEAR_INTENTS_CEX_LABEL
                val historyAddress = accountTonAddress
                val sourceAddress = if (isNearIntents) {
                    estimate.request.wallet.addressByChain[tokenToSend.mBlockchain?.name]
                        ?: run {
                            failUnexpectedSubmission("missing source-chain refund address")
                            return
                        }
                } else {
                    accountTonAddress
                }

                swappedEstimateConfig = estimate
                val result = WalletCore.Swap.swapCexCreateTransaction(
                    accountId,
                    enclaveToken,
                    MApiSwapCexCreateTransactionRequest(
                        from = tokenToSend.swapSlug,
                        fromAmount = fromAmount,
                        fromAddress = sourceAddress,
                        historyAddress = historyAddress,
                        cexLabel = cexLabel,
                        to = tokenToReceive.swapSlug,
                        toAmount = cex.toAmount,
                        toAddress = toUserAddress,
                        payoutExtraId = null,
                        swapFee = swapFee,
                        networkFee = networkFee
                    )
                )
                val createdCex = result.swap.cex ?: run {
                    failUnexpectedSubmission("missing CEX transaction details")
                    return
                }

                if (estimate.request.tokenToSendIsSupported) {
                    val depositMemo = createdCex.payinExtraId?.trim()?.takeIf { it.isNotEmpty() }
                    if (isNearIntents && depositMemo != null && !canAutoSubmitDepositMemo(
                            tokenToSend.mBlockchain
                        )
                    ) {
                        awaitingActivity = false
                        swappedEstimateConfig = null
                        _eventsFlow.tryEmit(
                            Event.SwapComplete(
                                success = false,
                                error = MBridgeError.Type.UNKNOWN
                            )
                        )
                        return
                    }
                    val payload = if (isNearIntents && depositMemo != null) {
                        ApiTransferPayload.Comment(depositMemo, shouldEncrypt = false)
                    } else {
                        null
                    }
                    val cexSubmit = WalletCore.Transfer.swapCexSubmit(
                        estimate.request.tokenToSendChain,
                        MApiSubmitTransferOptions(
                            accountId = accountId,
                            enclaveToken = enclaveToken,
                            toAddress = createdCex.payinAddress,
                            amount = estimate.fromAmount ?: BigInteger.ZERO,
                            fee = estimate.fee,
                            payload = payload,
                            tokenAddress = if (!tokenToSend.isBlockchainNative) {
                                tokenToSend.tokenAddress
                            } else {
                                null
                            },
                            noFeeCheck = false,
                            isGasless = false
                        ),
                        result.swap.id
                    )
                    cexSubmit.error?.let { error ->
                        swappedEstimateConfig = null
                        _eventsFlow.tryEmit(
                            Event.SwapComplete(
                                success = false,
                                error =
                                    MBridgeError.Type.entries.firstOrNull { it.errorName == error }
                                        ?: MBridgeError.Type.UNKNOWN
                            )
                        )
                        return
                    }
                    val mfaRequestHash = cexSubmit.mfaRequestHash
                    if (mfaRequestHash != null) {
                        _eventsFlow.tryEmit(
                            Event.MfaRequested(mfaRequestHash, result.swap.id, estimate)
                        )
                    } else if (receivedActivity != null) {
                        _eventsFlow.tryEmit(
                            Event.SwapComplete(
                                success = true,
                                activity = receivedActivity,
                                isOnchain = false
                            )
                        )
                    } else {
                        awaitingActivity = true
                    }
                } else {
                    _eventsFlow.tryEmit(
                        Event.ShowAddressToSend(
                            estimate = estimate,
                            response = result,
                            cex = createdCex
                        )
                    )
                }
            }
        } catch (e: CancellationException) {
            swappedEstimateConfig = null
            throw e
        } catch (e: JSWebViewBridge.ApiError) {
            swappedEstimateConfig = null
            _eventsFlow.tryEmit(Event.SwapComplete(success = false, error = e.parsed))
        } catch (e: Exception) {
            Logger.e(
                Logger.LogTag.SWAP,
                "Submit failed type=${if (estimate.cex != null) "cex" else "dex"} error=${e.javaClass.simpleName}"
            )
            swappedEstimateConfig = null
            _eventsFlow.tryEmit(Event.SwapComplete(success = false))
        }
    }

    private fun failUnexpectedSubmission(reason: String) {
        Logger.e(Logger.LogTag.SWAP, "Submit rejected: $reason")
        swappedEstimateConfig = null
        _eventsFlow.tryEmit(Event.SwapComplete(success = false, error = MBridgeError.Type.UNKNOWN))
    }

    fun onMfaConfirmed() {
        if (receivedActivity != null) {
            _eventsFlow.tryEmit(
                Event.SwapComplete(
                    success = true,
                    activity = receivedActivity,
                    isOnchain = swappedEstimateConfig?.dex != null
                )
            )
        } else {
            awaitingActivity = true
        }
    }

    private fun checkReceivedActivity(receivedActivity: MApiTransaction) {
        val isSwapDone = receivedActivity is MApiTransaction.Swap &&
            previousPendingActivities?.contains(receivedActivity.id) != true &&
            (
                receivedActivity.from == swappedEstimateConfig?.request?.tokenToSend?.slug ||
                    receivedActivity.from ==
                    swappedEstimateConfig?.request?.tokenToSend?.tokenAddress
                ) &&
            (
                receivedActivity.to == swappedEstimateConfig?.request?.tokenToReceive?.slug ||
                    receivedActivity.to ==
                    swappedEstimateConfig?.request?.tokenToReceive?.tokenAddress
                )
        if (!isSwapDone) return
        if (awaitingActivity) {
            awaitingActivity = false
            _eventsFlow.tryEmit(
                Event.SwapComplete(
                    success = true,
                    activity = receivedActivity,
                    isOnchain = swappedEstimateConfig?.dex != null
                )
            )
        } else {
            this.receivedActivity = receivedActivity
        }
        swappedEstimateConfig = null
    }

    private fun canAutoSubmitDepositMemo(chain: MBlockchain?): Boolean =
        chain == MBlockchain.ton || chain == MBlockchain.solana

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {
                val wallet = createWalletState()
                val accountChanged = _walletStateFlow.value?.accountId != wallet?.accountId
                if (accountChanged) {
                    _simulatedSwapFlow.value = null
                    lastSimulationTime = 0L
                }
                _walletStateFlow.value = wallet
                if (accountChanged) {
                    if (_inputStateFlow.value.isFromAmountMax) {
                        tokenToSendSetMaxAmount()
                    } else {
                        _inputStateFlow.value = _inputStateFlow.value.copy(
                            tokenToSendMaxAmount = maxAvailableAmount(
                                _inputStateFlow.value.tokenToSend
                            )
                        )
                    }
                }
                resolveDefaultTokensIfNeeded()
            }

            WalletEvent.BalanceChanged -> {
                _walletStateFlow.value = createWalletState()
                resolveDefaultTokensIfNeeded()
            }

            WalletEvent.NetworkConnected,

            WalletEvent.NetworkDisconnected -> {
                val correctVal = _inputStateFlow.value
                _inputStateFlow.value = SwapInputState()
                _inputStateFlow.value = correctVal
            }

            is WalletEvent.NewLocalActivities -> {
                walletEvent.localActivities?.forEach {
                    checkReceivedActivity(it)
                }
            }

            is WalletEvent.ReceivedPendingActivities -> {
                walletEvent.pendingActivities?.forEach {
                    checkReceivedActivity(it)
                }
            }

            is WalletEvent.ReceivedNewActivities -> {
                walletEvent.newActivities?.filter { it.isPending() }?.forEach {
                    checkReceivedActivity(it)
                }
            }

            else -> {}
        }
    }

    // Init and clear.

    init {
        collectFlow(uiInputStateFlow, this::subscribe)
        collectFlow(uiInputStateFlow) {
            it.tokenToSend?.let { token -> loadPairsIfNeeded(token.slug) }
        }

        TokenStore.swapAssetsFlow.filterNotNull().onEach {
            _walletStateFlow.value = createWalletState()
            resolveDefaultTokensIfNeeded()
        }.launchIn(viewModelScope)

        WalletCore.registerObserver(this)
    }

    override fun onCleared() {
        unsubscribe()
        WalletCore.unregisterObserver(this)

        super.onCleared()
    }
}
