package org.mytonwallet.app_air.uisettings.viewControllers.mintCard

import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.models.MCardInfo
import org.mytonwallet.app_air.walletcore.models.MCardsInfo
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

object MintCardHelpers {

    private val REQUIRED_TON_FOR_FEE = BigInteger.valueOf(65_000_000L)

    val mycoin: MToken?
        get() = TokenStore.getToken(MYCOIN_SLUG)

    fun cardsInfo(accountId: String): MCardsInfo? {
        return MCardsInfo.fromJson(WGlobalStorage.getCardsInfo(accountId))
    }

    fun mycoinBalance(accountId: String): BigInteger {
        return BalanceStore.getBalances(accountId)?.get(MYCOIN_SLUG) ?: BigInteger.ZERO
    }

    fun toncoinBalance(accountId: String): BigInteger {
        return BalanceStore.getBalances(accountId)?.get(TONCOIN_SLUG) ?: BigInteger.ZERO
    }

    fun priceAmount(cardInfo: MCardInfo, token: MToken): BigInteger? {
        return cardInfo.price.toBigInteger(token.decimals)
    }

    fun isEnoughMycoin(accountId: String, cardInfo: MCardInfo, token: MToken): Boolean {
        val amount = priceAmount(cardInfo, token) ?: return false
        return amount <= mycoinBalance(accountId)
    }

    fun isEnoughToncoin(accountId: String): Boolean {
        return REQUIRED_TON_FOR_FEE <= toncoinBalance(accountId)
    }
}
