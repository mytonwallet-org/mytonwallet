package org.mytonwallet.app_air.uisend.send

import androidx.lifecycle.ViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.onStart
import org.mytonwallet.app_air.uicomponents.commonViews.TokenAmountInputView
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.throttle
import org.mytonwallet.app_air.uisend.send.helpers.TransferHelpers
import org.mytonwallet.app_air.walletcontext.helpers.DNSHelpers
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.TokenEquivalent
import org.mytonwallet.app_air.walletcore.models.MBaseCurrency
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MFee
import org.mytonwallet.app_air.walletcore.models.explainedFee.ExplainedTransferFee
import org.mytonwallet.app_air.walletcore.moshi.ApiTokenWithPrice
import org.mytonwallet.app_air.walletcore.moshi.MApiAnyDisplayError
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitTransferOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitTransferResult
import org.mytonwallet.app_air.walletcore.moshi.MDieselStatus
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigDecimal
import java.math.BigInteger

class SendViewModel : ViewModel(), WalletCore.EventObserver {

    /* Wallet */

    data class CurrentWalletState(
        val accountId: String,
        val balances: Map<String, BigInteger>
    )

    private val _walletStateFlow = combine(
        AccountStore.activeAccountIdFlow.filterNotNull(),
        BalanceStore.balancesFlow
    ) { accountId, balances ->
        CurrentWalletState(
            accountId = accountId,
            balances = balances[accountId] ?: emptyMap()
        )
    }.distinctUntilChanged()


    /* Input Raw */

    private val _inputStateFlow = MutableStateFlow(InputStateRaw())
    val inputStateFlow = _inputStateFlow.asStateFlow()

    data class InputStateRaw(
        val tokenSlug: String = "toncoin",
        val tokenCodeHash: String? = null,
        val destination: String = "",
        val amount: String = "",
        val comment: String = "",
        val shouldEncrypt: Boolean = false,
        val fiatMode: Boolean = false,
        val isMax: Boolean = false,
        val binary: String? = null,
        val stateInit: String? = null,
    )

    fun onInputToken(slug: String) {
        _inputStateFlow.value = _inputStateFlow.value.copy(
            tokenSlug = slug,
            tokenCodeHash = TokenStore.getToken(slug)?.codeHash,
            isMax = false
        )
    }

    fun onInputDestination(destination: String) {
        _inputStateFlow.value = _inputStateFlow.value.copy(destination = destination)
    }

    fun onInputAmount(amount: String) {
        if (amount == _inputStateFlow.value.amount)
            return
        _inputStateFlow.value = _inputStateFlow.value.copy(amount = amount, isMax = false)
    }

    fun onInputComment(comment: String) {
        _inputStateFlow.value = _inputStateFlow.value.copy(comment = comment)
    }

    fun setBinaryData(binary: String) {
        _inputStateFlow.value = _inputStateFlow.value.copy(binary = binary)
    }

    fun setStateInit(stateInit: String) {
        _inputStateFlow.value = _inputStateFlow.value.copy(stateInit = stateInit)
    }

    private fun onInputTokenAmount(equivalent: TokenEquivalent, isMax: Boolean) {
        val state = _inputStateFlow.value
        _inputStateFlow.value = _inputStateFlow.value.copy(
            amount = equivalent.getRaw(state.fiatMode),
            isMax = isMax
        )
    }

    fun onInputMaxButton() {
        val equivalent = lastUiState?.draft?.maxToSend
            ?: (lastUiState?.inputState as? InputStateFull.Complete)?.balanceEquivalent ?: return
        onInputTokenAmount(equivalent, true)
    }

    fun onInputToggleFiatMode() {
        val state = _inputStateFlow.value
        val fiatMode = !state.fiatMode
        val amount = (if (state.amount.isNotEmpty())
            (lastUiState?.inputState as? InputStateFull.Complete)?.amountEquivalent?.getRaw(fiatMode)
        else null) ?: ""

        _inputStateFlow.value = _inputStateFlow.value.copy(amount = amount, fiatMode = fiatMode)
    }

