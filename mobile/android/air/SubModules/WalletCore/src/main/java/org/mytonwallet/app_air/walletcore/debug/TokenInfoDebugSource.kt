package org.mytonwallet.app_air.walletcore.debug

import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.MApiTokenDetails
import org.mytonwallet.app_air.walletcore.stores.EnvironmentStore

enum class TokenInfoDebugSource(val storageValue: String, val displayName: String) {
    REAL_API("realApi", "Real API"),
    COMPLETE_DATA("completeData", "Complete Data"),
    LOCALIZED_DESCRIPTION("localizedDescription", "Localized Description"),
    LONG_DESCRIPTION_PARTIAL_DATA(
        "longDescriptionPartialData",
        "Long Description / Partial Data"
    ),
    MISSING_DESCRIPTION("missingDescription", "Missing Description");

    val mockTokenInfo: MApiTokenDetails.TokenInfo?
        get() = when (this) {
            COMPLETE_DATA -> completeDataMock

            LOCALIZED_DESCRIPTION -> completeDataMock.copy(
                localizedDescription =
                    "Gram — нативная криптовалюта TON, глубоко интегрированная " +
                        "в экосистему Telegram."
            )

            LONG_DESCRIPTION_PARTIAL_DATA -> longDescriptionPartialDataMock

            MISSING_DESCRIPTION -> completeDataMock.copy(
                description = null,
                localizedDescription = null
            )

            REAL_API -> null
        }

    companion object {
        private val completeDataMock = MApiTokenDetails.TokenInfo(
            description =
                "Gram is TON’s native cryptocurrency and deeply integrated " +
                    "into the Telegram ecosystem.",
            marketCap = 7_580_000_000.0,
            supply = MApiTokenDetails.Supply(
                circulating = 5_120_000_000.0,
                total = 5_120_000_000.0
            ),
            createdAt = "2019-11-15T00:00:00.000Z",
            volume24h = MApiTokenDetails.Volume(
                buy = 2_440_000.0,
                sell = 1_580_000.0,
                percentChange = 89.46
            ),
            links = listOf(
                MApiTokenDetails.Link("https://x.com", "x"),
                MApiTokenDetails.Link("https://t.me", "telegram"),
                MApiTokenDetails.Link("https://gramcoin.org")
            ),
            docsUrl = "https://docs.ton.org",
            sourceCodeUrl = "https://github.com/ton-blockchain/ton"
        )

        private val longDescriptionPartialDataMock = MApiTokenDetails.TokenInfo(
            description =
                "Gram is TON’s native cryptocurrency and deeply integrated into the Telegram " +
                    "ecosystem. This deliberately long test description verifies that every " +
                    "additional line contributes to the measured section height without truncation.",
            supply = MApiTokenDetails.Supply(
                circulating = 5_120_000_000.0,
                total = null
            ),
            links = listOf(
                MApiTokenDetails.Link("https://x.com", "x"),
                MApiTokenDetails.Link("https://t.me", "telegram"),
                MApiTokenDetails.Link("https://gramcoin.org")
            ),
            docsUrl = "https://docs.ton.org",
            sourceCodeUrl = "https://github.com/ton-blockchain/ton"
        )

        fun fromStorageValue(value: String?): TokenInfoDebugSource {
            when (value) {
                "design" -> return COMPLETE_DATA
                "longSparse" -> return LONG_DESCRIPTION_PARTIAL_DATA
            }
            return entries.firstOrNull { it.storageValue == value } ?: REAL_API
        }
    }
}

object TokenInfoDebugConfig {
    val source: TokenInfoDebugSource
        get() {
            if (!DEBUG_MODE && !EnvironmentStore.isBeta) {
                return TokenInfoDebugSource.REAL_API
            }
            return TokenInfoDebugSource.fromStorageValue(
                WGlobalStorage.getTokenInfoDebugSource()
            )
        }

    fun setSource(source: TokenInfoDebugSource) {
        WGlobalStorage.setTokenInfoDebugSource(source.storageValue)
    }
}
