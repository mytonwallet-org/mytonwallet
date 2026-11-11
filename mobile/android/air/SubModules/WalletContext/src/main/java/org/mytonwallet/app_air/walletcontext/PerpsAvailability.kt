package org.mytonwallet.app_air.walletcontext

// Release-only: Perps stays closed in this release. Every Android entry point to Futures and
// the tab-order migration that inserts it read this, so the release that opens Perps flips it.
object PerpsAvailability {
    fun isAvailable(): Boolean = false
}
