package org.mytonwallet.app_air.walletcore.api

import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiPortfolioHistoryResponse

suspend fun WalletCore.fetchPortfolioNetWorthHistory(
    wallets: List<String>,
    baseCurrency: MBaseCurrency,
): ApiPortfolioHistoryResponse {
    return bridge!!.callApiAsync(
        "fetchPortfolioNetWorthHistory",
        ArgumentsBuilder()
            .jsArray(wallets, String::class.java)
            .string(baseCurrency.currencyCode)
            .build(),
        ApiPortfolioHistoryResponse::class.java
    )
}
