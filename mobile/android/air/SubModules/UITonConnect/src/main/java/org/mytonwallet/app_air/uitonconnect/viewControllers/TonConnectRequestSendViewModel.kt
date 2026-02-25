package org.mytonwallet.app_air.uitonconnect.viewControllers

import android.graphics.RectF
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.ClickableSpan
import android.view.Gravity
import android.view.View
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.DappWarningPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.FakeLoading
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.TonConnectItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.requestDAppList
import org.mytonwallet.app_air.walletcore.helpers.DappFeeHelpers
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.ApiDappTransfer
import org.mytonwallet.app_air.walletcore.moshi.ApiParsedPayload
import org.mytonwallet.app_air.walletcore.moshi.ApiTokenWithPrice
import org.mytonwallet.app_air.walletcore.moshi.MSignDataPayload
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.DApp.ConfirmDappRequestSendTransaction
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.Transfer.SignDappTransfers
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.Transfer.SignDappTransfers.Options
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.app_air.walletcore.toAmountString
import java.math.BigDecimal
import java.math.BigInteger

class TonConnectRequestSendViewModel private constructor(
    private val update: ApiUpdate.ApiUpdateDappSignRequest
) : ViewModel() {
    private val transactionTokenSlugs =
        if (update is ApiUpdate.ApiUpdateDappSendTransactions) update.transactions.map {
            it.payload?.payloadTokenSlug
        } else emptyList()
    private val tokensMapFlow = TokenStore.tokensFlow.map { tokens ->
        Tokens(
            currency = WalletCore.baseCurrency,
            tokens = tokens?.tokens,
            list = transactionTokenSlugs.map {
                val t = tokens?.tokens?.get(it ?: TONCOIN_SLUG)
                Token(
                    slug = it ?: TONCOIN_SLUG,
                    token = t,
                    isUnknown = t == null && !tokens?.tokens.isNullOrEmpty()
                )
            }
        )

    }.distinctUntilChanged()
    val uiItemsFlow = tokensMapFlow.map(this::buildUiItems)

    private data class Tokens(
        val currency: MBaseCurrency,
        val tokens: Map<String, ApiTokenWithPrice>?,
        val list: List<Token>
    )

    private data class Token(
        val slug: String,
        val token: ApiTokenWithPrice?,
        val isUnknown: Boolean,
    ) {
        val icon by lazy {
            token?.let {
                Content.of(it, showChain = false)
            } ?: TokenStore.getToken(slug)
                ?.takeIf { it.isBlockchainNative }
                ?.mBlockchain
                ?.let(Content::chain)
        }
    }

    data class UiState(
        val cancelButtonIsLoading: Boolean
    ) {
        val isLocked = cancelButtonIsLoading
    }


    private val _uiStateFlow = MutableStateFlow(UiState(cancelButtonIsLoading = false))
    val uiStateFlow = _uiStateFlow.asStateFlow()


    fun cancel(promiseId: String, reason: String?, scope: CoroutineScope? = null) {
        if (isConfirmed)
            return
        assert(promiseId)
        if (_uiStateFlow.value.isLocked) {
            return
        }

        _uiStateFlow.value = _uiStateFlow.value.copy(cancelButtonIsLoading = true)
        (scope ?: viewModelScope).launch {
            val t = FakeLoading.init()
            try {
                WalletCore.call(
                    ApiMethod.DApp.CancelDappRequest(
                        promiseId = update.promiseId,
                        reason = reason
                    )
                )
                FakeLoading.start(500, t)
            } catch (_: JSWebViewBridge.ApiError) {
                // todo: show error
            }
            _eventsFlow.tryEmit(Event.Close)
            _uiStateFlow.value = _uiStateFlow.value.copy(cancelButtonIsLoading = false)
        }
    }

    fun accept(promiseId: String, password: String) {
        assert(promiseId)
        if (_uiStateFlow.value.isLocked) {
            return
        }

        viewModelScope.launch {
            when (update) {
                is ApiUpdate.ApiUpdateDappSendTransactions -> {
                    try {
                        val account = AccountStore.accountById(update.accountId) ?: return@launch
                        val dappChain = account.dappChain(update.operationChain) ?: return@launch
                        val signedMessages = WalletCore.call(
                            SignDappTransfers(
                                dappChain = dappChain,
                                accountId = update.accountId,
                                transactions = update.transactions,
                                options = Options(
                                    password = password,
                                    validUntil = update.validUntil,
                                    vestingAddress = update.vestingAddress,
                                    isLegacyOutput = update.isLegacyOutput
                                )
                            )
                        )
                        WalletCore.call(
                            ConfirmDappRequestSendTransaction(
                                update.promiseId,
                                signedMessages
                            )
                        )
                        notifyDone(true, null)
                    } catch (err: JSWebViewBridge.ApiError) {
                        notifyDone(false, err.parsed)
                    }
                }

                is ApiUpdate.ApiUpdateDappSignData -> {
                    try {
                        val account = AccountStore.accountById(update.accountId) ?: return@launch
                        val dappChain = account.dappChain(update.operationChain) ?: return@launch
                        val signedData = WalletCore.call(
                            ApiMethod.Transfer.SignDappData(
                                dappChain = dappChain,
                                accountId = update.accountId,
                                dappUrl = update.dapp.url!!,
                                payloadToSign = update.payloadToSign,
                                password = password
                            )
                        )
                        WalletCore.call(
                            ApiMethod.DApp.ConfirmDappRequestSignData(
                                update.promiseId,
                                signedData
                            )
                        )
                        notifyDone(true, null)
                    } catch (err: JSWebViewBridge.ApiError) {
                        notifyDone(false, err.parsed)
                    }
                }
            }
        }
    }

    var isConfirmed = false
    fun notifyDone(success: Boolean, err: MBridgeError?) {
        isConfirmed = true
        _eventsFlow.tryEmit(Event.Complete(success, err))
    }

    private fun assert(promiseId: String) {
        if (update.promiseId != promiseId) {
            // Theoretically unreachable code. Just for safety.
            throw IllegalStateException("PromiseId do not match")
        }
    }

    sealed class Event {
        data object Close : Event()
        data class Complete(
            val success: Boolean,
            val err: MBridgeError?
        ) : Event()

        data class ShowWarningAlert(
            val title: String,
            val text: CharSequence,
            val allowLinkInText: Boolean = false
        ) : Event()

        data class OpenDappInBrowser(val url: String) : Event()
    }

    private val _eventsFlow =
        MutableSharedFlow<Event>(replay = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val eventsFlow = _eventsFlow.asSharedFlow()

    private fun buildUiItems(tokens: Tokens): List<BaseListItem> {
        val uiItems = mutableListOf(
            TonConnectItem.SendRequestHeader(update, {
                val warningText = DappWarningPopupHelpers.reopenInIabWarningText {
                    WalletCore.call(
                        ApiMethod.DApp.DeleteDapp(
                            update.accountId,
                            update.dapp.sse?.appClientId ?: "",
                            update.dapp.url ?: ""
                        ), callback = { _, _ ->
                            WalletCore.notifyEvent(WalletEvent.DappRemoved(update.dapp))
                            WalletCore.requestDAppList()
                        }
                    )
                    update.dapp.url?.let { url ->
                        _eventsFlow.tryEmit(Event.OpenDappInBrowser(url))
                    }
                }

                _eventsFlow.tryEmit(
                    Event.ShowWarningAlert(
                        LocaleController.getString("Warning"),
                        warningText,
                        allowLinkInText = true
                    )
                )
            }),
            Item.Gap
        )

        when (update) {
            is ApiUpdate.ApiUpdateDappSendTransactions -> {
                if (update.shouldHideTransfers != true) {
                    if (update.transactions.size == 1) {
                        uiItems.addAll(
                            buildUiItemsSingleTransaction(
                                update.operationChain,
                                update.transactions[0],
                                tokens,
                                0,
                                false
                            )
                        )
                    } else {
                        uiItems.addAll(buildUiItemsListTransactions(update, tokens))
                    }

                    uiItems.addAll(
                        listOf(
                            Item.Gap
                        )
                    )
                }

                update.emulation?.activities?.let { previewActivities ->
                    val isMultichain = WGlobalStorage.isMultichain(update.accountId)
                    val previewTitle = SpannableStringBuilder()
                    previewTitle.append(LocaleController.getString("Preview"))
                    previewTitle.append("\u00A0")
                    ContextCompat.getDrawable(
                        ApplicationContextHolder.applicationContext,
                        org.mytonwallet.app_air.walletcontext.R.drawable.ic_warning
                    )?.let { drawable ->
                        val width = 14.dp
                        val height = 26.dp
                        drawable.setBounds(0, 0, width, height)
                        val imageSpan = VerticalImageSpan(drawable)
                        val start = previewTitle.length
                        previewTitle.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)

                        val clickableSpan = object : ClickableSpan() {
                            override fun onClick(widget: View) {
                                _eventsFlow.tryEmit(
                                    Event.ShowWarningAlert(
                                        LocaleController.getString("Warning"),
                                        LocaleController.getString("\$preview_not_guaranteed")
                                            .toProcessedSpannableStringBuilder()
                                    )
                                )
                            }
                        }
                        previewTitle.setSpan(
                            clickableSpan,
                            start,
                            previewTitle.length,
                            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                        )
                    }

                    val tonToken = TokenStore.getToken(MBlockchain.valueOf(update.operationChain).nativeSlug)
                    var feeValue: CharSequence? = null
                    tonToken?.let {
                        val realFee = update.emulation?.realFee
                        realFee?.let {
                            if (realFee != BigInteger.ZERO)
                                feeValue = LocaleController.getStringWithKeyValues(
                                    "\$fee_value_with_colon",
                                    listOf(
                                        Pair(
                                            "%fee%", "**~" + realFee.toString(
                                                tonToken.decimals,
                                                tonToken.symbol,
                                                realFee.smartDecimalsCount(tonToken.decimals),
                                                false,
                                                forceCurrencyToRight = true,
                                                roundUp = true
                                            ) + "**"
                                        )
                                    )
                                )
                        }
                    }
                    uiItems.add(
                        Item.ListTitleValue(
                            previewTitle,
                            feeValue?.toProcessedSpannableStringBuilder()
                        )
                    )

                    previewActivities.forEachIndexed { index, activity ->
                        uiItems.add(
                            Item.Activity(
                                activity = activity.apply {
                                    isEmulation = true
                                },
                                isMultichain = isMultichain,
                                accountId = AccountStore.activeAccountId!!,
                                isFirst = index == 0,
                                isLast = index == previewActivities.lastIndex
                            )
                        )
                    }
                }

                if (update.emulation?.activities.isNullOrEmpty()) {
                    uiItems.add(
                        Item.ListText(
                            title = LocaleController.getString("Preview is currently unavailable."),
                            paddingDp = RectF(16f, 24f, 16f, 24f),
                            Gravity.CENTER,
                            font = WFont.Regular.typeface,
                            textColor = WColor.SecondaryText,
                            textSize = 14f
                        )
                    )
                }
            }

            is ApiUpdate.ApiUpdateDappSignData -> {
                when (update.payloadToSign) {
                    is MSignDataPayload.SignDataPayloadBinary -> {
                        uiItems.addAll(
                            listOf(
                                Item.ListTitle(
                                    LocaleController.getString(
                                        "Binary Data"
                                    ),
                                    topRounding = HeaderCell.TopRounding.NORMAL
                                ),
                                Item.CopyableText(
                                    ((update.payloadToSign as MSignDataPayload.SignDataPayloadBinary).bytes),
                                    "Binary Data",
                                    LocaleController.getString("Data Copied")
                                ),
                                Item.Gap,
                                Item.Alert(LocaleController.getString("The binary data content is unclear. Sign it only if you trust the service."))
                            )
                        )
                    }

                    is MSignDataPayload.SignDataPayloadCell -> {
                        uiItems.addAll(
                            listOf(
                                Item.ListTitle(
                                    LocaleController.getString(
                                        "Cell Schema"
                                    ),
                                    topRounding = HeaderCell.TopRounding.NORMAL
                                ),
                                Item.CopyableText(
                                    (update.payloadToSign as MSignDataPayload.SignDataPayloadCell).schema,
                                    "Cell Schema",
                                    LocaleController.getString("Data Copied")
                                ),
                                Item.Gap,
                                Item.ListTitle(
                                    LocaleController.getString(
                                        "Cell Data"
                                    ),
                                    topRounding = HeaderCell.TopRounding.NORMAL
                                ),
                                Item.CopyableText(
                                    (update.payloadToSign as MSignDataPayload.SignDataPayloadCell).cell,
                                    "Cell Data",
                                    LocaleController.getString("Data Copied")
                                ),
                                Item.Gap,
                                Item.Alert(LocaleController.getString("The binary data content is unclear. Sign it only if you trust the service."))
                            )
                        )
                    }

                    is MSignDataPayload.SignDataPayloadText -> {
                        uiItems.addAll(
                            listOf(
                                Item.ListTitle(
                                    LocaleController.getString(
                                        "Message"
                                    ),
                                    topRounding = HeaderCell.TopRounding.NORMAL
                                ),
                                Item.CopyableText(
                                    ((update.payloadToSign as MSignDataPayload.SignDataPayloadText).text),
                                    "Message",
                                    LocaleController.getString("Data Copied")
                                ),
                            )
                        )
                    }
                }
            }
        }

        return uiItems
    }


    @Suppress("UNCHECKED_CAST")
    class Factory(private val update: ApiUpdate.ApiUpdateDappSignRequest) :
        ViewModelProvider.Factory {
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(TonConnectRequestSendViewModel::class.java)) {
                return TonConnectRequestSendViewModel(update) as T
            }
            throw IllegalArgumentException("Unknown ViewModel class")
        }
    }

    companion object {
        private fun formatTransactionAmountString(
            chain: String,
            transaction: ApiDappTransfer,
            tokens: Tokens,
            includeNetworkFee: Boolean
        ): SpannableStringBuilder {
            val tonAmount = transaction.amount +
                if (!includeNetworkFee) BigInteger.ZERO else transaction.networkFee
            val amountBySlug = mutableMapOf<String, BigInteger>()
            val payload = transaction.payload

            if (payload is ApiParsedPayload.ApiTokensTransferPayload ||
                payload is ApiParsedPayload.ApiTokensTransferNonStandardPayload ||
                payload is ApiParsedPayload.ApiTokensBurnPayload
            ) {
                val tokenSlug = payload.payloadTokenSlug
                val tokenAmount = payload.payloadTokenAmount
                if (tokenSlug != null && tokenAmount != null) {
                    amountBySlug[tokenSlug] = tokenAmount
                }
            }

            if (tonAmount != BigInteger.ZERO || amountBySlug.isEmpty()) {
                amountBySlug[MBlockchain.valueOf(chain).nativeSlug] = tonAmount
            }

            if (amountBySlug.isEmpty()) {
                return SpannableStringBuilder()
            }

            val sortedEntries = amountBySlug.entries.sortedBy { (slug, _) ->
                if (TokenStore.getToken(slug)?.isBlockchainNative == true) 0 else 1
            }

            val amountParts = sortedEntries.mapNotNull { (slug, amount) ->
                if (amount == BigInteger.ZERO) return@mapNotNull null

                val token = tokens.tokens?.get(slug) ?: TokenStore.getToken(slug)
                token?.let {
                    CoinUtils.setSpanToSymbolPart(
                        SpannableStringBuilder(amount.toAmountString(it)),
                        WForegroundColorSpan(WColor.SecondaryText)
                    )
                }
            }

            return when {
                amountParts.isEmpty() -> SpannableStringBuilder()
                amountParts.size == 1 -> amountParts[0]
                else -> {
                    val result = SpannableStringBuilder()
                    amountParts.forEachIndexed { index, part ->
                        if (index > 0) {
                            result.append(" + ")
                        }
                        result.append(part)
                    }
                    result
                }
            }
        }

        private fun formatTransactionAmountInBaseCurrencyString(
            transaction: ApiDappTransfer,
            token: Token,
            baseCurrency: MBaseCurrency,
            includeNetworkFee: Boolean,
        ): SpannableStringBuilder? {
            if (token.isUnknown)
                return null

            // Tokens
            val tokenWithPrice = token.token ?: return null
            val nativeToken =
                TokenStore.getToken(tokenWithPrice.mBlockchain?.nativeSlug) ?: return null

            // Token amount
            val tokenAmount = if (transaction.payload?.payloadIsToken == true) {
                transaction.payload?.payloadTokenAmount ?: BigInteger.ZERO
            } else {
                BigInteger.ZERO
            }
            val tokenAmountInBaseCurrency =
                CoinUtils.toBigDecimal(tokenAmount, tokenWithPrice.decimals) *
                    BigDecimal.valueOf(tokenWithPrice.price ?: 0.0)

            val feeAmount =
                if (transaction.payload?.payloadIsToken == true)
                    BigInteger.ZERO
                else
                    (transaction.amount + if (includeNetworkFee) transaction.networkFee else BigInteger.ZERO)
            val feeAmountInBaseCurrency =
                CoinUtils.toBigDecimal(feeAmount, nativeToken.decimals) *
                    BigDecimal.valueOf(nativeToken.price ?: 0.0)

            return nativeToken.let {
                val totalBaseCurrencyAmount = tokenAmountInBaseCurrency + feeAmountInBaseCurrency
                SpannableStringBuilder(
                    CoinUtils.fromDecimal(
                        totalBaseCurrencyAmount,
                        9
                    )?.toString(
                        currency = baseCurrency.sign,
                        decimals = 9,
                        currencyDecimals = totalBaseCurrencyAmount.smartDecimalsCount(),
                        showPositiveSign = false,
                        roundUp = false
                    )
                )
            }
        }

        private fun formatAddressSubtitle(transaction: ApiDappTransfer): SpannableStringBuilder {
            val payload = transaction.payload
            val receivingAddress = when (payload) {
                is ApiParsedPayload.ApiTokensTransferPayload -> payload.destination
                is ApiParsedPayload.ApiTokensTransferNonStandardPayload -> payload.destination
                is ApiParsedPayload.ApiTokensBurnPayload -> payload.address
                is ApiParsedPayload.ApiNftTransferPayload -> payload.newOwner
                else -> transaction.toAddress
            }
            return SpannableStringBuilder(
                LocaleController.getString("to") + " " + receivingAddress.formatStartEndAddress()
            ).apply {
                styleDots()
            }
        }

        private fun formatTokenDetails(
            totalPerToken: Map<String, BigInteger>,
            tokens: Tokens
        ): String {
            if (totalPerToken.isEmpty()) return ""

            val sortedEntries = totalPerToken.entries.sortedBy { (slug, _) ->
                if (TokenStore.getToken(slug)?.isBlockchainNative == true) 0 else 1
            }

            val tokenDetails = sortedEntries.mapNotNull { (slug, amount) ->
                val token = tokens.tokens?.get(slug) ?: TokenStore.getToken(slug)
                token?.let {
                    amount.toString(
                        decimals = it.decimals,
                        currency = it.symbol ?: "",
                        currencyDecimals = amount.smartDecimalsCount(it.decimals),
                        showPositiveSign = false,
                        roundUp = false
                    )
                }
            }.joinToString(" + ")

            return if (tokenDetails.isNotEmpty()) " ($tokenDetails)" else ""
        }

        private fun formatCurrencyAmount(
            currencySign: String,
            amount: String,
            details: String
        ): SpannableStringBuilder {
            return SpannableStringBuilder().apply {
                val signStart = length
                append(currencySign)
                setSpan(
                    WForegroundColorSpan(WColor.SecondaryText),
                    signStart,
                    length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                setSpan(
                    AbsoluteSizeSpan(16, true),
                    signStart,
                    length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )

                val decimalIndex = amount.indexOf('.')

                if (decimalIndex != -1) {
                    val integerStart = length
                    append(amount.substring(0, decimalIndex))
                    setSpan(
                        AbsoluteSizeSpan(22, true),
                        integerStart,
                        length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )

                    val decimalStart = length
                    append(amount.substring(decimalIndex))
                    setSpan(
                        AbsoluteSizeSpan(16, true),
                        decimalStart,
                        length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                } else {
                    val amountStart = length
                    append(amount)
                    setSpan(
                        AbsoluteSizeSpan(22, true),
                        amountStart,
                        length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }

                if (details.isNotEmpty()) {
                    val detailStart = length
                    append(details)
                    setSpan(
                        WForegroundColorSpan(WColor.SecondaryText),
                        detailStart,
                        length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                    setSpan(
                        AbsoluteSizeSpan(16, true),
                        detailStart,
                        length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
            }
        }

        private fun buildUiItemsListTransactions(
            update: ApiUpdate.ApiUpdateDappSendTransactions,
            tokens: Tokens
        ): List<BaseListItem> {
            val uiItems = mutableListOf<BaseListItem>()
            uiItems.add(
                Item.ListTitle(
                    LocaleController.getPlural(update.transactions.size, "transfer"),
                    topRounding = HeaderCell.TopRounding.NORMAL
                )
            )

            var totalPrice = BigDecimal.ZERO
            val totalPerToken = emptyMap<String, BigInteger>().toMutableMap()

            for (a in 0..<update.transactions.size) {
                val transaction = update.transactions[a]
                val token = tokens.list[a]
                val nativeToken = tokens.tokens?.get(token.token?.mBlockchain?.nativeSlug)
                val tokenIcon = token.icon
                val payload = transaction.payload

                val amount = if (payload?.payloadIsToken == true && !token.isUnknown) {
                    transaction.payload?.payloadTokenAmount ?: BigInteger.ZERO
                } else transaction.amount

                val totalFee = transaction.networkFee + if (payload?.payloadIsToken == true) {
                    transaction.amount
                } else BigInteger.ZERO

                token.token?.let { token ->
                    totalPerToken[token.slug] =
                        (totalPerToken[token.slug] ?: BigInteger.ZERO) + amount
                    totalPrice += amount.toBigDecimal(token.decimals) * BigDecimal.valueOf(
                        token.price ?: 0.0
                    )
                }
                nativeToken?.let { nativeToken ->
                    totalPerToken[nativeToken.slug] =
                        (totalPerToken[nativeToken.slug] ?: BigInteger.ZERO) + totalFee
                    totalPrice += totalFee.toBigDecimal(nativeToken.decimals) * BigDecimal.valueOf(
                        nativeToken.price ?: 0.0
                    )
                }

                /*if (fee > BigInteger.ZERO) {
                    subtitle.append(" (")
                    subtitle.append(
                        DappFeeHelpers.Companion.calculateDappTransferFee(
                            transaction.networkFee,
                            BigInteger.ZERO
                        ),
                    )
                    subtitle.append(')')
                }*/

                uiItems.add(
                    Item.IconDualLine(
                        image = tokenIcon,
                        title = formatTransactionAmountString(update.operationChain, transaction, tokens, true),
                        subtitle = formatAddressSubtitle(transaction),
                        clickable = Item.Clickable.Items(
                            buildUiItemsSingleTransaction(
                                update.operationChain,
                                transaction,
                                tokens,
                                a,
                                true
                            )
                        ),
                    )
                )
            }

            // Total amount row
            val totalCurrencyFmt = SpannableStringBuilder(
                CoinUtils.fromDecimal(totalPrice, 9)?.let {
                    it.toString(
                        currency = "",
                        decimals = 9,
                        currencyDecimals = it.smartDecimalsCount(9),
                        showPositiveSign = false,
                        roundUp = false
                    )
                } ?: "")
            val detailed = formatTokenDetails(totalPerToken, tokens)

            uiItems.addAll(
                0,
                listOf(
                    Item.ListTitle(
                        LocaleController.getFormattedString(
                            "Total Amount",
                            listOf(tokens.currency.currencySymbol)
                        ),
                        topRounding = HeaderCell.TopRounding.NORMAL
                    ),
                    TonConnectItem.CurrencyAmount(
                        formatCurrencyAmount(
                            tokens.currency.sign,
                            totalCurrencyFmt.toString(),
                            detailed
                        )
                    ),
                    Item.Gap,
                )
            )

            return uiItems
        }

        private fun buildUiItemsSingleTransaction(
            chain: String,
            transaction: ApiDappTransfer,
            tokens: Tokens,
            index: Int,
            isDetailView: Boolean
        ): List<BaseListItem> {
            val token = tokens.list[index]
            val uiItems = mutableListOf<BaseListItem>()
            val tokenIcon = token.icon
            val nativeToken = TokenStore.getToken(token.token?.mBlockchain?.nativeSlug ?: TONCOIN_SLUG)

            val payload = transaction.payload
            val receivingAddress = when (payload) {
                is ApiParsedPayload.ApiTokensTransferPayload -> payload.destination
                is ApiParsedPayload.ApiTokensTransferNonStandardPayload -> payload.destination
                is ApiParsedPayload.ApiTokensBurnPayload -> payload.address
                is ApiParsedPayload.ApiNftTransferPayload -> payload.newOwner
                else -> transaction.toAddress
            }

            uiItems.addAll(
                listOf(
                    Item.ListTitle(
                        LocaleController.getString("Receiving Address"),
                        topRounding = HeaderCell.TopRounding.NORMAL
                    ),
                    Item.CopyableText(
                        receivingAddress,
                        "Address",
                        LocaleController.getString("%chain% Address Copied")
                            .replace("%chain%", try { MBlockchain.valueOf(chain).displayName } catch (_: Throwable) { chain })
                    ),
                    Item.Gap
                )
            )

            if (payload?.payloadIsNft == true) {
                uiItems.addAll(
                    listOf(
                        Item.ListTitle(
                            LocaleController.getString("NFT"),
                            topRounding = HeaderCell.TopRounding.NORMAL
                        ),
                        Item.IconDualLine(
                            title = transaction.payload?.payloadNft?.name,
                            subtitle = DappFeeHelpers.calculateDappTransferFee(
                                chain,
                                transaction.networkFee,
                                BigInteger.ZERO
                            ),
                            image = Content(
                                image = Content.Image.Url(
                                    transaction.payload?.payloadNft?.image ?: ""
                                ),
                                rounding = Content.Rounding.Radius(8f.dp)
                            )
                        ),
                    )
                )
            } else {
                uiItems.addAll(
                    listOfNotNull(
                        Item.ListTitle(
                            LocaleController.getString("Amount"),
                            topRounding = HeaderCell.TopRounding.NORMAL
                        ),
                        Item.IconDualLine(
                            title = formatTransactionAmountString(
                                chain,
                                transaction,
                                tokens,
                                !isDetailView && transaction.payload?.payloadIsToken != true
                            ),
                            subtitle = formatTransactionAmountInBaseCurrencyString(
                                transaction,
                                token,
                                tokens.currency,
                                !isDetailView && transaction.payload?.payloadIsToken != true
                            ),
                            image = tokenIcon,
                        ),
                    )
                )
                if (isDetailView) {
                    uiItems.addAll(
                        listOf(
                            Item.Gap,
                            Item.ListTitle(
                                LocaleController.getString("Fee"),
                                topRounding = HeaderCell.TopRounding.NORMAL
                            ),
                            Item.IconDualLine(
                                title = nativeToken?.let {
                                    CoinUtils.setSpanToSymbolPart(
                                        SpannableStringBuilder(
                                            transaction.networkFee.toAmountString(
                                                nativeToken
                                            )
                                        ),
                                        WForegroundColorSpan(WColor.SecondaryText)
                                    )
                                },
                                subtitle = SpannableStringBuilder(
                                    CoinUtils.fromDecimal(
                                        CoinUtils.toBigDecimal(transaction.networkFee, 9) *
                                            BigDecimal.valueOf(nativeToken?.price ?: 0.0),
                                        9
                                    )?.toString(
                                        currency = tokens.currency.sign,
                                        decimals = 9,
                                        currencyDecimals = transaction.networkFee.smartDecimalsCount(
                                            9
                                        ),
                                        showPositiveSign = false,
                                        roundUp = false
                                    )
                                ),
                                image = null,
                            ),
                        )
                    )
                }
            }

            val comment = payload?.payloadComment
            comment?.let { text ->
                uiItems.addAll(
                    listOf(
                        Item.Gap,
                        Item.ListTitle(
                            LocaleController.getString("Comment"),
                            topRounding = HeaderCell.TopRounding.NORMAL
                        ),
                        Item.CopyableText(
                            text,
                            "Comment",
                            LocaleController.getString("Comment Copied")
                        ),
                    )
                )
            }

            if (payload !is ApiParsedPayload.ApiCommentPayload) {
                transaction.rawPayload?.let { base64 ->
                    uiItems.addAll(
                        listOf(
                            Item.Gap,
                            Item.ListTitle(
                                LocaleController.getString("Payload"),
                                topRounding = HeaderCell.TopRounding.NORMAL
                            ),
                            Item.ExpandableText(base64),
                        )
                    )
                }
            }

            if (transaction.isDangerous) {
                uiItems.addAll(
                    listOf(
                        Item.Gap,
                        Item.Alert(
                            LocaleController.getString("\$hardware_payload_warning")
                                .toProcessedSpannableStringBuilder()
                        ),
                    )
                )
            }

            return uiItems
        }
    }
}
