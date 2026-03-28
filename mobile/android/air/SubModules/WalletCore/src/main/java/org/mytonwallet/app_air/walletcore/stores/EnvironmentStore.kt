package org.mytonwallet.app_air.walletcore.stores

import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.MEnvironmentVariables
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

object EnvironmentStore : IStore {

    private var environmentVariables: MEnvironmentVariables? = null

    fun loadEnvVariable() {
        WalletCore.call(ApiMethod.Other.GetEnvironmentVariables(), { res, _ ->
            if (res != null)
                environmentVariables = res
        })
    }

    override fun wipeData() {
    }

    override fun clearCache() {
    }

    val isBeta: Boolean
        get() {
            return environmentVariables != null && environmentVariables?.appEnv != "production"
        }

    val isAndroidDirect: Boolean
        get() {
            return environmentVariables?.isAndroidDirect == true
        }

    val appVersion: String?
        get() {
            return environmentVariables?.appVersion
        }
}
