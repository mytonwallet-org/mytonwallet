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
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.FakeLoading
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.TonConnectItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.helpers.DappFeeHelpers
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.ApiDappTransfer
import org.mytonwallet.app_air.walletcore.moshi.ApiParsedPayload
import org.mytonwallet.app_air.walletcore.moshi.ApiTokenWithPrice
import org.mytonwallet.app_air.walletcore.moshi.ApiTransferToSign
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.app_air.walletcore.toAmountString
import java.math.BigDecimal
import java.math.BigInteger

class TonConnectRequestSendViewModel private constructor(
    private val update: ApiUpdate.ApiUpdateDappSendTransactions
) : ViewModel() {
    private val transactionTokenSlugs =
        update.transactions.map { it.payload?.payloadTokenSlug ?: "toncoin" }
    private val tokensMapFlow = TokenStore.tokensFlow.map { tokens ->
        Tokens(
            currency = WalletCore.baseCurrency!!,
            tokens = tokens?.tokens,
            list = transactionTokenSlugs.map {
                val t = tokens?.tokens?.get(it)
                Token(
                    slug = it,
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
        val icon = token?.let { Content.Companion.of(it) }
            ?: (if (slug == "toncoin" || isUnknown) Content.Companion.chain(MBlockchain.ton) else null)
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
            try {
                val signedMessages = WalletCore.call(
                    ApiMethod.Transfer.SignTransfers(
                        accountId = update.accountId,
                        transactions = update.transactions.map {
                            ApiTransferToSign(
                                toAddress = it.toAddress,
                                amount = it.amount,
                                rawPayload = it.rawPayload,
                                payload = it.payload,
                                stateInit = it.stateInit
                            )
                        },
                        options = ApiMethod.Transfer.SignTransfers.Options(
                            password = password,
                            validUntil = update.validUntil,
                            vestingAddress = update.vestingAddress
                        )
                    )
                )
                WalletCore.call(
                    ApiMethod.DApp.ConfirmDappRequestSendTransaction(
                        update.promiseId,
                        signedMessages
                    )
                )
                notifyDone(true, null)
            } catch (err: JSWebViewBridge.ApiError) {
                notifyDone(false, err.parsed)
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
                val warningText = SpannableStringBuilder()
                val template =
                    LocaleController.getString("For your safety, please re-open this dapp in %browserButton%.")
                val browserButtonText = LocaleController.getString("MyTonWallet Browser")
                val browserButtonPlaceholder = "%browserButton%"

                val placeholderStart = template.indexOf(browserButtonPlaceholder)
                if (placeholderStart != -1) {
                    warningText.append(template.substring(0, placeholderStart))

                    val buttonStart = warningText.length
                    warningText.append(browserButtonText)
                    val buttonEnd = warningText.length

                    val clickableSpan = WClickableSpan(update.dapp.url ?: "", onClick = {
                        update.dapp.url?.let { url ->
                            _eventsFlow.tryEmit(Event.OpenDappInBrowser(url))
                        }
                    })
                    warningText.setSpan(
                        clickableSpan,
                        buttonStart,
                        buttonEnd,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )

                    val placeholderEnd = placeholderStart + browserButtonPlaceholder.length
                    if (placeholderEnd < template.length) {
                        warningText.append(template.substring(placeholderEnd))
                    }
                } else {
                    warningText.append(template)
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

        if (update.transactions.size == 1) {
            uiItems.addAll(
                buildUiItemsSingleTransaction(
                    //update,
                    update.transactions[0],
                    tokens,
                    0
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

        update.emulation?.activities?.let { previewActivities ->
            val previewTitle = SpannableStringBuilder()
            previewTitle.append(LocaleController.getString("Preview"))
            previewTitle.append(" ")
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

            val tonToken = TokenStore.getToken(TONCOIN_SLUG)
            var feeValue: CharSequence? = null
            tonToken?.let {
                val realFee = update.emulation?.realFee
                realFee?.let {
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
                        isFirst = index == 0,
                        isLast = index == previewActivities.lastIndex
                    )
                )
            }
        }

        if (update.emulation?.activities.isNullOrEmpty()) {
            uiItems.add(
                Item.ListTitle(
                    title = LocaleController.getString("Preview is currently unavailable."),
                    paddingDp = RectF(16f, 24f, 16f, 24f),
                    Gravity.CENTER,
                    font = WFont.Regular.typeface,
                    textColor = WColor.SecondaryText,
                    textSize = 14f
                )
            )
        }

        return uiItems
    }


    @Suppress("UNCHECKED_CAST")
    class Factory(private val update: ApiUpdate.ApiUpdateDappSendTransactions) :
        ViewModelProvider.Factory {
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(TonConnectRequestSendViewModel::class.java)) {
                return TonConnectRequestSendViewModel(update) as T
            }
            throw IllegalArgumentException("Unknown ViewModel class")
        }
    }

    companion object {
        private fun formatTokenDetails(
            totalPerToken: Map<String, BigInteger>,
            tokens: Tokens
        ): String {
            if (totalPerToken.isEmpty()) return ""

            val sortedEntries = totalPerToken.entries.sortedBy { (slug, _) ->
                when (slug) {
                    TONCOIN_SLUG -> 0 // TON comes first
                    else -> 1 // Other tokens after TON
                }
            }

            val tokenDetails = sortedEntries.mapNotNull { (slug, amount) ->
                val token = tokens.tokens?.get(slug) ?: TokenStore.getToken(slug)
                token?.let {
                    amount.toString(
                        it.decimals,
                        it.symbol ?: "",
                        amount.smartDecimalsCount(it.decimals),
                        false
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
                    LocaleController.getPlural(update.transactions.size, "transfer")
                )
            )

            var price = BigDecimal.ZERO
            val totalPerToken = emptyMap<String, BigInteger>().toMutableMap()

            for (a in 0..<update.transactions.size) {
                val transaction = update.transactions[a]
                val token = tokens.list[a]
                val nativeToken = tokens.tokens?.get(token.token?.mBlockchain?.nativeSlug)
                val tokenIcon = token.icon
                val tokenToShow = if (token.isUnknown) {
                    TokenStore.swapAssetsMap?.get("toncoin")
                } else {
                    token.token
                }
                val payload = transaction.payload

                val receivingAddress = when (payload) {
                    is ApiParsedPayload.ApiTokensTransferPayload -> payload.destination
                    is ApiParsedPayload.ApiTokensTransferNonStandardPayload -> payload.destination
                    is ApiParsedPayload.ApiTokensBurnPayload -> payload.address
                    is ApiParsedPayload.ApiNftTransferPayload -> payload.newOwner
                    else -> transaction.toAddress
                }

                val amount = if (payload?.payloadIsToken == true && !token.isUnknown) {
                    transaction.payload?.payloadTokenAmount ?: BigInteger.ZERO
                } else transaction.amount

                val fee = if (payload?.payloadIsToken == true && !token.isUnknown) {
                    transaction.amount
                } else BigInteger.ZERO

                token.token?.let { t ->
                    totalPerToken[token.token.slug] =
                        (totalPerToken[token.token.slug] ?: BigInteger.ZERO) + amount
                    price += amount.toBigDecimal(t.decimals) * BigDecimal.valueOf(
                        t.price ?: 0.0
                    )
                }
                nativeToken?.let { t ->
                    totalPerToken[nativeToken.slug] =
                        (totalPerToken[nativeToken.slug] ?: BigInteger.ZERO) + fee
                    price += fee.toBigDecimal(t.decimals) * BigDecimal.valueOf(
                        t.price ?: 0.0
                    )
                }

                val subtitle = SpannableStringBuilder(
                    LocaleController.getString("to") + " " + receivingAddress.formatStartEndAddress()
                ).apply {
                    updateDotsTypeface()
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
                        title = tokenToShow?.let {
                            CoinUtils.setSpanToSymbolPart(
                                SpannableStringBuilder(amount.toAmountString(it)),
                                WForegroundColorSpan(WColor.SecondaryText)
                            )
                        },
                        subtitle = subtitle,
                        clickable = Item.Clickable.Items(
                            buildUiItemsSingleTransaction(
                                //update,
                                transaction,
                                tokens,
                                a
                            )
                        ),
                        allowSeparator = a != update.transactions.lastIndex
                    )
                )
            }

            // Total amount row
            val totalCurrencyFmt = SpannableStringBuilder(
                CoinUtils.fromDecimal(price, tokens.currency.decimalsCount)?.let {
                    it.toString(
                        currency = "",
                        decimals = tokens.currency.decimalsCount,
                        currencyDecimals = it.smartDecimalsCount(tokens.currency.decimalsCount),
                        showPositiveSign = false
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
                        )
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
            transaction: ApiDappTransfer,
            tokens: Tokens,
            index: Int
        ): List<BaseListItem> {
            val token = tokens.list[index]
            val uiItems = mutableListOf<BaseListItem>()
            val tokenIcon = token.icon
            val tokenToShow = if (token.isUnknown) {
                TokenStore.swapAssetsMap?.get(TONCOIN_SLUG)
            } else {
                token.token
            }

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
                    Item.ListTitle(LocaleController.getString("Receiving Address")),
                    Item.Address(receivingAddress),
                    Item.Gap
                )
            )

            if (payload?.payloadIsNft == true) {
                uiItems.addAll(
                    listOf(
                        Item.ListTitle(LocaleController.getString("NFT")),
                        Item.IconDualLine(
                            title = transaction.payload?.payloadNft?.name,
                            subtitle = DappFeeHelpers.Companion.calculateDappTransferFee(
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
            } else if (payload?.payloadIsToken == true) {
                val amount = if (token.isUnknown) {
                    transaction.amount
                } else {
                    transaction.payload?.payloadTokenAmount ?: BigInteger.ZERO
                }

                uiItems.addAll(
                    listOf(
                        Item.ListTitle(LocaleController.getString("Amount")),
                        Item.IconDualLine(
                            title = tokenToShow?.let {
                                CoinUtils.setSpanToSymbolPart(
                                    SpannableStringBuilder(amount.toAmountString(it)),
                                    WForegroundColorSpan(WColor.SecondaryText)
                                )
                            },
                            subtitle = DappFeeHelpers.Companion.calculateDappTransferFee(
                                transaction.networkFee,
                                BigInteger.ZERO
                            ),
                            image = tokenIcon,
                        ),
                    )
                )
            } else {
                val amount = transaction.amount

                uiItems.addAll(
                    listOf(
                        Item.ListTitle(LocaleController.getString("Amount")),
                        Item.IconDualLine(
                            title = tokenToShow?.let {
                                CoinUtils.setSpanToSymbolPart(
                                    SpannableStringBuilder(amount.toAmountString(it)),
                                    WForegroundColorSpan(WColor.SecondaryText)
                                )
                            },
                            subtitle = DappFeeHelpers.Companion.calculateDappTransferFee(
                                transaction.networkFee,
                                BigInteger.ZERO
                            ),
                            image = tokenIcon,
                        ),
                    )
                )
            }

            val comment = payload?.payloadComment
            comment?.let { text ->
                uiItems.addAll(
                    listOf(
                        Item.Gap,
                        Item.ListTitle(LocaleController.getString("Comment")),
                        Item.Address(text),
                    )
                )
            }

            if (payload !is ApiParsedPayload.ApiCommentPayload) {
                transaction.rawPayload?.let { base64 ->
                    uiItems.addAll(
                        listOf(
                            Item.Gap,
                            Item.ListTitle(LocaleController.getString("Payload")),
                            Item.ExpandableText(base64),
                        )
                    )
                }
            }

            return uiItems
        }
    }
}
