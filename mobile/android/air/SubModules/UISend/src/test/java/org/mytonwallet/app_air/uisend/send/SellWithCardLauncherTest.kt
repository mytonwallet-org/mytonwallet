package org.mytonwallet.app_air.uisend.send

import java.math.BigInteger
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.moshi.ApiTokenWithPrice

class SellWithCardLauncherTest {
    private val ton = ApiTokenWithPrice(
        name = "Toncoin",
        symbol = "TON",
        slug = TONCOIN_SLUG,
        decimals = 9,
        chain = "ton",
        priceUsd = null,
        percentChange24h = null
    )

    @Test
    fun tonMaximumKeepsExactFullBalanceWithoutSdkConnection() = runBlocking {
        val balance = BigInteger("1234567890")

        assertEquals(balance, SellWithCardLauncher.maximumAmount("account-id", ton, balance))
    }

    @Test
    fun tonMaximumStillRespectsMoonpayCapWithoutSdkConnection() = runBlocking {
        assertEquals(
            BigInteger("2000000000000"),
            SellWithCardLauncher.maximumAmount("account-id", ton, BigInteger("2500000000000"))
        )
    }
}
