package org.mytonwallet.app_air.walletcore.stores

interface IStore {
    // Remove all data and cache (removed all wallets)
    fun wipeData()

    // Remove cached data (switching to Classic)
    fun clearCache()
}
