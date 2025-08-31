package org.mytonwallet.app_air.walletcore.models

data class NftCollection(
    val address: String,
    val name: String
) {
    companion object {
        const val TELEGRAM_GIFTS_SUPER_COLLECTION = "super:telegram-gifts"
    }
}
