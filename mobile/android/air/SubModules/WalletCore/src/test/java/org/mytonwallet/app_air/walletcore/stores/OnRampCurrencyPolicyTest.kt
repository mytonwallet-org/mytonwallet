package org.mytonwallet.app_air.walletcore.stores

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency

class OnRampCurrencyPolicyTest {

    @Test
    fun absentListKeepsFullBaselineOnTon() {
        ConfigStore.init(mapOf())
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
        ConfigStore.init(mapOf("allowedOnOffRampCurrencies" to listOf("usd", "eur", "rub")))
        for (chain in listOf("tron", "solana", "ethereum", "base", "bnb")) {
            assertEquals(
                listOf(MBaseCurrency.USD, MBaseCurrency.EUR),
                OnRampCurrencyPolicy.supportedCurrencies(chain)
            )
        }
    }

    @Test
    fun serverListNarrowsTheBaseline() {
        ConfigStore.init(mapOf("allowedOnOffRampCurrencies" to listOf("usd", "eur")))
        assertEquals(
            listOf(MBaseCurrency.USD, MBaseCurrency.EUR),
            OnRampCurrencyPolicy.supportedCurrencies("ton")
        )
    }

    @Test
    fun emptyListYieldsNoCurrencies() {
        ConfigStore.init(mapOf("allowedOnOffRampCurrencies" to emptyList<String>()))
        assertEquals(emptyList<MBaseCurrency>(), OnRampCurrencyPolicy.supportedCurrencies("ton"))
    }

    @Test
    fun currencyCodesAreMatchedRegardlessOfCase() {
        ConfigStore.init(mapOf("allowedOnOffRampCurrencies" to listOf("USD", "Eur")))
        assertEquals(
            listOf(MBaseCurrency.USD, MBaseCurrency.EUR),
            OnRampCurrencyPolicy.supportedCurrencies("ton")
        )
    }

    @Test
    fun unknownCodesDropWithoutHidingTheKnownOnes() {
        ConfigStore.init(mapOf("allowedOnOffRampCurrencies" to listOf("usd", "gbp", "usd")))
        assertEquals(listOf(MBaseCurrency.USD), OnRampCurrencyPolicy.supportedCurrencies("ton"))
    }

    @Test
    fun malformedValueReadsAsAbsent() {
        ConfigStore.init(mapOf("allowedOnOffRampCurrencies" to "rub"))
        assertEquals(
            listOf(MBaseCurrency.USD, MBaseCurrency.EUR, MBaseCurrency.RUB),
            OnRampCurrencyPolicy.supportedCurrencies("ton")
        )
    }

    @Test
    fun narrowingAfterAWiderConfigTakesEffect() {
        ConfigStore.init(mapOf("allowedOnOffRampCurrencies" to listOf("usd", "eur", "rub")))
        assertEquals(
            listOf(MBaseCurrency.USD, MBaseCurrency.EUR, MBaseCurrency.RUB),
            OnRampCurrencyPolicy.supportedCurrencies("ton")
        )
        ConfigStore.init(mapOf("allowedOnOffRampCurrencies" to listOf("usd")))
        assertEquals(listOf(MBaseCurrency.USD), OnRampCurrencyPolicy.supportedCurrencies("ton"))
    }

    @Test
    fun preferredCurrencyTakesTheFirstOfferedPreference() {
        ConfigStore.init(mapOf("allowedOnOffRampCurrencies" to listOf("usd", "eur", "rub")))
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
        ConfigStore.init(mapOf("allowedOnOffRampCurrencies" to listOf("usd", "eur")))
        assertEquals(
            MBaseCurrency.USD,
            OnRampCurrencyPolicy.preferredCurrency("ton", listOf(MBaseCurrency.RUB))
        )
    }

    @Test
    fun preferredCurrencyNeverAnswersOutsideTheOfferedSet() {
        ConfigStore.init(mapOf("allowedOnOffRampCurrencies" to listOf("eur")))
        assertEquals(
            MBaseCurrency.EUR,
            OnRampCurrencyPolicy.preferredCurrency("ton", listOf(MBaseCurrency.USD))
        )
    }

    @Test
    fun preferredCurrencyAnswersNothingWhenNothingIsOffered() {
        ConfigStore.init(mapOf("allowedOnOffRampCurrencies" to emptyList<String>()))
        assertEquals(
            null,
            OnRampCurrencyPolicy.preferredCurrency(
                "ton",
                listOf(MBaseCurrency.USD, MBaseCurrency.EUR)
            )
        )
    }
}
