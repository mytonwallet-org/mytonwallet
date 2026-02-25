package org.mytonwallet.app_air.uisend.send

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import org.mytonwallet.app_air.uicomponents.commonViews.TokenAmountInputView
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.throttle
import org.mytonwallet.app_air.uisend.send.helpers.TransferHelpers
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletcontext.helpers.DNSHelpers
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.TokenEquivalent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MFee
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.models.explainedFee.ExplainedTransferFee
import org.mytonwallet.app_air.walletcore.moshi.ApiSubmitTransferResult
import org.mytonwallet.app_air.walletcore.moshi.ApiTokenWithPrice
import org.mytonwallet.app_air.walletcore.moshi.ApiTransferPayload
import org.mytonwallet.app_air.walletcore.moshi.MApiAnyDisplayError
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitTransferOptions
import org.mytonwallet.app_air.walletcore.moshi.MDieselStatus
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore
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

    private val otherAccountsFlow: Flow<List<MAccount>> =
        AccountStore.activeAccountIdFlow.mapNotNull { accountId ->
            WalletCore.getAllAccounts().filter { account -> account.accountId != accountId }
        }

    private val savedAddressesFlow: Flow<List<MSavedAddress>> =
        AccountStore.activeAccountIdFlow.mapNotNull {
            AddressStore.addressData?.savedAddresses
        }

    /* Input Raw */

    private val _inputStateFlow = MutableStateFlow(InputStateRaw())
    val inputStateFlow = _inputStateFlow.asStateFlow()

    data class InputStateRaw(
        val tokenSlug: String = TONCOIN_SLUG,
        val tokenCodeHash: String? = null,
        val destination: String = "",
        val amount: String = "",
        val comment: String = "",
        val shouldEncrypt: Boolean = false,
        val fiatMode: Boolean = false,
        val isMax: Boolean = false,
        val binary: String? = null,
        val stateInit: String? = null,
    ) {
        val payload: ApiTransferPayload? = when {
            binary != null -> {
                ApiTransferPayload.Base64(binary)
            }

            comment.isNotEmpty() -> {
                ApiTransferPayload.Comment(comment, shouldEncrypt && TokenStore.getToken(tokenSlug)?.mBlockchain?.isEncryptedCommentSupported == true)
            }

            else -> {
                null
            }
        }
    }

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

    data class AddressInfo(
        val chain: MBlockchain,
        val input: String,
        val resolvedAddress: String? = null,
        val addressName: String? = null,
        val isMemoRequired: Boolean? = null,
        val isScam: Boolean? = null,
        val error: MApiAnyDisplayError? = null,
    )

    private val _addressInfoFlow = MutableStateFlow<AddressInfo?>(null)
    val addressInfoFlow = _addressInfoFlow.asStateFlow()
    private var addressInfoJob: Job? = null

    fun onDestinationEntered(address: String) {
        val destination = address.trim()
        if (destination.isEmpty()) {
            _addressInfoFlow.value = null
            return
        }
        val chain = TokenStore.getToken(getTokenSlug())?.mBlockchain ?: MBlockchain.ton
        addressInfoJob?.cancel()
        addressInfoJob = viewModelScope.launch {
            _addressInfoFlow.emit(fetchAddressInfo(chain, destination))
        }
    }

    val memoRequiredFlow = addressInfoFlow
        .map { info -> info?.isMemoRequired == true }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    private suspend fun fetchAddressInfo(chain: MBlockchain, destination: String): AddressInfo? {
        if (destination.isEmpty()) return null
        val savedName = AddressStore.getSavedAddress(destination, chain.name)
            ?.name
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        if (savedName != null) {
            return AddressInfo(
                chain = chain,
                input = destination,
                resolvedAddress = destination,
                addressName = savedName,
            )
        }
        val isValid =
            chain.isValidAddress(destination) || (chain == MBlockchain.ton && DNSHelpers.isDnsDomain(destination))
        if (!isValid) return null
        val network = AccountStore.activeAccount?.network ?: return null
        return try {
            val result = withTimeoutOrNull(100) {
                WalletCore.call(
                    ApiMethod.WalletData.GetAddressInfo(
                        chain = chain,
                        network = network,
                        addressOrDomain = destination
                    )
                )
            }
            AddressInfo(
                chain = chain,
                input = destination,
                resolvedAddress = result?.resolvedAddress,
                addressName = result?.addressName,
                isMemoRequired = result?.isMemoRequired,
                isScam = result?.isScam,
                error = result?.error,
            )
        } catch (_: Throwable) {
            AddressInfo(chain, destination)
        }
    }

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
                    WalletCore.baseCurrency
                )
                val chain = token.mBlockchain ?: return Incomplete(
                    walletState,
                    inputState,
                    token,
                    WalletCore.baseCurrency
                )
                val tokenNative = tokens.tokens[chain.nativeSlug] ?: return Incomplete(
                    walletState,
                    inputState,
                    token,
                    WalletCore.baseCurrency
                )

                return Complete(
                    wallet = walletState,
                    input = inputState,
                    token = token,
                    chain = chain,
                    tokenNative = tokenNative,
                    baseCurrency = WalletCore.baseCurrency!!
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
                        stateInit = req.input.stateInit,

                        allowGasless = true,

                        payload = req.input.payload,
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
            toAddress = data.resolvedAddress!!,
            comment = request.input.binary ?: request.input.comment,
            payload = request.input.payload,
            stateInit = request.input.stateInit,
            tokenAddress = if (!request.token.isBlockchainNative) request.token.tokenAddress else null,
            password = passcode,
            amount = request.amount.amountInteger,
            fee = data.explainedFee?.fullFee?.nativeSum ?: data.fee,
            noFeeCheck = true,
            realFee = data.explainedFee?.realFee?.nativeSum,
            isGasless = data.explainedFee?.isGasless,
            dieselAmount = data.dieselAmount,
            isGaslessWithStars = data.dieselStatus == MDieselStatus.STARS_FEE,
        )
    }

    fun getTokenSlug(): String {
        return _inputStateFlow.value.tokenSlug
    }

    fun getShouldEncrypt(): Boolean {
        return _inputStateFlow.value.shouldEncrypt && _inputStateFlow.value.binary == null
    }

    suspend fun callSend(data: DraftResult.Result, passcode: String): ApiSubmitTransferResult {
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
        WaitMemo,
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

    data class AddressSearchState(
        val enabled: Boolean
    )

    data class UiState(
        internal val inputState: InputStateFull,
        internal val draft: DraftResult?,
        val uiAddressSearch: AddressSearchState,
        val isMemoRequired: Boolean
    ) {
        val uiInput: TokenAmountInputView.State = buildUiInputState(inputState, draft)
        val uiButton: ButtonState = buildUiButtonState(inputState, draft, isMemoRequired)
    }

    val uiStateFlow = combine(
        inputFlow,
        draftFlow,
        otherAccountsFlow,
        savedAddressesFlow,
        memoRequiredFlow
    ) { input, draft, otherAccounts, savedAddresses, memoRequired ->
        UiState(
            input,
            draft,
            AddressSearchState(otherAccounts.isNotEmpty() || savedAddresses.isNotEmpty()),
            memoRequired
        )
    }


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
                    title = LocaleController.getString("Amount"),
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
                title = LocaleController.getString("Amount"),
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
            estimated: DraftResult?,
            isMemoRequired: Boolean
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
                if (isMemoRequired &&
                    state.input.binary == null &&
                    state.input.comment.isBlank()
                ) {
                    return ButtonState(
                        ButtonStatus.WaitMemo,
                        LocaleController.getString("Continue")
                    )
                }
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
