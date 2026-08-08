package org.mytonwallet.app_air.walletcore.helpers

internal fun shouldHideNft(
    isHiddenByUser: Boolean,
    isWhitelisted: Boolean,
    isHidden: Boolean,
    isUnverified: Boolean,
    areUnverifiedNftsHidden: Boolean
): Boolean {
    if (isHiddenByUser) return true
    if (isWhitelisted) return false
    return isHidden || (areUnverifiedNftsHidden && isUnverified)
}

internal fun shouldHideNftActivity(
    isHiddenByUser: Boolean,
    isWhitelisted: Boolean,
    isHidden: Boolean,
    isUnverified: Boolean,
    areUnverifiedNftsHidden: Boolean,
    isIncoming: Boolean,
    isNftTrade: Boolean
): Boolean = shouldHideNft(
    isHiddenByUser = isHiddenByUser,
    isWhitelisted = isWhitelisted,
    isHidden = isHidden,
    isUnverified = isUnverified && isIncoming && !isNftTrade,
    areUnverifiedNftsHidden = areUnverifiedNftsHidden
)