    fun onShouldEncrypt(shouldEncrypt: Boolean) {
        _inputStateFlow.value = _inputStateFlow.value.copy(shouldEncrypt = shouldEncrypt)
    }

    /* Input Full */

    private val inputFlow = combine(
        _walletStateFlow,
        _inputStateFlow,
        TokenStore.tokensFlow,
        InputStateFull::of
    ).distinctUntilChanged()

    sealed class InputStateFull {
        abstract val wallet: CurrentWalletState
        abstract val input: InputStateRaw

        data class Complete(
            override val wallet: CurrentWalletState,
            override val input: InputStateRaw,
            val token: ApiTokenWithPrice,
            val chain: MBlockchain,
            val tokenNative: ApiTokenWithPrice,
            val baseCurrency: MBaseCurrency
        ) : InputStateFull() {

            val tokenPrice: BigDecimal = token.price?.let {
                BigDecimal.valueOf(it).stripTrailingZeros()
            } ?: BigDecimal.ZERO

            val balanceEquivalent = TokenEquivalent.fromToken(
                price = tokenPrice,
                token = token,
                amount = wallet.balances[token.slug] ?: BigInteger.ZERO,
                currency = baseCurrency
            )

            private val inputAmountParsed = CoinUtils.fromDecimal(
                input.amount,
                if (input.fiatMode) baseCurrency.decimalsCount else token.decimals
            )
            val amountEquivalent = TokenEquivalent.from(
                inFiatMode = input.fiatMode,
                price = tokenPrice,
                token = token,
                amount = inputAmountParsed ?: BigInteger.ZERO,
                currency = baseCurrency
            )

            val amount = amountEquivalent.tokenAmount
            val balance = balanceEquivalent.tokenAmount

            val inputSymbol = if (input.fiatMode) baseCurrency.sign else null
            val inputDecimal = if (input.fiatMode) baseCurrency.decimalsCount else token.decimals
            val inputError =
                (inputAmountParsed == null && input.amount.isNotEmpty()) || (amount.amountInteger > balance.amountInteger)

            val key =
                "${token.slug}_${input.destination}_${amount}_${balance}_${input.shouldEncrypt}_${input.comment}"
        }

        data class Incomplete(
            override val wallet: CurrentWalletState,
            override val input: InputStateRaw,
            val token: ApiTokenWithPrice?,
            val baseCurrency: MBaseCurrency?
        ) : InputStateFull()

        companion object {
            fun of(
                walletState: CurrentWalletState,
                inputState: InputStateRaw,
                tokensState: TokenStore.Tokens?
            ): InputStateFull {
                val tokens = tokensState ?: return Incomplete(walletState, inputState, null, null)
                val token = tokens.tokens[inputState.tokenSlug] ?: return Incomplete(
                    walletState,
                    inputState,
                    null,
                    tokens.baseCurrency
                )
                val chain = token.mBlockchain ?: return Incomplete(
                    walletState,
                    inputState,
                    token,
                    tokens.baseCurrency
                )
                val tokenNative = tokens.tokens[chain.nativeSlug] ?: return Incomplete(
                    walletState,
                    inputState,
                    token,
                    tokens.baseCurrency
                )

                return Complete(
                    wallet = walletState,
                    input = inputState,
                    token = token,
                    chain = chain,
                    tokenNative = tokenNative,
                    baseCurrency = tokens.baseCurrency
                )
            }
        }
    }


    /* Estimate */

    @OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
    private val draftFlow = inputFlow
        .throttle(1000)
        .flatMapLatest { i ->
            flow {
                when (i) {
                    is InputStateFull.Complete -> emit(callEstimate(i))
                    is InputStateFull.Incomplete -> emit(null)
                }
            }
        }
        .onStart { emit(null) }
        .distinctUntilChanged()

    sealed class DraftResult {
        abstract val request: InputStateFull.Complete
        abstract val maxToSend: TokenEquivalent?
        abstract val dieselStatus: MDieselStatus?

