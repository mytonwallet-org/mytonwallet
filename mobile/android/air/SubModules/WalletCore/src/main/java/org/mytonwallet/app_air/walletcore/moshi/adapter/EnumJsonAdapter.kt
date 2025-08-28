package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.FromJson
import com.squareup.moshi.Json
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.ToJson
import kotlin.reflect.KClass

class EnumJsonAdapter<T : Enum<T>>(private val enumClass: KClass<T>) : JsonAdapter<T>() {
    private val values = enumClass.java.enumConstants!!.associateBy {
        enumClass.java.getField(it.name).getAnnotation(Json::class.java)?.name ?: it.name
    }

    @FromJson
    override fun fromJson(reader: JsonReader): T? {
        if (!reader.hasNext()) {
            return null
        }

        val value = reader.nextString()
        return values[value]
    }

    @ToJson
    override fun toJson(writer: JsonWriter, value: T?) {
        val enumName = value?.name ?: run {
            writer.nullValue()
            return
        }

        val annotationName = enumClass.java.getField(enumName)
            .getAnnotation(Json::class.java)?.name

        writer.value(annotationName ?: enumName)
    }
}
