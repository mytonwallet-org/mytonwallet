package org.mytonwallet.app_air.walletcore.moshi.adapter.factory

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonAdapter.Factory
import com.squareup.moshi.Moshi
import org.mytonwallet.app_air.walletcore.moshi.adapter.EnumJsonAdapter
import kotlin.reflect.KClass
import kotlin.reflect.full.isSubclassOf

class EnumJsonAdapterFactory : Factory {
    override fun create(
        type: java.lang.reflect.Type,
        annotations: MutableSet<out Annotation>,
        moshi: Moshi
    ): JsonAdapter<*>? {
        val rawType = (type as? Class<*>)?.kotlin ?: return null
        if (rawType.isSubclassOf(Enum::class)) {
            @Suppress("UNCHECKED_CAST")
            return EnumJsonAdapter(rawType as KClass<out Enum<*>>)
        }
        return null
    }
}