        data class Error(
            override val request: InputStateFull.Complete,
            val error: JSWebViewBridge.ApiError?,
            val anyError: MApiAnyDisplayError?,
            override val maxToSend: TokenEquivalent?,
            override val dieselStatus: MDieselStatus?,
        ) : DraftResult()

        data class Result(
            override val request: InputStateFull.Complete,
            val fee: BigInteger?,
            val addressName: String?,
            val isScam: Boolean?,
            val resolvedAddress: String?,
            val isToAddressNew: Boolean?,
            val isBounceable: Boolean?,
            val isMemoRequired: Boolean?,
            val dieselAmount: BigInteger?,
            val explainedFee: ExplainedTransferFee?,
            val showingFee: MFee?,
            override val maxToSend: TokenEquivalent?,
            override val dieselStatus: MDieselStatus?,
        ) : DraftResult()
    }

    private fun processEstimateResponse(
        req: InputStateFull.Complete,
        draft: MApiCheckTransactionDraftResult
    ): DraftResult {
        val isNativeToken = req.token.slug == req.tokenNative.slug
        val explainedFee = TransferHelpers.explainApiTransferFee(
            req.token.chain!!,
            isNativeToken,
            draft
        )
        val prevMaxToSendEquivalent =
            if (req.input.tokenSlug == lastUiState?.draft?.request?.token?.slug)
                lastUiState?.draft?.maxToSend else null
        val maxToSend = TransferHelpers.getMaxTransferAmount(
            req.wallet.balances[req.token.slug],
            isNativeToken,
            explainedFee.fullFee?.terms,
            explainedFee.canTransferFullBalance
        )
        val maxToSendEquivalent = (lastUiState?.inputState as? InputStateFull.Complete)?.let {
            if (maxToSend == null)
                return@let prevMaxToSendEquivalent
            TokenEquivalent.fromToken(
                price = it.tokenPrice,
                token = it.token,
                amount = maxToSend,
                currency = it.baseCurrency
            )
        }
        if (req.input.isMax && req.amount.amountInteger != maxToSend && maxToSendEquivalent != null) {
            onInputTokenAmount(maxToSendEquivalent, true)
        }

        if (draft.error != null) {
            return DraftResult.Error(
                request = req,
                error = null,
                anyError = draft.error,
                maxToSend = maxToSendEquivalent,
                dieselStatus = draft.diesel?.status
            )
        }
        return DraftResult.Result(
            request = req,
            fee = draft.fee,
            addressName = draft.addressName,
            isScam = draft.isScam,
            resolvedAddress = draft.resolvedAddress,
            isToAddressNew = draft.isToAddressNew,
            isBounceable = draft.isBounceable,
            isMemoRequired = draft.isMemoRequired,
            dieselStatus = draft.diesel?.status,
            dieselAmount = draft.diesel?.amount,
            explainedFee = explainedFee,
            showingFee = showingFee(req, draft, explainedFee),
            maxToSend = maxToSendEquivalent
        )
    }

    private suspend fun callEstimate(req: InputStateFull.Complete): DraftResult {
        try {
            val draft = WalletCore.call(
                ApiMethod.Transfer.CheckTransactionDraft(
                    chain = req.token.mBlockchain!!,
                    options = MApiCheckTransactionDraftOptions(
                        accountId = req.wallet.accountId,
                        toAddress = req.input.destination,
                        amount = req.amountEquivalent.tokenAmount.amountInteger,
                        tokenAddress = if (!req.token.isBlockchainNative) req.token.tokenAddress else null,
                        data = req.input.binary ?: req.input.comment,
                        stateInit = req.input.stateInit,
                        shouldEncrypt = req.input.shouldEncrypt && req.input.binary == null,
                        isBase64Data = req.input.binary != null,
                        allowGasless = true
                    )
                )
            )
            return processEstimateResponse(req, draft)
        } catch (e: Throwable) {
            if (e is CancellationException) {
                throw e
            }
            var maxToSend: TokenEquivalent? = null
            var dieselStatus: MDieselStatus? = null
            (e as? JSWebViewBridge.ApiError)?.parsedResult?.let { parsedResult ->
                (parsedResult as? MApiCheckTransactionDraftResult)?.let { draft ->
                    draft.error?.toErrorDialogMessage?.let { errorMessage ->
                        val wasAlertShown =
                            ((lastUiState?.draft as? DraftResult.Error)?.error?.parsedResult as? MApiCheckTransactionDraftResult)?.error == draft.error
                        if (!wasAlertShown) {
                            _uiEventFlow.tryEmit(
                                UiEvent.ShowAlert(
                                    title = LocaleController.getString("Error"),
                                    message = errorMessage
                                )
                            )
                        }
                    }
                    val draft = processEstimateResponse(req, draft)
                    maxToSend = draft.maxToSend
                    dieselStatus = draft.dieselStatus
                }
            }
            return DraftResult.Error(
                request = req,
                error = e as? JSWebViewBridge.ApiError,
                anyError = null,
                maxToSend = maxToSend,
                dieselStatus = dieselStatus
            )
        }
    }

