package org.mytonwallet.app_air.walletsdk.methods

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory

class SDKMoshiBuilder {
    companion object {
        fun build(): Moshi {
            return Moshi.Builder()
                .addLast(KotlinJsonAdapterFactory())
                .build()
        }
    }
}
