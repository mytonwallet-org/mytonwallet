package org.mytonwallet.app_air.uiswap.screens.swap.models

import java.math.BigInteger
import java.net.URI
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapHint
import org.mytonwallet.app_air.walletcore.stores.TokenStore

sealed class SwapHint {
    data class Receive(val chain: MBlockchain, val hasAlternativeToken: Boolean) : SwapHint()
    data class BelowMinimum(val chain: MBlockchain) : SwapHint()
    data class Intermediate(val token: MApiSwapAsset, val buyingToken: IApiToken) : SwapHint()
    data class External(val providerName: String, val url: String) : SwapHint()

    val title: String
        get() = when (this) {
            is Receive, is BelowMinimum -> LocaleController.getString("Add funds to swap")
            is Intermediate -> LocaleController.getString("Direct swap unavailable")
            is External -> LocaleController.getString("Swap on an external service")
        }

    val message: String
        get() = when (this) {
            is Receive -> if (hasAlternativeToken) {
                LocaleController.getString("Buy crypto or choose another token to sell.")
            } else {
                LocaleController.getString("Buy with a card or receive crypto to fund this swap.")
            }

            is BelowMinimum -> LocaleController.getString(
                "Your balances are small. Add funds or choose another token to swap."
            )

            is Intermediate -> LocaleController.getStringWithKeyValues(
                "To buy %buy_token%, first buy %token%, then swap it for %buy_token%.",
                listOf(
                    "%buy_token%" to (buyingToken.symbol ?: ""),
                    "%token%" to (token.symbol ?: "")
                )
            )

            is External -> LocaleController.getStringWithKeyValues(
                "Open %provider% to swap this pair in the browser.",
                listOf("%provider%" to providerName)
            )
        }

    val actionTitle: String
        get() = when (this) {
            is Receive, is BelowMinimum -> LocaleController.getString("Fund")

            is Intermediate -> LocaleController.getStringWithKeyValues(
                "Buy %token%",
                listOf("%token%" to (token.symbol ?: ""))
            )

            is External -> LocaleController.getStringWithKeyValues(
                "Open %provider%",
                listOf("%provider%" to providerName)
            )
        }

    companion object {
        fun resolve(state: SwapUiInputState, est: SwapEstimateResponse?): SwapHint? {
            val sellingToken = state.tokenToSend
            val buyingToken = state.tokenToReceive ?: return null
            fromBackend(est?.hint, state, sellingToken, buyingToken)?.let { return it }

            val buyingChain = buyingToken.mBlockchain ?: return null
            if (!state.wallet.isSupportedChain(buyingChain)) return null
            val balances = state.wallet.balances
            if (sellingToken != null && state.tokenToSendIsSupported) {
                val fromMin = est?.fromAmountMin
                if (fromMin != null && (balances[sellingToken.slug] ?: BigInteger.ZERO) < fromMin) {
                    return BelowMinimum(buyingChain)
                }
            }
            if (sellingToken != null && sellingToken.slug != buyingToken.slug &&
                (balances[sellingToken.slug] ?: BigInteger.ZERO) > BigInteger.ZERO
            ) {
                return null
            }
            val hasAlternativeToken = balances.any { (slug, balance) ->
                slug != buyingToken.slug && balance > BigInteger.ZERO &&
                    TokenStore.getToken(slug)?.isLpToken != true
            }
            return Receive(buyingChain, hasAlternativeToken)
        }

        private fun fromBackend(
            hint: MApiSwapHint?,
            state: SwapUiInputState,
            sellingToken: IApiToken?,
            buyingToken: IApiToken
        ): SwapHint? {
            hint ?: return null
            sellingToken ?: return null
            return when (hint.type) {
                "intermediate" -> {
                    val slug = hint.token ?: return null
                    val token = state.wallet.assetsMap[slug]
                        ?: TokenStore.getToken(slug)?.let { MApiSwapAsset.from(it) }
                        ?: return null
                    if (token.slug == sellingToken.slug ||
                        token.slug == buyingToken.slug
                    ) {
                        return null
                    }
                    Intermediate(token, buyingToken)
                }

                "external" -> {
                    val providerName = hint.providerName?.trim()?.takeIf { it.isNotEmpty() }
                        ?: return null
                    val url = hint.url ?: return null
                    val uri = runCatching { URI(url) }.getOrNull() ?: return null
                    if (uri.scheme != "https" || uri.host.isNullOrEmpty()) return null
                    External(providerName, url)
                }

                else -> null
            }
        }
    }
}