    fun getTransferOptions(data: DraftResult.Result, passcode: String): MApiSubmitTransferOptions {
        val request = data.request
        return MApiSubmitTransferOptions(
            accountId = request.wallet.accountId,
            password = passcode,
            toAddress = data.resolvedAddress!!,
            amount = request.amount.amountInteger,
            comment = request.input.binary ?: request.input.comment,
            tokenAddress = if (!request.token.isBlockchainNative) request.token.tokenAddress else null,
            fee = data.explainedFee?.fullFee?.nativeSum ?: data.fee,
            realFee = data.explainedFee?.realFee?.nativeSum,
            shouldEncrypt = request.input.shouldEncrypt && request.input.binary == null,
            isBase64Data = request.input.binary != null,
            withDiesel = data.explainedFee?.isGasless,
            dieselAmount = data.dieselAmount,
            isGaslessWithStars = data.dieselStatus == MDieselStatus.STARS_FEE,
            stateInit = request.input.stateInit
        )
    }

    fun getTokenSlug(): String {
        return _inputStateFlow.value.tokenSlug
    }

    fun getShouldEncrypt(): Boolean {
        return _inputStateFlow.value.shouldEncrypt && _inputStateFlow.value.binary == null
    }

    suspend fun callSend(data: DraftResult.Result, passcode: String): MApiSubmitTransferResult {
        val request = data.request

        val options = getTransferOptions(data, passcode)
        return WalletCore.call(
            ApiMethod.Transfer.SubmitTransfer(request.chain, options)
        )
    }

    private fun showingFee(
        req: InputStateFull.Complete,
        draft: MApiCheckTransactionDraftResult,
        explainedFee: ExplainedTransferFee
    ): MFee? {
        val isToncoin = req.token.slug == "toncoin"
        val accountBalance = req.wallet.balances[req.token.slug]
        val isToncoinFullBalance = isToncoin && req.amount.amountInteger == accountBalance
        val nativeTokenBalance =
            req.wallet.balances[req.tokenNative.slug] ?: BigInteger.ZERO
        val isEnoughNativeCoin = if (isToncoinFullBalance) {
            draft.fee != null && draft.fee!! < nativeTokenBalance
        } else {
            draft.fee != null && (draft.fee!! + (if (isToncoin) req.amount.amountInteger else BigInteger.ZERO)) <= nativeTokenBalance
        }
        val isGaslessWithStars = draft.diesel?.status == MDieselStatus.STARS_FEE
        val isDieselAvailable =
            draft.diesel?.status == MDieselStatus.AVAILABLE || isGaslessWithStars
        val dieselAmount = draft.diesel?.amount ?: BigInteger.ZERO
        val isEnoughDiesel =
            if (explainedFee.isGasless &&
                req.amount.amountInteger > BigInteger.ZERO &&
                (accountBalance ?: BigInteger.ZERO) > BigInteger.ZERO &&
                (draft.diesel?.amount != null)
            ) {
                if (isGaslessWithStars) {
                    true
                } else {
                    (accountBalance
                        ?: BigInteger.ZERO) - req.amount.amountInteger >= dieselAmount
                }
            } else {
                false
            }
        val isInsufficientFee =
            (draft.fee != null && !isEnoughNativeCoin && !isDieselAvailable) || (explainedFee.isGasless && !isEnoughDiesel)
        val isInsufficientBalance =
            accountBalance != null && req.amount.amountInteger > accountBalance
        val shouldShowFull = isInsufficientFee && !isInsufficientBalance
        return if (shouldShowFull) explainedFee.fullFee else explainedFee.realFee
    }

