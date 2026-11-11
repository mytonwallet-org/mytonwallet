package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.Moshi
import java.lang.reflect.Type

/** Reads an unreadable value of [types] as `null`. */
class LenientJsonAdapterFactory(private vararg val types: Type) : JsonAdapter.Factory {
    override fun create(type: Type, annotations: Set<Annotation>, moshi: Moshi): JsonAdapter<*>? {
        if (annotations.isNotEmpty() || type !in types) return null
        val delegate = moshi.nextAdapter<Any>(this, type, annotations)
        return object : JsonAdapter<Any>() {
            override fun fromJson(reader: JsonReader): Any? {
                val value = reader.readJsonValue()
                return try {
                    delegate.fromJsonValue(value)
                } catch (_: Exception) {
                    null
                }
            }

            override fun toJson(writer: JsonWriter, value: Any?) {
                delegate.toJson(writer, value)
            }
        }
    }
}
