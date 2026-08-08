@file:Suppress("ktlint:standard:backing-property-naming")

package org.mytonwallet.app_air.uisend.send

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.math.BigDecimal
import java.math.BigInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
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
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletcontext.helpers.DNSHelpers
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.TokenAmount
import org.mytonwallet.app_air.walletcore.helpers.TokenEquivalent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MSavedAddress
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiSubmitTransferResult
import org.mytonwallet.app_air.walletcore.moshi.ApiTokenWithPrice
import org.mytonwallet.app_air.walletcore.moshi.ApiTransferPayload
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiAnyDisplayError
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitTransferOptions
import org.mytonwallet.app_air.walletcore.moshi.MDieselStatus
import org.mytonwallet.app_air.walletcore.moshi.MTransferDiesel
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MExplainedTransferFee
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFee
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class SendViewModel :
    ViewModel(),
    WalletCore.EventObserver {

    /* Wallet */

    data class CurrentWalletState(val accountId: String, val balances: Map<String, BigInteger>)

    private val _walletStateFlow = combine(
        AccountStore.activeAccountIdFlow.filterNotNull(),
        BalanceStore.balancesFlow
    ) { accountId, balances ->
        CurrentWalletState(
            accountId = accountId,
            balances = balances[accountId] ?: emptyMap()
        )
    }.distinctUntilChanged()

    private val otherAccountsFlow: StateFlow<List<MAccount>> =
        AccountStore.activeAccountIdFlow
            .mapNotNull { accountId ->
                WalletCore.getAllAccounts().filter { account -> account.accountId != accountId }
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val savedAddressesFlow: StateFlow<List<MSavedAddress>> =
        AccountStore.activeAccountIdFlow
            .mapNotNull {
                AddressStore.addressData?.savedAddresses
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /* Input Raw */

    private val _inputStateFlow = MutableStateFlow(InputStateRaw())
    val inputStateFlow = _inputStateFlow.asStateFlow()

    enum class AmountSource {
        TOKEN,
        BASE_CURRENCY
    }

    data class InputStateRaw(
        val tokenSlug: String = TONCOIN_SLUG,
        val tokenCodeHash: String? = null,
        val destination: String = "",
        val destinationAccountId: String? = null,
        val amount: String = "",
        val amountInBaseCurrency: String = "",
        val comment: String = "",
        val shouldEncrypt: Boolean = false,
        val fiatMode: Boolean = false,
        val amountSource: AmountSource = AmountSource.TOKEN,
        val isMax: Boolean = false,
        val binary: String? = null,
        val stateInit: String? = null
    ) {
        val displayedAmount: String
            get() = if (fiatMode) amountInBaseCurrency else amount

        internal val sourceInBaseCurrency: Boolean
            get() = amountSource == AmountSource.BASE_CURRENCY

        internal val sourceAmount: String
            get() = if (sourceInBaseCurrency) amountInBaseCurrency else amount

        internal val isAmountSourceDisplayed: Boolean
            get() = fiatMode == sourceInBaseCurrency

        val payload: ApiTransferPayload? = when {
            binary != null -> {
                ApiTransferPayload.Base64(binary)
            }

            comment.isNotEmpty() -> {
                ApiTransferPayload.Comment(
                    comment,
                    shouldEncrypt &&
                        TokenStore.getToken(tokenSlug)?.mBlockchain?.isEncryptedCommentSupported ==
                        true
                )
            }

            else -> {
                null
            }
        }

        internal fun resolveAmountEquivalent(
            tokenPrice: BigDecimal,
            token: IApiToken,
            baseCurrency: MBaseCurrency
        ): TokenEquivalent {
            val parsedTokenAmount = CoinUtils.fromDecimal(amount, token.decimals)
            val parsedBaseCurrencyAmount = CoinUtils.fromDecimal(
                amountInBaseCurrency,
                baseCurrency.decimalsCount
            )
            if (
                !isAmountSourceDisplayed &&
                parsedTokenAmount != null &&
                parsedBaseCurrencyAmount != null
            ) {
                return TokenEquivalent(
                    price = tokenPrice,
                    token = token,
                    tokenAmount = TokenAmount.valueOf(
                        token.decimals,
                        parsedTokenAmount
                    ),
                    currency = baseCurrency,
                    currencyAmount = TokenAmount.valueOf(
                        baseCurrency.decimalsCount,
                        parsedBaseCurrencyAmount
                    )
                )
            }
            return TokenEquivalent.from(
                inFiatMode = sourceInBaseCurrency,
                price = tokenPrice,
                token = token,
                amount = if (sourceInBaseCurrency) {
                    parsedBaseCurrencyAmount ?: BigInteger.ZERO
                } else {
                    parsedTokenAmount ?: BigInteger.ZERO
                },
                currency = baseCurrency
            )
        }

        internal fun updateOtherAmount(equivalent: TokenEquivalent?): InputStateRaw {
            val otherAmount = if (displayedAmount.isEmpty()) {
                ""
            } else {
                equivalent?.getRaw(!fiatMode) ?: ""
            }
            return if (fiatMode) {
                copy(amount = otherAmount)
            } else {
                copy(amountInBaseCurrency = otherAmount)
            }
        }
    }

    private fun resolveInputAmountEquivalent(input: InputStateRaw): TokenEquivalent? {
        val token = TokenStore.getToken(input.tokenSlug) ?: return null
        val tokenPrice = token.price?.takeIf { it.isFinite() }?.let {
            BigDecimal.valueOf(it).stripTrailingZeros()
        } ?: BigDecimal.ZERO
        return input.resolveAmountEquivalent(
            tokenPrice = tokenPrice,
            token = token,
            baseCurrency = WalletCore.baseCurrency
        )
    }

    fun onInputToken(slug: String) {
        val state = _inputStateFlow.value
        val previousChain = TokenStore.getToken(state.tokenSlug)?.mBlockchain?.name
        val nextChain = TokenStore.getToken(slug)?.mBlockchain?.name
        var newState = state.copy(
            tokenSlug = slug,
            tokenCodeHash = TokenStore.getToken(slug)?.codeHash,
            destination = resolveDestinationForChainChange(
                destination = state.destination,
                destinationAccountId = state.destinationAccountId,
                previousChain = previousChain,
                nextChain = nextChain,
                accounts = WalletCore.getAllAccounts()
            ),
            amount = if (state.fiatMode) "" else state.amount,
            amountInBaseCurrency = if (state.fiatMode) state.amountInBaseCurrency else "",
            amountSource = if (state.fiatMode) {
                AmountSource.BASE_CURRENCY
            } else {
                AmountSource.TOKEN
            },
            isMax = false
        )
        newState = newState.updateOtherAmount(resolveInputAmountEquivalent(newState))
        _inputStateFlow.value = newState
    }

    fun onInputDestination(destination: String) {
        val state = _inputStateFlow.value
        _inputStateFlow.value = state.copy(
            destination = destination,
            destinationAccountId = state.destinationAccountId.takeIf {
                state.destination == destination
            }
        )
    }

    fun onDestinationAccountSelected(accountId: String, destination: String) {
        _inputStateFlow.value = _inputStateFlow.value.copy(
            destination = destination,
            destinationAccountId = accountId
        )
    }

    fun onInputAmount(amount: String) {
        val state = _inputStateFlow.value
        if (amount == state.displayedAmount) return
        var newState = if (state.fiatMode) {
            state.copy(
                amount = "",
                amountInBaseCurrency = amount,
                amountSource = AmountSource.BASE_CURRENCY,
                isMax = false
            )
        } else {
            state.copy(
                amount = amount,
                amountInBaseCurrency = "",
                amountSource = AmountSource.TOKEN,
                isMax = false
            )
        }
        newState = newState.updateOtherAmount(resolveInputAmountEquivalent(newState))
        _inputStateFlow.value = newState
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
        _inputStateFlow.value = _inputStateFlow.value.copy(
            amount = equivalent.getRaw(false),
            amountInBaseCurrency = equivalent.getRaw(true),
            amountSource = AmountSource.TOKEN,
            isMax = isMax
        )
    }

    fun onInputMaxButton() {
        val tokenSlug = _inputStateFlow.value.tokenSlug
        val accountId = AccountStore.activeAccountId ?: return
        val inputState = lastUiState?.inputState as? InputStateFull.Complete
        val equivalent = if (
            inputState?.token?.slug == tokenSlug && inputState.wallet.accountId == accountId
        ) {
            lastUiState?.draft?.takeIf {
                it.request.token.slug == tokenSlug && it.request.wallet.accountId == accountId
            }?.maxToSend ?: inputState.balanceEquivalent
        } else {
            val token = TokenStore.getToken(tokenSlug) ?: return
            val amount = BalanceStore.getBalances(accountId)?.get(tokenSlug) ?: BigInteger.ZERO
            val tokenPrice = token.price?.takeIf { it.isFinite() }?.let {
                BigDecimal.valueOf(it).stripTrailingZeros()
            } ?: BigDecimal.ZERO
            TokenEquivalent.fromToken(tokenPrice, token, amount, WalletCore.baseCurrency)
        }
        onInputTokenAmount(equivalent, true)
    }

    fun onInputToggleFiatMode() {
        val state = _inputStateFlow.value
        val updatedState = if (state.isAmountSourceDisplayed) {
            state.updateOtherAmount(resolveInputAmountEquivalent(state))
        } else {
            state
        }
        _inputStateFlow.value = updatedState.copy(fiatMode = !state.fiatMode)
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
        val accountId: String? = null,
        val isMemoRequired: Boolean? = null,
        val isScam: Boolean? = null,
        val error: MApiAnyDisplayError? = null
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
        val destinationAccountId = _inputStateFlow.value.destinationAccountId
        addressInfoJob?.cancel()
        addressInfoJob = viewModelScope.launch {
            val info = fetchAddressInfo(chain, destination, destinationAccountId)
            val currentState = _inputStateFlow.value
            if (currentState.destination.trim() == destination &&
                TokenStore.getToken(currentState.tokenSlug)?.mBlockchain == chain
            ) {
                _inputStateFlow.value = currentState.copy(
                    destinationAccountId = info?.accountId ?: currentState.destinationAccountId
                )
            }
            _addressInfoFlow.emit(info)
        }
    }

    val memoRequiredFlow = addressInfoFlow
        .map { info -> info?.isMemoRequired == true }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    private suspend fun fetchAddressInfo(
        chain: MBlockchain,
        destination: String,
        destinationAccountId: String?
    ): AddressInfo? {
        if (destination.isEmpty()) return null
        val selectedDestinationAccount = WalletCore.getAllAccounts().firstOrNull { account ->
            account.accountId == destinationAccountId &&
                account.byChain[chain.name]?.address == destination
        }
        if (selectedDestinationAccount != null) {
            return AddressInfo(
                chain = chain,
                input = destination,
                resolvedAddress = destination,
                addressName = selectedDestinationAccount.name.trim().takeIf { it.isNotEmpty() },
                accountId = selectedDestinationAccount.accountId
            )
        }
        val savedName = savedAddressesFlow.value.firstOrNull { savedAddress ->
            savedAddress.address == destination && savedAddress.chain == chain.name
        }?.name?.trim()?.takeIf { it.isNotEmpty() }
        if (savedName != null) {
            return AddressInfo(
                chain = chain,
                input = destination,
                resolvedAddress = destination,
                addressName = savedName
            )
        }

        val otherAccount = findDestinationAccount(
            destination = destination,
            chain = chain.name,
            preferredAccountId = null,
            accounts = otherAccountsFlow.value
        )
        val otherAccountName = otherAccount?.name?.trim()?.takeIf { it.isNotEmpty() }
        if (otherAccountName != null) {
            return AddressInfo(
                chain = chain,
                input = destination,
                resolvedAddress = destination,
                addressName = otherAccountName,
                accountId = otherAccount.accountId
            )
        }

        val isValid =
            chain.isValidAddress(destination) ||
                (chain == MBlockchain.ton && DNSHelpers.isDnsDomain(destination))
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
                error = result?.error
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Logger.e(
                Logger.LogTag.SEND,
                "Address lookup failed chain=${chain.name} error=${e.javaClass.simpleName}"
            )
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

            val tokenPrice: BigDecimal = token.price?.takeIf { it.isFinite() }?.let {
                BigDecimal.valueOf(it).stripTrailingZeros()
            } ?: BigDecimal.ZERO

            val balanceEquivalent = TokenEquivalent.fromToken(
                price = tokenPrice,
                token = token,
                amount = wallet.balances[token.slug] ?: BigInteger.ZERO,
                currency = baseCurrency
            )

            private val inputAmountParsed = CoinUtils.fromDecimal(
                input.sourceAmount,
                if (input.sourceInBaseCurrency) baseCurrency.decimalsCount else token.decimals
            )
            val amountEquivalent = input.resolveAmountEquivalent(
                tokenPrice = tokenPrice,
                token = token,
                baseCurrency = baseCurrency
            )

            val amount = amountEquivalent.tokenAmount
            val balance = balanceEquivalent.tokenAmount

            val inputSymbol = if (input.fiatMode) baseCurrency.sign else null
            val inputDecimal = if (input.fiatMode) baseCurrency.decimalsCount else token.decimals
            val inputError =
                (inputAmountParsed == null && input.sourceAmount.isNotEmpty()) ||
                    (amount.amountInteger > balance.amountInteger)

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
                val baseCurrency = WalletCore.baseCurrency

                return Complete(
                    wallet = walletState,
                    input = inputState,
                    token = token,
                    chain = chain,
                    tokenNative = tokenNative,
                    baseCurrency = baseCurrency
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
        abstract val explainedFee: MExplainedTransferFee?
        abstract val showingFee: MFee?

        data class Error(
            override val request: InputStateFull.Complete,
            val error: JSWebViewBridge.ApiError?,
            val anyError: MApiAnyDisplayError?,
            override val maxToSend: TokenEquivalent?,
            override val dieselStatus: MDieselStatus?,
            override val explainedFee: MExplainedTransferFee?,
            override val showingFee: MFee?
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
            val diesel: MTransferDiesel?,
            val dieselAmount: BigInteger?,
            override val explainedFee: MExplainedTransferFee?,
            override val showingFee: MFee?,
            override val maxToSend: TokenEquivalent?,
            override val dieselStatus: MDieselStatus?
        ) : DraftResult()
    }

    private fun processEstimateResponse(
        req: InputStateFull.Complete,
        draft: MApiCheckTransactionDraftResult
    ): DraftResult {
        val isNativeToken = req.token.slug == req.tokenNative.slug
        val explainedFee = draft.explainedFee
        val prevMaxToSendEquivalent =
            if (req.input.tokenSlug == lastUiState?.draft?.request?.token?.slug &&
                req.wallet.accountId == lastUiState?.draft?.request?.wallet?.accountId
            ) {
                lastUiState?.draft?.maxToSend
            } else {
                null
            }
        val maxToSend = TransferHelpers.getMaxTransferAmount(
            req.wallet.balances[req.token.slug],
            isNativeToken,
            explainedFee?.fullFee?.terms,
            explainedFee?.canTransferFullBalance ?: false
        )
        val maxToSendEquivalent = if (maxToSend == null) {
            prevMaxToSendEquivalent
        } else {
            TokenEquivalent.fromToken(
                price = req.tokenPrice,
                token = req.token,
                amount = maxToSend,
                currency = req.baseCurrency
            )
        }
        if (req.input.isMax && req.amount.amountInteger != maxToSend &&
            maxToSendEquivalent != null
        ) {
            onInputTokenAmount(maxToSendEquivalent, true)
        } else {
            val balance = req.wallet.balances[req.token.slug]
            val amount = req.amount.amountInteger
            val fullFee =
                TransferHelpers.getFullTransferFee(explainedFee?.fullFee?.terms, isNativeToken)
            if (balance != null && fullFee != null && fullFee < balance && amount <= balance &&
                amount + fullFee > balance
            ) {
                val adjustedAmount = balance - fullFee
                onInputTokenAmount(
                    TokenEquivalent.fromToken(
                        price = req.tokenPrice,
                        token = req.token,
                        amount = adjustedAmount,
                        currency = req.baseCurrency
                    ),
                    false
                )
            }
        }

        if (draft.error != null) {
            return DraftResult.Error(
                request = req,
                error = null,
                anyError = draft.error,
                maxToSend = maxToSendEquivalent,
                dieselStatus = draft.diesel?.status,
                explainedFee = explainedFee,
                showingFee = showingFee(req, draft, explainedFee)
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
            diesel = draft.diesel,
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
                    chain = req.chain,
                    options = MApiCheckTransactionDraftOptions(
                        accountId = req.wallet.accountId,
                        toAddress = req.input.destination,
                        amount = req.amountEquivalent.tokenAmount.amountInteger,
                        tokenAddress = if (!req.token.isBlockchainNative) {
                            req.token.tokenAddress
                        } else {
                            null
                        },
                        stateInit = req.input.stateInit,

                        allowGasless = true,

                        payload = req.input.payload
                    )
                )
            )
            return processEstimateResponse(req, draft)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            var maxToSend: TokenEquivalent? = null
            var dieselStatus: MDieselStatus? = null
            var explainedFee: MExplainedTransferFee? = null
            var showingFee: MFee? = null
            (e as? JSWebViewBridge.ApiError)?.parsedResult?.let { parsedResult ->
                (parsedResult as? MApiCheckTransactionDraftResult)?.let { draft ->
                    draft.error?.toErrorDialogMessage?.let { errorMessage ->
                        val lastDraftError =
                            (
                                (lastUiState?.draft as? DraftResult.Error)?.error?.parsedResult
                                    as? MApiCheckTransactionDraftResult
                                )?.error
                        val wasAlertShown =
                            lastDraftError == draft.error
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
                    explainedFee = draft.explainedFee
                    showingFee = draft.showingFee
                }
            }
            return DraftResult.Error(
                request = req,
                error = e as? JSWebViewBridge.ApiError,
                anyError = null,
                maxToSend = maxToSend,
                dieselStatus = dieselStatus,
                explainedFee = explainedFee,
                showingFee = showingFee
            )
        }
    }

    sealed interface TransferPreparation {
        data class Ready(val chain: MBlockchain, val options: MApiSubmitTransferOptions) :
            TransferPreparation

        data object MissingResolvedAddress : TransferPreparation
    }

    fun prepareTransfer(data: DraftResult.Result, enclaveToken: String): TransferPreparation {
        val request = data.request
        val diesel = data.diesel
        val resolvedAddress = data.resolvedAddress
            ?: return TransferPreparation.MissingResolvedAddress
        return TransferPreparation.Ready(
            chain = request.chain,
            options = MApiSubmitTransferOptions(
                accountId = request.wallet.accountId,
                toAddress = resolvedAddress,
                comment = request.input.binary ?: request.input.comment,
                payload = request.input.payload,
                stateInit = request.input.stateInit,
                tokenAddress = if (!request.token.isBlockchainNative) {
                    request.token.tokenAddress
                } else {
                    null
                },
                enclaveToken = enclaveToken,
                amount = request.amount.amountInteger,
                fee = data.explainedFee?.fullFee?.nativeSum ?: data.fee,
                noFeeCheck = true,
                realFee = data.explainedFee?.realFee?.nativeSum,
                isGasless = data.explainedFee?.isGasless,
                dieselAmount = data.dieselAmount,
                isGaslessWithStars = diesel?.status == MDieselStatus.STARS_FEE,
                gaslessTransaction = diesel?.transaction
            )
        )
    }

    fun getTokenSlug(): String = _inputStateFlow.value.tokenSlug

    fun getShouldEncrypt(): Boolean =
        _inputStateFlow.value.shouldEncrypt && _inputStateFlow.value.binary == null

    suspend fun callSend(preparation: TransferPreparation.Ready): ApiSubmitTransferResult =
        WalletCore.call(
            ApiMethod.Transfer.SubmitTransfer(preparation.chain, preparation.options)
        )

    private fun showingFee(
        req: InputStateFull.Complete,
        draft: MApiCheckTransactionDraftResult,
        explainedFee: MExplainedTransferFee?
    ): MFee? {
        val shouldShowFull = TransferHelpers.shouldShowFullFee(
            tokenBalance = req.wallet.balances[req.token.slug],
            isNativeToken = req.token.slug == req.tokenNative.slug,
            nativeTokenBalance = req.wallet.balances[req.tokenNative.slug],
            transferAmount = req.amount.amountInteger,
            explainedFee = explainedFee,
            diesel = draft.diesel
        )
        return if (shouldShowFull) explainedFee?.fullFee else explainedFee?.realFee
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

    data class ButtonState(val status: ButtonStatus, val title: String = "")

    data class AddressSearchState(val enabled: Boolean)

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

    fun shouldAuthorizeDiesel(): Boolean =
        lastUiState?.uiButton?.status == ButtonStatus.AuthorizeDiesel

    init {
        WalletCore.registerObserver(this)
        collectFlow(uiStateFlow) { lastUiState = it }
    }

    override fun onCleared() {
        WalletCore.unregisterObserver(this)
        super.onCleared()
    }

    fun getConfirmationPageConfig(): DraftResult.Result? = lastUiState?.draft as? DraftResult.Result

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
        internal fun resolveDestinationForChainChange(
            destination: String,
            destinationAccountId: String? = null,
            previousChain: String?,
            nextChain: String?,
            accounts: List<MAccount>
        ): String {
            if (destination.isEmpty() || previousChain == null || nextChain == null ||
                previousChain == nextChain
            ) {
                return destination
            }
            val selectedAccount = findDestinationAccount(
                destination = destination,
                chain = previousChain,
                preferredAccountId = destinationAccountId,
                accounts = accounts
            )
            return selectedAccount?.byChain?.get(nextChain)?.address ?: destination
        }

        internal fun findDestinationAccount(
            destination: String,
            chain: String,
            preferredAccountId: String?,
            accounts: List<MAccount>
        ): MAccount? = if (preferredAccountId != null) {
            accounts.firstOrNull { account ->
                account.accountId == preferredAccountId &&
                    account.byChain[chain]?.address == destination
            }
        } else {
            accounts.firstOrNull { account ->
                account.byChain[chain]?.address == destination
            }
        }

        val INVALID_ADDRESS_ERRORS = setOf(
            MApiAnyDisplayError.DOMAIN_NOT_RESOLVED,
            MApiAnyDisplayError.INVALID_ADDRESS,
            MApiAnyDisplayError.INVALID_TO_ADDRESS,
            MApiAnyDisplayError.INVALID_ADDRESS_FORMAT
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

            val slugChanged = estimated?.request?.token?.slug != input.token.slug
            val canShowFee = !slugChanged &&
                state.input.destination.isNotEmpty() &&
                state.amount.amountInteger != BigInteger.ZERO &&
                state.amount.amountInteger <= state.balance.amountInteger
            val feeFmt = if (!canShowFee) {
                null
            } else {
                estimated.showingFee?.toString(
                    state.token,
                    appendNonNative = true
                )
            }
            val feeError = canShowFee && TransferHelpers.hasInsufficientFeeError(
                tokenBalance = state.balance.amountInteger,
                nativeTokenBalance = state.wallet.balances[state.tokenNative.slug]
                    ?: BigInteger.ZERO,
                transferAmount = state.amount.amountInteger,
                fullFee = estimated.explainedFee?.fullFee?.terms,
                canTransferFullBalance = estimated.explainedFee?.canTransferFullBalance ?: false,
                dieselStatus = estimated.dieselStatus
            )
            val maxToSend = if (slugChanged) {
                state.balanceEquivalent
            } else {
                estimated.maxToSend ?: state.balanceEquivalent
            }
            val displayedMaxToSend = if (state.input.fiatMode) {
                TokenEquivalent.fromToken(
                    price = state.tokenPrice,
                    token = state.token,
                    amount = maxToSend.tokenAmount.amountInteger,
                    currency = state.baseCurrency
                )
            } else {
                maxToSend
            }
            return TokenAmountInputView.State(
                title = LocaleController.getString("Amount"),
                subtitle = if (feeFmt != null) {
                    LocaleController.getString("\$fee_value_with_colon")
                        .replace("%fee%", feeFmt)
                } else {
                    null
                },
                token = state.token,
                fiatMode = state.input.fiatMode,
                inputDecimal = state.inputDecimal,
                inputSymbol = state.inputSymbol,
                inputError = state.inputError,
                balance = displayedMaxToSend.getFmt(state.input.fiatMode),
                equivalent = state.amountEquivalent.getFmt(!state.input.fiatMode),
                feeError = feeError
            )
        }

        private fun buildUiButtonState(
            input: InputStateFull,
            estimated: DraftResult?,
            isMemoRequired: Boolean
        ): ButtonState {
            val chain = TokenStore.getToken(input.input.tokenSlug)?.mBlockchain
            if (chain != null &&
                AccountStore.activeAccount?.byChain?.get(chain.name)?.isMultisig == true
            ) {
                return ButtonState(
                    ButtonStatus.Error,
                    LocaleController.getString("Multisig sending disabled")
                )
            }
            val destination = input.input.destination
            if (destination.isEmpty()) {
                return ButtonState(
                    ButtonStatus.WaitAddress,
                    LocaleController.getString("Enter Address")
                )
            }
            val isValidAddress =
                destination != AccountStore.activeAccount?.tronAddress &&
                    (
                        chain?.isValidAddress(destination) != false ||
                            (chain == MBlockchain.ton && DNSHelpers.isDnsDomain(destination))
                        )
            if (!isValidAddress) {
                return ButtonState(
                    ButtonStatus.Error,
                    LocaleController.getString("Invalid address")
                )
            }
            if (input.input.sourceAmount.isEmpty()) {
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

            if (state.amount.amountInteger > state.balance.amountInteger ||
                state.balance.amountInteger == BigInteger.ZERO
            ) {
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
                if (draft.error?.parsed == MBridgeError.Type.INSUFFICIENT_BALANCE ||
                    draft.anyError == MApiAnyDisplayError.INSUFFICIENT_BALANCE
                ) {
                    if (draft.dieselStatus == MDieselStatus.NOT_AUTHORIZED) {
                        return ButtonState(
                            ButtonStatus.AuthorizeDiesel,
                            LocaleController.getFormattedString(
                                "Authorize %1$@ fee",
                                listOf(draft.request.token.symbol ?: "")
                            )
                        )
                    }
                    return ButtonState(
                        ButtonStatus.NotEnoughNativeToken,
                        LocaleController.getString("Insufficient Fee")
                    )
                }
                val error = draft.anyError
                    ?: (draft.error?.parsedResult as? MApiCheckTransactionDraftResult)?.error
                return if (INVALID_ADDRESS_ERRORS.contains(error)) {
                    ButtonState(
                        ButtonStatus.Error,
                        LocaleController.getString("Invalid address")
                    )
                } else if (error?.toErrorDialogMessage != null) {
                    ButtonState(
                        ButtonStatus.ErrorAlert,
                        LocaleController.getString("Continue")
                    )
                } else {
                    ButtonState(
                        ButtonStatus.WaitNetwork,
                        LocaleController.getString("Waiting for Network")
                    )
                }
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
                if (draft.explainedFee?.isGasless == true) {
                    if (draft.dieselStatus == MDieselStatus.NOT_AUTHORIZED) {
                        return ButtonState(
                            ButtonStatus.AuthorizeDiesel,
                            LocaleController.getFormattedString(
                                "Authorize %1$@ fee",
                                listOf(draft.request.token.symbol ?: "")
                            )
                        )
                    }
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