    /* Ui State */

    enum class ButtonStatus {
        WaitAmount,
        WaitAddress,
        WaitNetwork,
        ErrorAlert,

        Loading,
        Error,
        NotEnoughNativeToken,
        NotEnoughToken,
        AuthorizeDiesel,
        PendingPreviousDiesel,
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

    data class UiState(
        internal val inputState: InputStateFull,
        internal val draft: DraftResult?,
    ) {
        val uiInput = buildUiInputState(inputState, draft)
        val uiButton = buildUiButtonState(inputState, draft)
    }

    val uiStateFlow = combine(inputFlow, draftFlow) { input, draft -> UiState(input, draft) }


    /* * */

    private var lastUiState: UiState? = null

    fun shouldAuthorizeDiesel(): Boolean {
        return lastUiState?.uiButton?.status == ButtonStatus.AuthorizeDiesel
    }

    init {
        WalletCore.registerObserver(this)
        collectFlow(uiStateFlow) { lastUiState = it }
    }

    override fun onCleared() {
        WalletCore.unregisterObserver(this)
        super.onCleared()
    }

    fun getConfirmationPageConfig(): DraftResult.Result? {
        return lastUiState?.draft as? DraftResult.Result
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.NetworkConnected,
            WalletEvent.NetworkDisconnected -> {
                val correctVal = _inputStateFlow.value
                _inputStateFlow.value = InputStateRaw()
                _inputStateFlow.value = correctVal
            }

            else -> {}
        }
    }

