package org.mytonwallet.app_air.walletcore.models.blockchain

// Parses "#RRGGBB" without android.graphics so chain configs can initialize in JVM unit tests.
internal fun String.hexToColorInt(): Int {
    require(length == 7 && startsWith('#')) { "Expected #RRGGBB, got $this" }
    return (0xFF shl 24) or substring(1).toInt(16)
}
