package org.mytonwallet.app_air.walletcore.stores

import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcore.WalletCore

object ConfigStore : IStore {
    var isCopyStorageEnabled: Boolean? = null
    var supportAccountsCount: Double? = null
    var isLimited: Boolean? = null
    var countryCode: String? = null
    var isAppUpdateRequired: Boolean? = null
    var swapVersion: Int? = null

    fun init(configMap: Map<String, Any>?) {
        if (configMap == null) return
        if (configMap["switchToClassic"] as? Boolean == true) {
            WalletCore.switchingToLegacy()
            WalletContextManager.delegate?.switchToLegacy()
        }
        isCopyStorageEnabled = configMap["isCopyStorageEnabled"] as? Boolean
        supportAccountsCount = configMap["supportAccountsCount"] as? Double
        isLimited = configMap["isLimited"] as? Boolean
        countryCode = configMap["countryCode"] as? String
        isAppUpdateRequired = configMap["isAppUpdateRequired"] as? Boolean
        swapVersion = (configMap["swapVersion"] as? Number)?.toInt()
    }

    override fun wipeData() {
    }

    override fun clearCache() {
    }
}