    companion object {
        val INVALID_ADDRESS_ERRORS = setOf(
            MApiAnyDisplayError.DOMAIN_NOT_RESOLVED,
            MApiAnyDisplayError.INVALID_TO_ADDRESS
        )

        private fun buildUiInputState(
            input: InputStateFull,
            estimated: DraftResult?
        ): TokenAmountInputView.State {
            val state: InputStateFull.Complete = when (input) {
                is InputStateFull.Complete -> input
                is InputStateFull.Incomplete -> return TokenAmountInputView.State(
                    title = LocaleController.getString("\$send_action"),
                    subtitle = null,
                    token = input.token,
                    fiatMode = input.input.fiatMode,
                    inputDecimal = 0,
                    inputSymbol = null,
                    inputError = false,
                    balance = null,
                    equivalent = null
                )
            }

            val draftResult = estimated as? DraftResult.Result
            val slugChanged = estimated?.request?.token?.slug != input.token.slug
            val feeFmt = if (slugChanged) null else draftResult?.showingFee?.toString(
                state.token,
                appendNonNative = true
            )
            return TokenAmountInputView.State(
                title = LocaleController.getString("\$send_action"),
                subtitle = if (feeFmt != null)
                    LocaleController.getString("\$fee_value_with_colon")
                        .replace("%fee%", feeFmt)
                else
                    null,
                token = state.token,
                fiatMode = state.input.fiatMode,
                inputDecimal = state.inputDecimal,
                inputSymbol = state.inputSymbol,
                inputError = state.inputError,
                balance = (if (slugChanged) state.balanceEquivalent else (estimated.maxToSend
                    ?: state.balanceEquivalent)).getFmt(state.input.fiatMode),
                equivalent = state.amountEquivalent.getFmt(!state.input.fiatMode)
            )
        }

        private fun buildUiButtonState(
            input: InputStateFull,
            estimated: DraftResult?
        ): ButtonState {
            val destination = input.input.destination
            if (destination.isEmpty()) {
                return ButtonState(
                    ButtonStatus.WaitAddress,
                    LocaleController.getString("Enter Address")
                )
            }
            val chain = TokenStore.getToken(input.input.tokenSlug)?.mBlockchain
            val isValidAddress =
                destination != AccountStore.activeAccount?.tronAddress &&
                    (
                        chain?.isValidAddress(destination) != false ||
                            (chain == MBlockchain.ton && DNSHelpers.isDnsDomain(destination))
                        )
            if (!isValidAddress) {
                return ButtonState(
                    ButtonStatus.WaitAddress,
                    LocaleController.getString("Invalid address")
                )
            }
            if (input.input.amount.isEmpty()) {
                return ButtonState(
                    ButtonStatus.WaitAmount,
                    LocaleController.getString("Enter Amount")
                )
            }

            val state =
                input as? InputStateFull.Complete ?: return ButtonState(ButtonStatus.Loading)
            if (state.amount.amountInteger == BigInteger.ZERO) {
                return ButtonState(
                    ButtonStatus.WaitAmount,
                    LocaleController.getString("Enter Amount")
                )
            }

            if (state.amount.amountInteger > state.balance.amountInteger || state.balance.amountInteger == BigInteger.ZERO) {
                return ButtonState(
                    ButtonStatus.NotEnoughToken,
                    LocaleController.getString("Insufficient Balance")
                )
            }

            val draft = estimated ?: return ButtonState(ButtonStatus.Loading)

            if (state.key != draft.request.key) {
                return ButtonState(ButtonStatus.Loading)
            }

            if (draft is DraftResult.Error) {
                if (draft.error?.parsed == MBridgeError.INSUFFICIENT_BALANCE) {
                    if (draft.dieselStatus == MDieselStatus.NOT_AUTHORIZED) {
                        return ButtonState(
                            ButtonStatus.AuthorizeDiesel, LocaleController.getFormattedString(
                                "Authorize %1$@ fee",
                                listOf(draft.request.token.symbol ?: "")
                            )
                        )
                    }
                    return ButtonState(
                        ButtonStatus.NotEnoughNativeToken,
                        LocaleController.getFormattedString(
                            "Insufficient %1$@ Balance",
                            listOf(
                                state.tokenNative.symbol ?: ""
                            )
                        )
                    )
                }
                val error = (draft.error?.parsedResult as? MApiCheckTransactionDraftResult)?.error
                return if (INVALID_ADDRESS_ERRORS.contains(error))
                    ButtonState(
                        ButtonStatus.WaitAddress,
                        LocaleController.getString("Invalid address")
                    )
                else if (error?.toErrorDialogMessage != null)
                    ButtonState(
                        ButtonStatus.ErrorAlert,
                        LocaleController.getString("Continue")
                    )
                else
                    ButtonState(
                        ButtonStatus.WaitNetwork,
                        LocaleController.getString("Waiting for Network")
                    )
            }

            if (draft is DraftResult.Result) {
                if (draft.explainedFee?.isGasless == true)
                    if (draft.dieselStatus == MDieselStatus.NOT_AUTHORIZED) {
                        return ButtonState(
                            ButtonStatus.AuthorizeDiesel, LocaleController.getFormattedString(
                                "Authorize %1$@ fee",
                                listOf(draft.request.token.symbol ?: "")
                            )
                        )
                    }
                if (draft.dieselStatus == MDieselStatus.PENDING_PREVIOUS) {
                    return ButtonState(
                        ButtonStatus.PendingPreviousDiesel,
                        LocaleController.getString("Pending previous fee")
                    )
                }
            }

            return ButtonState(
                ButtonStatus.Ready,
                LocaleController.getString("Continue")
            )
        }
    }

    /* UI Events */
    private val _uiEventFlow: MutableSharedFlow<UiEvent> =
        MutableSharedFlow(extraBufferCapacity = 1)
    val uiEventFlow = _uiEventFlow.asSharedFlow()

    sealed class UiEvent {
        data class ShowAlert(val title: String, val message: String) : UiEvent()
    }
}
