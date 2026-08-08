package org.mytonwallet.app_air.walletcore.stores

import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency

// Which buy-with-card currencies a surface may offer: the hardcoded baseline narrowed by the
// server-sent allowlist. An absent list means the baseline; an empty list means no currencies,
// and callers must hide or refuse the entry point instead of falling back to a default currency.
object OnRampCurrencyPolicy {

    // Plain chain-name literal instead of the MBlockchain enum keeps this object free of the
    // Android-flavored blockchain config graph and therefore testable on the JVM
    private const val TON_CHAIN = "ton"

    private val baselineCurrencies = listOf(MBaseCurrency.USD, MBaseCurrency.EUR, MBaseCurrency.RUB)

    fun supportedCurrencies(chain: String): List<MBaseCurrency> {
        val allowed = ConfigStore.allowedOnOffRampCurrencies
        return baselineCurrencies.filter { currency ->
            (allowed == null || allowed.contains(currency)) &&
                (currency != MBaseCurrency.RUB || chain == TON_CHAIN)
        }
    }

    // Which currency a surface starts on: the first listed preference still offered, or the first offered
    // currency when no preference survives. Null means nothing is offered and the caller must refuse the
    // entry point - naming a currency of its own here is what lets the app offer one the server withdrew.
    fun preferredCurrency(chain: String, preferences: List<MBaseCurrency>): MBaseCurrency? {
        val supported = supportedCurrencies(chain)
        return preferences.firstOrNull { supported.contains(it) } ?: supported.firstOrNull()
    }
}
