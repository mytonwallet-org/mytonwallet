package org.mytonwallet.app_air.walletcore

internal data class PlayInstallMetadata(val installedAt: Long?, val installVersion: String)

internal fun readPlayInstallMetadata(
    installBeginTimestampServerSeconds: Long,
    installVersion: String?
): PlayInstallMetadata {
    val installedAt = installBeginTimestampServerSeconds
        .takeIf { it in 1L..9007199254740L }?.times(1000)
    val version = installVersion?.takeIf { it.length <= 64 } ?: ""
    return PlayInstallMetadata(installedAt, version)
}
