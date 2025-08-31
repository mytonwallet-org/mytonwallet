package org.mytonwallet.app_air.walletcore.models

import org.mytonwallet.app_air.walletcontext.helpers.LocaleController

enum class MBaseCurrency(val currencyCode: String) {
    USD("USD"),
    EUR("EUR"),
    RUB("RUB"),
    CNY("CNY"),
    BTC("BTC"),
    TON("TON");

    val sign: String
        get() = when (this) {
            USD -> "$"
            EUR -> "€"
            RUB -> "₽"
            CNY -> "¥"
            BTC -> "BTC"
            TON -> "TON"
        }

    val decimalsCount: Int
        get() = when (this) {
            BTC -> 6
            else -> 2
        }

    val currencySymbol: String
        get() = when (this) {
            USD -> LocaleController.getString("USD")
            EUR -> LocaleController.getString("EUR")
            RUB -> LocaleController.getString("RUB")
            CNY -> LocaleController.getString("CNY")
            BTC -> LocaleController.getString("BTC")
            TON -> LocaleController.getString("TON")
        }

    val currencyName: String
        get() = when (this) {
            USD -> LocaleController.getString("US Dollar")
            EUR -> LocaleController.getString("Euro")
            RUB -> LocaleController.getString("Ruble")
            CNY -> LocaleController.getString("Yuan")
            BTC -> LocaleController.getString("Bitcoin")
            TON -> LocaleController.getString("Toncoin")
        }

    companion object {
        fun parse(value: String) = try {
            MBaseCurrency.valueOf(value)
        } catch (t: Throwable) {
            USD
        }
    }
}
