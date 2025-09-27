package org.mytonwallet.app_air.walletsdk

import com.squareup.moshi.Moshi
import org.mytonwallet.app_air.walletsdk.methods.SDKMoshiBuilder

object WalletSDK {
    val moshi: Moshi by lazy {
        SDKMoshiBuilder.build()
    }
}
