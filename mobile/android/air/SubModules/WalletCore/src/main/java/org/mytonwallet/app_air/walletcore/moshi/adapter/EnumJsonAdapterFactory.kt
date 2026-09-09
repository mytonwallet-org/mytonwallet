package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Moshi
import java.lang.reflect.Type
import kotlin.reflect.KClass
import kotlin.reflect.full.isSubclassOf

class EnumJsonAdapterFactory : JsonAdapter.Factory {
    override fun create(
        type: Type,
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
