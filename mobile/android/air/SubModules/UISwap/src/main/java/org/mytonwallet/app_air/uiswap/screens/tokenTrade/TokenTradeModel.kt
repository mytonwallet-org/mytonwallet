package org.mytonwallet.app_air.uiswap.screens.tokenTrade

import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import kotlinx.coroutines.CancellationException
import org.mytonwallet.app_air.uisend.send.SellWithCardLauncher
import org.mytonwallet.app_air.uiswap.screens.swap.SwapViewModel
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapEstimateResponse
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapUiInputState
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexEstimateResponse
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.OnRampCurrencyPolicy
import org.mytonwallet.app_air.walletcore.stores.TokenStore

enum class TokenTradeDirection { BUY, SELL }

/** Buy/Sell state of one token layered on the shared swap quote pipeline. */
class TokenTradeModel(
    private val swap: SwapViewModel,
    val direction: TokenTradeDirection,
    val token: IApiToken
) {
    data class CardMaximumRequest(val accountId: String, val balance: BigInteger)

    var input = TokenTradeAmountInput()
        private set
    var isTokenAmount = tokenPriceUsd <= 0
        private set
    var cardCurrency: MBaseCurrency? = null
        private set
    private var cardMaximum: BigInteger? = null
    private var cardMaximumError: String? = null
    private var retainedTokenAmount: BigInteger? = null

    var swapState: SwapUiInputState? = null
        private set
    private var estimate: SwapEstimateResponse? = null
    private var status: SwapViewModel.UiStatus? = null

    val isBuying: Boolean
        get() = direction == TokenTradeDirection.BUY

    private val account: MAccount?
        get() = AccountStore.activeAccount

    private val tokenPriceUsd: Double
        get() = TokenStore.getToken(token.slug)?.priceUsd?.takeIf { it.isFinite() } ?: 0.0

    val paymentToken: IApiToken?
        get() = if (isBuying) swapState?.tokenToSend else swapState?.tokenToReceive

    val currency: MBaseCurrency
        get() = cardCurrency ?: WalletCore.baseCurrency

    val price: Double
        get() = tokenPriceUsd * (TokenStore.currencyRates?.get(currency.currencyCode) ?: 0.0)

    val inputDecimals: Int
        get() = if (isTokenAmount) token.decimals else currency.decimalsCount

    val hasAmount: Boolean
        get() = input.amount(inputDecimals) > BigInteger.ZERO

    val typedTokenAmount: BigInteger
        get() {
            retainedTokenAmount?.let { return it }
            if (isTokenAmount) return input.amount(token.decimals)
            return fiatToToken(input.amount(inputDecimals))
        }

    private val matchingEstimate: SwapEstimateResponse?
        get() {
            val state = swapState ?: return null
            return estimate?.takeIf {
                it.request.tokenToSend.slug == state.tokenToSend?.slug &&
                    it.request.tokenToReceive.slug == state.tokenToReceive?.slug
            }
        }

    val displayedTokenAmount: BigInteger
        get() {
            if (isBuying && cardCurrency == null) {
                matchingEstimate?.toAmount?.takeIf { it > BigInteger.ZERO }?.let { return it }
            }
            return typedTokenAmount
        }

    val conversionText: String
        get() {
            if (isTokenAmount) {
                return tokenToFiat(typedTokenAmount).toString(
                    decimals = currency.decimalsCount,
                    currency = currency.sign,
                    currencyDecimals = currency.decimalsCount,
                    showPositiveSign = false
                )
            }
            val amount = displayedTokenAmount
            return amount.toString(
                decimals = token.decimals,
                currency = token.symbol ?: "",
                currencyDecimals = amount.smartDecimalsCount(token.decimals),
                showPositiveSign = false,
                roundUp = false
            )
        }

    val availableCardCurrencies: List<MBaseCurrency>
        get() {
            val account = account ?: return emptyList()
            val chain = token.mBlockchain ?: return emptyList()
            if (!account.supportsBuyWithCard || account.isHardware ||
                ConfigStore.isLimited == true ||
                !account.isChainSupported(chain.name) || !token.isBlockchainNative
            ) {
                return emptyList()
            }
            if (isBuying) {
                if (!chain.isOnrampSupported) return emptyList()
                return OnRampCurrencyPolicy.supportedCurrencies(chain.name)
            }
            if (!chain.isOfframpSupported) return emptyList()
            return SellWithCardLauncher.supportedCurrencies()
        }

    val maximumTokenAmount: BigInteger?
        get() {
            if (cardCurrency != null) return if (isBuying) null else cardMaximum
            val selling = swapState?.tokenToSend ?: return null
            val maximum = swap.tokenToSendMaxBalance
            if (!isBuying) return maximum
            return convert(maximum, selling, token)
        }

    private val feeEstimate: SwapEstimateResponse?
        get() = if (cardCurrency != null || !hasAmount) null else matchingEstimate

    /** The fee as the card and menu show it, e.g. "~0.0037 GRAM". */
    private val feeAmountText: String?
        get() = feeEstimate?.transactionFeeFmt2

    /** USD value of the shown fee, or null while a price it depends on is unknown. */
    private val feeUsd: Double?
        get() {
            val estimate = feeEstimate ?: return null
            val explainedFee = estimate.explainedFee
            val fee = (
                if (estimate.hasInsufficientFeeError) {
                    explainedFee.fullFee
                } else {
                    explainedFee.realFee ?: explainedFee.fullFee
                }
                ) ?: return null
            val sending = estimate.request.tokenToSend
            val nativeAmount = fee.networkTerms?.native?.takeIf { it > BigInteger.ZERO }
                ?: fee.terms.native ?: BigInteger.ZERO
            var usd = valueUsd(nativeAmount, sending.nativeToken ?: return null) ?: return null
            if (explainedFee.isGasless) {
                usd += valueUsd(fee.terms.token ?: BigInteger.ZERO, sending) ?: return null
            }
            return usd
        }

    /** Fees below SMALL_FEE_USD move from the amount card to the settings menu. */
    private val isFeeInMenu: Boolean
        get() = (feeUsd ?: return false) < SMALL_FEE_USD

    val feeText: String?
        get() {
            if (isFeeInMenu) return null
            val fee = feeAmountText ?: return null
            val label = LocaleController.getString("Fee")
            return when {
                fee.startsWith("<") -> "$label $fee"
                fee.startsWith("~") -> "$label ~ ${fee.drop(1)}"
                else -> "$label ~ $fee"
            }
        }

    val menuFeeText: String?
        get() = if (isFeeInMenu) feeAmountText else null

    val methodAmountText: String?
        get() {
            if (!hasAmount) return null
            if (cardCurrency != null) {
                return tokenToFiat(typedTokenAmount).toString(
                    decimals = currency.decimalsCount,
                    currency = "",
                    currencyDecimals = currency.decimalsCount,
                    showPositiveSign = false
                ).trim()
            }
            val estimate = matchingEstimate ?: return null
            val payment = paymentToken ?: return null
            val amount = (if (isBuying) estimate.fromAmount else estimate.toAmount)
                ?.takeIf { it > BigInteger.ZERO } ?: return null
            return amount.toString(
                decimals = payment.decimals,
                currency = "",
                currencyDecimals = amount.smartDecimalsCount(payment.decimals),
                showPositiveSign = false,
                roundUp = false
            ).trim()
        }

    val methodSymbol: String
        get() = cardCurrency?.currencyCode ?: paymentToken?.symbol
            ?: LocaleController.getString("Select Token")

    val isMethodAmountStale: Boolean
        get() {
            if (cardCurrency != null) return false
            val status = status ?: return false
            return if (isBuying) status.tokenToSend.isLoading else status.tokenToReceive.isLoading
        }

    val isConversionAmountStale: Boolean
        get() = isBuying && !isTokenAmount && cardCurrency == null && hasAmount &&
            status?.tokenToReceive?.isLoading == true

    val isLoading: Boolean
        get() = cardCurrency == null && status?.button?.status?.isLoading == true

    val actionTitle: String
        get() {
            val symbol = token.symbol ?: ""
            val cardCurrency = cardCurrency
            if (cardCurrency == null) {
                val button = status?.button
                if (button != null && button.title.isNotEmpty() &&
                    button.status != SwapViewModel.ButtonStatus.Ready &&
                    button.status != SwapViewModel.ButtonStatus.Loading
                ) {
                    return button.title
                }
                return if (isBuying) {
                    LocaleController.getStringWithKeyValues(
                        "Buy %token%",
                        listOf("%token%" to symbol)
                    )
                } else {
                    LocaleController.getStringWithKeyValues(
                        "Sell %symbol%",
                        listOf("%symbol%" to symbol)
                    )
                }
            }
            if (!isBuying) {
                cardMaximumError?.let { return it }
                val maximum = cardMaximum ?: return LocaleController.getString("Loading...")
                if (typedTokenAmount > maximum) {
                    return LocaleController.getString("Insufficient Balance")
                }
            }
            val provider = if (cardCurrency == MBaseCurrency.RUB) "Dreamwalkers" else "MoonPay"
            return LocaleController.getStringWithKeyValues(
                if (isBuying) "Buy %token% via %provider%" else "Sell %token% via %provider%",
                listOf("%token%" to symbol, "%provider%" to provider)
            )
        }

    val canContinue: Boolean
        get() {
            if (!hasAmount || typedTokenAmount <= BigInteger.ZERO ||
                ConfigStore.isLimited == true
            ) {
                return false
            }
            val cardCurrency = cardCurrency
            if (cardCurrency != null) {
                return availableCardCurrencies.contains(cardCurrency) &&
                    (isBuying || typedTokenAmount <= (cardMaximum ?: BigInteger.ZERO))
            }
            return status?.button?.status?.isEnabled == true
        }

    val rateText: String
        get() {
            val symbol = token.symbol ?: ""
            if (cardCurrency != null) {
                if (price <= 0) return ""
                return "$symbol ≈ " + (
                    price.toString(
                        decimals = currency.decimalsCount,
                        currency = currency.sign,
                        currencyDecimals = currency.decimalsCount,
                        smartDecimals = true
                    ) ?: ""
                    )
            }
            val other = paymentToken ?: return ""
            val estimate = matchingEstimate
            val from = estimate?.fromAmount?.takeIf { it > BigInteger.ZERO }
            val to = estimate?.toAmount?.takeIf { it > BigInteger.ZERO }
            val rate = if (estimate != null && from != null && to != null) {
                val sent = BigDecimal(from, estimate.request.tokenToSend.decimals)
                val received = BigDecimal(to, estimate.request.tokenToReceive.decimals)
                if (isBuying) {
                    sent.divide(received, other.decimals, RoundingMode.HALF_UP)
                } else {
                    received.divide(sent, other.decimals, RoundingMode.HALF_UP)
                }
            } else {
                val otherPrice = priceUsd(other)
                if (otherPrice <= 0 || tokenPriceUsd <= 0) return ""
                BigDecimal.valueOf(tokenPriceUsd)
                    .divide(BigDecimal.valueOf(otherPrice), other.decimals, RoundingMode.HALF_UP)
            }
            val amount = CoinUtils.fromDecimal(rate, other.decimals) ?: return ""
            return "$symbol ≈ " + amount.toString(
                decimals = other.decimals,
                currency = other.symbol ?: "",
                currencyDecimals = amount.smartDecimalsCount(other.decimals),
                showPositiveSign = false
            )
        }

    val priceImpactText: String?
        get() = matchingEstimate?.takeIf { it.dex != null }?.priceImpactFmt

    val minimumReceivedText: String?
        get() = matchingEstimate?.takeIf { it.dex != null || it.toAmount != null }?.minReceivedFmt

    val slippage: Float
        get() = swapState?.slippage ?: 0f

    val isCrossChain: Boolean
        get() = swapState?.isCex == true

    val cexEstimate: MApiSwapCexEstimateResponse?
        get() = matchingEstimate?.cex

    fun update(
        state: SwapUiInputState? = swapState,
        estimate: SwapEstimateResponse? = this.estimate,
        status: SwapViewModel.UiStatus? = this.status
    ) {
        val hadState = swapState != null
        swapState = state
        this.estimate = estimate
        this.status = status
        if (!hadState && state != null && hasAmount) updateSwapAmount()
    }

    fun userEditedInput(input: TokenTradeAmountInput) {
        if (this.input == input) return
        this.input = input
        retainedTokenAmount = null
        updateSwapAmount()
    }

    fun toggleUnit() {
        if (price <= 0) return
        val amount = typedTokenAmount
        isTokenAmount = !isTokenAmount
        setInput(amount)
    }

    fun useFraction(percentage: Int) {
        val maximum = maximumTokenAmount ?: return
        if (cardCurrency != null) {
            setInput(maximum * percentage.toBigInteger() / HUNDRED)
            return
        }
        val selling = swapState?.tokenToSend ?: return
        val amount = swap.tokenToSendMaxBalance * percentage.toBigInteger() / HUNDRED
        if (percentage == 100) {
            swap.tokenToSendSetMaxAmount()
        } else {
            swap.onTokenToSendAmountInput(CoinUtils.toDecimalString(amount, selling.decimals))
        }
        setInput(if (isBuying) convert(amount, selling, token) ?: BigInteger.ZERO else amount)
    }

    fun selectCard(currency: MBaseCurrency) {
        if (!availableCardCurrencies.contains(currency)) return
        val amount = typedTokenAmount
        val changesCurrency = this.currency != currency
        cardCurrency = currency
        swap.onTokenToSendAmountInput(null)
        if (changesCurrency) setInput(amount) else retainedTokenAmount = amount
    }

    fun selectToken(asset: IApiToken) {
        if (asset.slug == token.slug) return
        val amount = typedTokenAmount
        val changesCurrency = currency != WalletCore.baseCurrency
        cardCurrency = null
        if (isBuying) swap.setTokenToSend(asset) else swap.setTokenToReceive(asset)
        if (changesCurrency) setInput(amount) else retainedTokenAmount = amount
        updateSwapAmount()
    }

    fun resetAmount() {
        input = TokenTradeAmountInput()
        retainedTokenAmount = null
        cardMaximum = null
        cardMaximumError = null
        cardCurrency?.let { if (!availableCardCurrencies.contains(it)) cardCurrency = null }
        swap.onTokenToSendAmountInput(null)
    }

    fun cardMaximumRequest(): CardMaximumRequest? {
        val cardCurrency = cardCurrency ?: return null
        if (isBuying || !availableCardCurrencies.contains(cardCurrency)) return null
        val accountId = account?.accountId ?: return null
        val balance = BalanceStore.getBalances(accountId)?.get(token.slug) ?: BigInteger.ZERO
        return CardMaximumRequest(accountId, balance)
    }

    fun clearCardMaximum() {
        cardMaximum = null
        cardMaximumError = null
    }

    /** Returns false when the request is no longer current and the result was dropped. */
    suspend fun refreshCardMaximum(request: CardMaximumRequest): Boolean {
        val result = try {
            Result.success(
                SellWithCardLauncher.maximumAmount(request.accountId, token, request.balance)
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Result.failure(e)
        }
        if (cardMaximumRequest() != request) return false
        result.fold(
            onSuccess = { cardMaximum = it },
            onFailure = { cardMaximumError = LocaleController.getString("Unexpected Error") }
        )
        return true
    }

    private fun setInput(tokenAmount: BigInteger) {
        retainedTokenAmount = tokenAmount
        input = if (isTokenAmount) {
            TokenTradeAmountInput.of(tokenAmount, token.decimals)
        } else {
            TokenTradeAmountInput.of(tokenToFiat(tokenAmount), currency.decimalsCount)
        }
    }

    private fun updateSwapAmount() {
        if (cardCurrency != null) return
        val state = swap.currentUiInputState ?: return
        val amount = typedTokenAmount
        if (isBuying && (state.isCex || !state.canSwapByBuyAmount)) {
            val payment = state.tokenToSend
            val paymentAmount = payment?.let { convert(amount, token, it) }
            swap.onTokenToSendAmountInput(
                paymentAmount?.takeIf { it > BigInteger.ZERO }
                    ?.let { CoinUtils.toDecimalString(it, payment.decimals) }
            )
            return
        }
        val text = amount.takeIf { it > BigInteger.ZERO }
            ?.let { CoinUtils.toDecimalString(it, token.decimals) }
        if (isBuying) {
            swap.onTokenToReceiveAmountInput(
                text
            )
        } else {
            swap.onTokenToSendAmountInput(text)
        }
    }

    private fun fiatToToken(fiat: BigInteger): BigInteger {
        if (price <= 0) return BigInteger.ZERO
        return BigDecimal(fiat, currency.decimalsCount)
            .divide(BigDecimal.valueOf(price), token.decimals, RoundingMode.HALF_UP)
            .movePointRight(token.decimals)
            .toBigInteger()
    }

    private fun tokenToFiat(amount: BigInteger): BigInteger = BigDecimal(amount, token.decimals)
        .multiply(BigDecimal.valueOf(price))
        .setScale(currency.decimalsCount, RoundingMode.HALF_UP)
        .unscaledValue()

    private fun convert(amount: BigInteger, from: IApiToken, to: IApiToken): BigInteger? {
        val fromPrice = priceUsd(from)
        val toPrice = priceUsd(to)
        if (fromPrice <= 0 || toPrice <= 0) return null
        return BigDecimal(amount, from.decimals)
            .multiply(BigDecimal.valueOf(fromPrice))
            .divide(BigDecimal.valueOf(toPrice), to.decimals, RoundingMode.DOWN)
            .movePointRight(to.decimals)
            .toBigInteger()
    }

    private fun valueUsd(amount: BigInteger, token: IApiToken): Double? {
        if (amount.signum() == 0) return 0.0
        val price = priceUsd(token).takeIf { it > 0 } ?: return null
        return BigDecimal(amount, token.decimals).toDouble() * price
    }

    private fun priceUsd(token: IApiToken): Double =
        TokenStore.getToken(token.slug)?.priceUsd?.takeIf { it.isFinite() } ?: 0.0

    private companion object {
        val HUNDRED: BigInteger = BigInteger.valueOf(100)
        const val SMALL_FEE_USD = 0.5
    }
}
