package org.mytonwallet.app_air.uiswap.screens.swap

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
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
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uiswap.screens.swap.helpers.SwapHelpers
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapEstimateRequest
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapEstimateResponse
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapInputState
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapUiInputState
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapWalletState
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
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
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitTransferOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapBuildRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexCreateTransactionRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexCreateTransactionResponse
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapDexLabel
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapEstimateVariant
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapHistoryItem
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapHistoryItemStatus
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapPairAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.MDieselStatus
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigDecimal
import java.math.BigInteger

const val DEFAULT_OUR_SWAP_FEE = 0.875

class SwapViewModel : ViewModel(), WalletCore.EventObserver {

    /** Wallet State **/

    private val _walletStateFlow = MutableStateFlow(createWalletState())

    private fun createWalletState(): SwapWalletState? {
        val account = AccountStore.activeAccount ?: return null
        val assets = TokenStore.swapAssets2 ?: return null
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
            slippage = 5f,
            selectedDex = null
        )
    )

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

    private fun calcSwapMaxBalance(fallbackToMax: Boolean = false): BigInteger {
        return SwapHelpers.calcSwapMaxBalance(
            _inputStateFlow.value.tokenToSend,
            _inputStateFlow.value.tokenToReceive,
            _walletStateFlow.value?.addressByChain,
            _walletStateFlow.value?.balances,
            _simulatedSwapFlow.value,
            fallbackToMax
        )
    }

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
        if (asset.slug != state.tokenToReceive?.slug) {
            _inputStateFlow.value = state.copy(
                tokenToSend = asset,
                tokenToSendMaxAmount = maxAvailableAmount(asset),
                isFromAmountMax = false
            )
            validatePair()
        } else {
            _inputStateFlow.value = state.copy(
                tokenToSend = asset,
                tokenToSendMaxAmount = maxAvailableAmount(asset),
                tokenToReceive = state.tokenToSend,
                isFromAmountMax = false
            )
        }
    }

    fun setSlippage(slippage: Float) {
        _inputStateFlow.value = _inputStateFlow.value.copy(slippage = slippage)
    }

    fun setDex(dex: MApiSwapDexLabel?) {
        _inputStateFlow.value = _inputStateFlow.value.copy(selectedDex = dex)
    }

    private fun validatePair() {
        val state = _inputStateFlow.value
        if (state.shouldShowAllPairs)
            return
        val pairs = tokenPairsCache[state.tokenToSend?.slug]
        if (pairs != null && state.tokenToReceive != null) {
            if (pairs.find { it.slug == state.tokenToReceive.slug } == null) {
                _inputStateFlow.value = state.copy(tokenToReceive = null)
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
                    if (it > BigDecimal.ZERO)
                        it.toPlainString()
                    else
                        null
                }
            } else state.amount
        _inputStateFlow.value = state.copy(
            tokenToSend = state.tokenToReceive,
            tokenToSendMaxAmount = maxAvailableAmount(state.tokenToReceive),
            tokenToReceive = state.tokenToSend,
            amount = newAmount,
            reverse = if (state.isCex) false else !state.reverse,
            isFromAmountMax = false
        )
    }

    fun getLastResponse(): SwapEstimateResponse? {
        return _simulatedSwapFlow.value
    }

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

    fun doSend(passcode: String, response: SwapEstimateResponse, addressToReceive: String?) {
        viewModelScope.launch {
            callSubmit(passcode, response, addressToReceive)
        }
    }

    private var lastSimulationTime: Long = 0L
    private var subscriptionScope: CoroutineScope? = null

    private val _simulatedSwapFlow = MutableStateFlow<SwapEstimateResponse?>(null)
    val simulatedSwapFlow = _simulatedSwapFlow.asStateFlow()

    private fun subscribe(state: SwapUiInputState) {
        unsubscribe()
        if (state.tokenToSend != null && state.tokenToReceive != null && state.amount != null) {
            subscriptionScope = CoroutineScope(Dispatchers.IO)
            subscriptionScope!!.launch {
                val currentTime = System.currentTimeMillis()
                val timeSinceLastSimulation = currentTime - lastSimulationTime
                if (timeSinceLastSimulation < TIME_LIMIT) {
                    delay(TIME_LIMIT - timeSinceLastSimulation)
                }
                while (isActive) {
                    lastSimulationTime = System.currentTimeMillis()

                    try {
                        val request = SwapEstimateRequest(
                            key = state.key,
                            tokenToSend = state.tokenToSend,
                            nativeTokenToSend = state.nativeTokenToSend!!,
                            nativeTokenToSendBalance = CoinUtils.toDecimalString(
                                _walletStateFlow.value?.balances?.get(state.nativeTokenToSend.slug)
                                    ?: BigInteger.ZERO, state.nativeTokenToSend.decimals
                            ),
                            tokenToReceive = state.tokenToReceive,
                            wallet = state.wallet,
                            amount = if (state.isFromAmountMax) {
                                if (state.isCex)
                                    calcSwapMaxBalance(true)
                                else
                                // Send balance, the api will take care of the fee and return correct result
                                    _walletStateFlow.value?.balances?.get(
                                        state.tokenToSend.slug
                                    ) ?: BigInteger.ZERO
                            } else state.amount,
                            reverse = state.reverse,
                            slippage = state.slippage,
                            isFromAmountMax = state.isFromAmountMax,
                            prevEst = _simulatedSwapFlow.value,
                            selectedDex = state.selectedDex
                        )

                        val response = callEstimate(request)
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
                            ),
                        )
                        if (_inputStateFlow.value.isFromAmountMax && response.fromAmount != available)
                            tokenToSendSetMaxAmount()

                        if (response.error != null) {
                            delay(DELAY_ERROR)
                        } else {
                            delay(DELAY_NORMAL)
                        }
                        continue
                    } catch (t: Throwable) {
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

    data class LoadingState(
        val needOpenSelectorAfterPairsLoading: Boolean = false,
    )

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
        data class ShowSelector(
            val assets: List<MApiSwapAsset>,
            val mode: Mode
        ) : Event()

        data class ShowConfirm(
            val request: SwapEstimateResponse,
            val addressToReceive: String?
        ) : Event()

        data class ShowAddressToReceiveInput(
            val request: SwapEstimateResponse
        ) : Event()

        data class ShowAddressToSend(
            val estimate: SwapEstimateResponse,
            val response: MApiSwapCexCreateTransactionResponse,
            val cex: MApiSwapHistoryItem.Cex
        ) : Event()

        data class SwapComplete(
            val success: Boolean,
            val activity: MApiTransaction? = null,
            val error: MBridgeError? = null
        ) : Event()

        data object ClearEstimateLayout : Event()
    }


    /** UI Status **/

    data class UiStatus(
        val tokenToSend: FieldState,
        val tokenToReceive: FieldState,
        val button: ButtonState
    )

    data class FieldState(
        val isError: Boolean = false,
        val isLoading: Boolean = false
    )

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

    data class ButtonState(
        val status: ButtonStatus,
        val title: String = ""
    )

    val uiStatusFlow: Flow<UiStatus> =
        combine(uiInputStateFlow, simulatedSwapFlow, _loadingStatusFlow, this::getUiState)

    private fun getUiState(
        assets: SwapUiInputState,
        est: SwapEstimateResponse?,
        loading: LoadingState
    ): UiStatus {
        val buttonState = getButtonState(assets, est, loading)
        val sendAmountError = (!assets.amountInput.isNullOrEmpty() && assets.amount == null)
            || buttonState.status == ButtonStatus.NotEnoughToken
            || buttonState.status == ButtonStatus.LessThanMinCex
            || buttonState.status == ButtonStatus.MoreThanMaxCex


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
            return if (WalletCore.isConnected())
                ButtonState(ButtonStatus.Loading)
            else
                ButtonState(
                    ButtonStatus.WaitNetwork,
                    LocaleController.getString("Waiting for Network")
                )
        }
        if (estimated.request.key != state.key) {
            return ButtonState(ButtonStatus.Loading)
        }

        val sendAmount = estimated.fromAmount ?: BigInteger.ZERO
        if (estimated.fromAmountMin != null && sendAmount < estimated.fromAmountMin) {
            return ButtonState(
                ButtonStatus.LessThanMinCex,
                LocaleController.getString("\$min_value").replace(
                    "%value%", estimated.fromAmountMin.toString(
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
                    ButtonStatus.MoreThanMaxCex, LocaleController.getFormattedString(
                        "Max %1$@", listOf(
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
                MBridgeError.AXIOS_ERROR -> return ButtonState(
                    ButtonStatus.WaitNetwork,
                    LocaleController.getString("Waiting for Network")
                )

                else -> return ButtonState(
                    ButtonStatus.Error, when (it) {
                        MBridgeError.INSUFFICIENT_BALANCE -> {
                            val walletBalance =
                                (est.request.wallet.balances[est.request.tokenToSend.slug]
                                    ?: BigInteger.ZERO)
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

                        MBridgeError.TOO_SMALL_AMOUNT,
                        MBridgeError.PAIR_NOT_FOUND -> it.toShortLocalized ?: ""

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


        val nativeSendAmount = if (tokenToSend.slug == tokenToSend.mBlockchain?.nativeSlug) {
            sendAmount
        } else {
            BigInteger.ZERO
        } + (estimated.fee ?: BigInteger.ZERO)

        if (nativeSendAmount > state.nativeTokenToSendBalance && state.tokenToSendIsSupported) {
            if (estimated.request.isDiesel) {
                if (shouldAuthorizeDiesel) {
                    return ButtonState(
                        ButtonStatus.AuthorizeDiesel, LocaleController.getFormattedString(
                            "Authorize %1$@ fee", listOf(tokenToSend.symbol ?: "")
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
                    } ?: LocaleController.getString("Insufficient Balance"))
            }
        }

        return ButtonState(
            ButtonStatus.Ready, LocaleController.getFormattedString(
                "Swap %1$@ to %2$@",
                listOf(tokenToSend.symbol ?: "", tokenToReceive.symbol ?: "")
            )
        )
    }


    /** API **/

    private suspend fun callEstimate(request: SwapEstimateRequest): SwapEstimateResponse {
        try {
            if (request.isCex) {
                var firstTransactionFee: BigInteger
                val needEstFee = request.wallet.isSupportedChain(request.tokenToSend.mBlockchain)

                if (needEstFee) { // Must call even when balance is 0 for proper fee estimation
                    val estFeeAddress = when (request.tokenToSend.mBlockchain) {
                        MBlockchain.ton -> request.wallet.tonAddress
                        else -> request.tokenToSend.mBlockchain?.feeCheckAddress ?: throw NotImplementedError()
                    }

                    val estAmount = BigInteger.ONE
                    try {
                        firstTransactionFee = WalletCore.Transfer.checkTransactionDraft(
                            request.tokenToSend.mBlockchain!!,
                            MApiCheckTransactionDraftOptions(
                                accountId = request.wallet.accountId,
                                toAddress = estFeeAddress,
                                amount = estAmount,
                                stateInit = null,
                                tokenAddress = if (!request.tokenToSend.isBlockchainNative) request.tokenToSend.tokenAddress else null,
                                payload = null,
                                allowGasless = null
                            )
                        ).fee!!
                    } catch (apiError: JSWebViewBridge.ApiError) {
                        if (apiError.parsed == MBridgeError.INSUFFICIENT_BALANCE &&
                            apiError.parsedResult is MApiCheckTransactionDraftResult
                        ) {
                            firstTransactionFee =
                                (apiError.parsedResult!! as MApiCheckTransactionDraftResult).fee
                                    ?: BigInteger.ZERO
                        } else {
                            throw apiError
                        }
                    }
                } else {
                    firstTransactionFee = BigInteger.ZERO
                }

                val cex = WalletCore.Swap.swapCexEstimate(request.estimateRequestCex)
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
                var dex = WalletCore.call(
                    ApiMethod.Swap.SwapEstimate(
                        request.wallet.accountId,
                        request.estimateRequestDex,
                    )
                )
                val fee = dex.networkFee.toBigInteger(request.nativeTokenToSend.decimals)
                val all = ArrayList(dex.other ?: emptyList())
                all.add(
                    MApiSwapEstimateVariant(
                        fromAmount = dex.fromAmount,
                        toAmount = dex.toAmount,
                        toMinAmount = dex.toMinAmount,
                        swapFee = dex.swapFee,
                        networkFee = dex.networkFee,
                        realNetworkFee = dex.realNetworkFee,
                        impact = dex.impact,
                        dexLabel = dex.dexLabel
                    )
                )
                val requestedDex = all.find { it.dexLabel == request.selectedDex }
                if (requestedDex != null) {
                    dex = dex.copy(
                        fromAmount = requestedDex.fromAmount,
                        toAmount = requestedDex.toAmount,
                        toMinAmount = requestedDex.toMinAmount,
                        swapFee = requestedDex.swapFee,
                        networkFee = requestedDex.networkFee,
                        realNetworkFee = requestedDex.realNetworkFee,
                        impact = requestedDex.impact,
                        dexLabel = request.selectedDex,
                        bestDexLabel = dex.dexLabel,
                        all = all
                    )
                } else {
                    dex = dex.copy(
                        all = all
                    )
                }
                return SwapEstimateResponse(
                    request = request,
                    dex = dex,
                    cex = null,
                    fee = fee,
                    error = null
                )
            }
        } catch (apiError: JSWebViewBridge.ApiError) {
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
    private suspend fun callSubmit(
        passcode: String,
        estimate: SwapEstimateResponse,
        addressToReceive: String?
    ) {
        val accountId = estimate.request.wallet.accountId
        val accountTonAddress = estimate.request.wallet.tonAddress
        val tokenToSend = estimate.request.tokenToSend
        val tokenToReceive = estimate.request.tokenToReceive

        try {
            estimate.dex?.let { dex ->
                val build = WalletCore.Swap.swapBuildTransfer(
                    accountId,
                    passcode,
                    MApiSwapBuildRequest(
                        dexLabel = estimate.request.selectedDex?.name
                            ?: dex.dexLabel?.name?.lowercase(),
                        from = dex.from,
                        fromAddress = accountTonAddress,
                        fromAmount = dex.fromAmount,
                        networkFee = dex.realNetworkFee ?: dex.networkFee,
                        shouldTryDiesel = estimate.request.shouldTryDiesel,
                        slippage = estimate.request.slippage,
                        swapFee = dex.swapFee,
                        to = dex.to,
                        toAmount = dex.toAmount,
                        toMinAmount = dex.toMinAmount,
                        ourFee = dex.ourFee,
                        dieselFee = dex.dieselFee,
                        swapVersion = ConfigStore.swapVersion ?: DEFAULT_SWAP_VERSION,
                        routes = dex.routes
                    )
                )

                swappedEstimateConfig = estimate
                WalletCore.Swap.swapSubmit(
                    accountId,
                    passcode,
                    build.transfers,
                    MApiSwapHistoryItem(
                        id = build.id,
                        timestamp = System.currentTimeMillis(),
                        lt = null,
                        from = dex.from,
                        fromAmount = dex.fromAmount,
                        to = dex.to,
                        toAmount = dex.toAmount,
                        networkFee = dex.networkFee,
                        swapFee = dex.swapFee,
                        status = MApiSwapHistoryItemStatus.PENDING,
                        txIds = emptyList(),
                        isCanceled = null,
                        cex = null
                    ),
                    estimate.request.isDiesel
                )
            }

            estimate.cex?.let { cex ->
                cex.error?.let {
                    _eventsFlow.tryEmit(Event.SwapComplete(success = false, error = it))
                    return
                }
                val toUserAddress =
                    estimate.request.wallet.addressByChain[tokenToReceive.mBlockchain?.name]
                        ?: addressToReceive
                        ?: throw NullPointerException("user address is null")

                // networkFee is only for the sent TON
                val networkFee = if (tokenToSend.mBlockchain == MBlockchain.ton) {
                    estimate.fee?.toBigDecimal(9)?.toDouble() ?: 0.0
                } else 0.0

                swappedEstimateConfig = estimate
                val result = WalletCore.Swap.swapCexCreateTransaction(
                    accountId,
                    passcode,
                    MApiSwapCexCreateTransactionRequest(
                        from = tokenToSend.swapSlug,
                        fromAmount = cex.fromAmount!!,
                        fromAddress = accountTonAddress,
                        to = tokenToReceive.swapSlug,
                        toAddress = toUserAddress,
                        payoutExtraId = null,
                        swapFee = cex.swapFee!!,
                        networkFee = networkFee
                    )
                )

                if (estimate.request.tokenToSendIsSupported) {
                    WalletCore.Transfer.swapCexSubmit(
                        tokenToSend.mBlockchain!!, MApiSubmitTransferOptions(
                            accountId = accountId,
                            password = passcode,
                            toAddress = result.swap.cex!!.payinAddress,
                            amount = estimate.fromAmount ?: BigInteger.ZERO,
                            fee = estimate.fee,
                            tokenAddress = if (!tokenToSend.isBlockchainNative) tokenToSend.tokenAddress else null,
                            noFeeCheck = true
                        ),
                        result.swap.id
                    )
                } else {
                    _eventsFlow.tryEmit(
                        Event.ShowAddressToSend(
                            estimate = estimate,
                            response = result,
                            cex = result.swap.cex!!
                        )
                    )
                }
            }
        } catch (e: JSWebViewBridge.ApiError) {
            swappedEstimateConfig = null
            _eventsFlow.tryEmit(Event.SwapComplete(success = false, error = e.parsed))
        } catch (_: Throwable) {
            swappedEstimateConfig = null
            _eventsFlow.tryEmit(Event.SwapComplete(success = false))
        }
    }

    private fun checkReceivedActivity(receivedActivity: MApiTransaction) {
        val isSwapDone = receivedActivity is MApiTransaction.Swap &&
            (receivedActivity.from == swappedEstimateConfig?.request?.tokenToSend?.slug ||
                receivedActivity.from == swappedEstimateConfig?.request?.tokenToSend?.tokenAddress) &&
            (receivedActivity.to == swappedEstimateConfig?.request?.tokenToReceive?.slug ||
                receivedActivity.to == swappedEstimateConfig?.request?.tokenToReceive?.tokenAddress)
        if (!isSwapDone)
            return
        _eventsFlow.tryEmit(Event.SwapComplete(success = true, activity = receivedActivity))
        swappedEstimateConfig = null
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged,
            WalletEvent.BalanceChanged -> {
                _walletStateFlow.value = createWalletState()
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


    /** Init and Clear **/

    init {
        collectFlow(uiInputStateFlow, this::subscribe)
        collectFlow(uiInputStateFlow) {
            it.tokenToSend?.let { token -> loadPairsIfNeeded(token.slug) }
        }

        combine(TokenStore.swapAssetsFlow, _inputStateFlow) { assets, input ->
            if (assets != null && input.tokenToSend == null && input.tokenToReceive == null) {
                _inputStateFlow.value = _inputStateFlow.value.copy(
                    tokenToSend = assets.find { it.isTON },
                    tokenToReceive = assets.find { it.isUsdt && it.isJetton },
                    isFromAmountMax = false
                )
            }
        }.launchIn(viewModelScope)

        WalletCore.registerObserver(this)
    }

    override fun onCleared() {
        unsubscribe()
        WalletCore.unregisterObserver(this)

        super.onCleared()
    }
}
