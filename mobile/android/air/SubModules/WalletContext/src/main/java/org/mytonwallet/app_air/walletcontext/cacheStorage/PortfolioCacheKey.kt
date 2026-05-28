package org.mytonwallet.app_air.walletcontext.cacheStorage

data class PortfolioCacheKey(
    val accountId: String,
    val methodName: String,
    val periodValue: String,
    val currencyCode: String,
    val bucket: Long,
) {
    override fun toString(): String =
        listOf(accountId, methodName, periodValue, currencyCode, bucket).joinToString(SEPARATOR)

    companion object {
        private const val SEPARATOR = "|"
        private const val SEGMENT_COUNT = 5

        fun accountPrefix(accountId: String): String = accountId + SEPARATOR

        fun chartPrefix(accountId: String, methodName: String, periodValue: String): String =
            listOf(accountId, methodName, periodValue, "").joinToString(SEPARATOR)

        fun parse(key: String): PortfolioCacheKey? {
            val segments = key.split(SEPARATOR)
            if (segments.size != SEGMENT_COUNT) return null
            val bucket = segments[4].toLongOrNull() ?: return null
            return PortfolioCacheKey(
                accountId = segments[0],
                methodName = segments[1],
                periodValue = segments[2],
                currencyCode = segments[3],
                bucket = bucket,
            )
        }
    }
}
