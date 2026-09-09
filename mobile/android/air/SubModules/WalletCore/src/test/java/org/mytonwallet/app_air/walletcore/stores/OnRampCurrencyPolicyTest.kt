package org.mytonwallet.app_air.walletcore.stores

import com.squareup.moshi.JsonDataException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletcore.moshi.MoshiBuilder
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

class OnRampCurrencyPolicyTest {

    @Test
    fun absentListKeepsFullBaselineOnTon() {
        ConfigStore.init(ApiUpdate.ApiUpdateConfig())
        assertEquals(
            listOf(MBaseCurrency.USD, MBaseCurrency.EUR, MBaseCurrency.RUB),
            OnRampCurrencyPolicy.supportedCurrencies("ton")
        )
    }

    // The ruble URL buys GRAM and carries the TON address, so offering RUB anywhere else would spend
    // rubles on an asset the user did not pick. Every chain has to stay out of the ruble flow, not
    // only the ones known today
    @Test
    fun rubIsNeverOfferedOffTon() {
        ConfigStore.init(
            ApiUpdate.ApiUpdateConfig(allowedOnOffRampCurrencies = listOf("usd", "eur", "rub"))
        )
        for (chain in listOf("tron", "solana", "ethereum", "base", "bnb")) {
            assertEquals(
                listOf(MBaseCurrency.USD, MBaseCurrency.EUR),
                OnRampCurrencyPolicy.supportedCurrencies(chain)
            )
        }
    }

    @Test
    fun serverListNarrowsTheBaseline() {
        ConfigStore.init(
            ApiUpdate.ApiUpdateConfig(allowedOnOffRampCurrencies = listOf("usd", "eur"))
        )
        assertEquals(
            listOf(MBaseCurrency.USD, MBaseCurrency.EUR),
            OnRampCurrencyPolicy.supportedCurrencies("ton")
        )
    }

    @Test
    fun emptyListYieldsNoCurrencies() {
        ConfigStore.init(
            ApiUpdate.ApiUpdateConfig(allowedOnOffRampCurrencies = emptyList<String>())
        )
        assertEquals(emptyList<MBaseCurrency>(), OnRampCurrencyPolicy.supportedCurrencies("ton"))
    }

    @Test
    fun currencyCodesAreMatchedRegardlessOfCase() {
        ConfigStore.init(
            ApiUpdate.ApiUpdateConfig(allowedOnOffRampCurrencies = listOf("USD", "Eur"))
        )
        assertEquals(
            listOf(MBaseCurrency.USD, MBaseCurrency.EUR),
            OnRampCurrencyPolicy.supportedCurrencies("ton")
        )
    }

    @Test
    fun unknownCodesDropWithoutHidingTheKnownOnes() {
        ConfigStore.init(
            ApiUpdate.ApiUpdateConfig(allowedOnOffRampCurrencies = listOf("usd", "gbp", "usd"))
        )
        assertEquals(listOf(MBaseCurrency.USD), OnRampCurrencyPolicy.supportedCurrencies("ton"))
    }

    @Test
    fun malformedListRejectsTheWholeUpdate() {
        val adapter = MoshiBuilder.build().adapter(ApiUpdate.ApiUpdateConfig::class.java)
        assertThrows(JsonDataException::class.java) {
            adapter.fromJson("""{"allowedOnOffRampCurrencies":"rub"}""")
        }
    }

    @Test
    fun narrowingAfterAWiderConfigTakesEffect() {
        ConfigStore.init(
            ApiUpdate.ApiUpdateConfig(allowedOnOffRampCurrencies = listOf("usd", "eur", "rub"))
        )
        assertEquals(
            listOf(MBaseCurrency.USD, MBaseCurrency.EUR, MBaseCurrency.RUB),
            OnRampCurrencyPolicy.supportedCurrencies("ton")
        )
        ConfigStore.init(ApiUpdate.ApiUpdateConfig(allowedOnOffRampCurrencies = listOf("usd")))
        assertEquals(listOf(MBaseCurrency.USD), OnRampCurrencyPolicy.supportedCurrencies("ton"))
    }

    @Test
    fun preferredCurrencyTakesTheFirstOfferedPreference() {
        ConfigStore.init(
            ApiUpdate.ApiUpdateConfig(allowedOnOffRampCurrencies = listOf("usd", "eur", "rub"))
        )
        assertEquals(
            MBaseCurrency.RUB,
            OnRampCurrencyPolicy.preferredCurrency(
                "ton",
                listOf(MBaseCurrency.RUB, MBaseCurrency.USD)
            )
        )
    }

    @Test
    fun preferredCurrencySkipsAPreferenceTheServerWithdrew() {
        ConfigStore.init(
            ApiUpdate.ApiUpdateConfig(allowedOnOffRampCurrencies = listOf("usd", "eur"))
        )
        assertEquals(
            MBaseCurrency.USD,
            OnRampCurrencyPolicy.preferredCurrency("ton", listOf(MBaseCurrency.RUB))
        )
    }

    @Test
    fun preferredCurrencyNeverAnswersOutsideTheOfferedSet() {
        ConfigStore.init(ApiUpdate.ApiUpdateConfig(allowedOnOffRampCurrencies = listOf("eur")))
        assertEquals(
            MBaseCurrency.EUR,
            OnRampCurrencyPolicy.preferredCurrency("ton", listOf(MBaseCurrency.USD))
        )
    }

    @Test
    fun preferredCurrencyAnswersNothingWhenNothingIsOffered() {
        ConfigStore.init(
            ApiUpdate.ApiUpdateConfig(allowedOnOffRampCurrencies = emptyList<String>())
        )
        assertEquals(
            null,
            OnRampCurrencyPolicy.preferredCurrency(
                "ton",
                listOf(MBaseCurrency.USD, MBaseCurrency.EUR)
            )
        )
    }
}
