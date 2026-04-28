package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.FromJson
import com.squareup.moshi.JsonReader
import com.squareup.moshi.ToJson
import org.mytonwallet.app_air.walletcore.moshi.ApiNftMetadata

class NftAttributeAdapter {
    @FromJson
    fun fromJson(reader: JsonReader): ApiNftMetadata.Attribute? {
        return when (reader.peek()) {
            JsonReader.Token.BEGIN_OBJECT -> {
                reader.beginObject()
                var traitType: String? = null
                var value: String? = null
                while (reader.hasNext()) {
                    when (reader.nextName()) {
                        "trait_type" -> traitType = readStringCoerced(reader)
                        "value" -> value = readStringCoerced(reader)
                        else -> reader.skipValue()
                    }
                }
                reader.endObject()
                ApiNftMetadata.Attribute(traitType, value)
            }

            JsonReader.Token.NULL -> {
                reader.nextNull<Unit>()
                null
            }

            else -> {
                reader.skipValue()
                null
            }
        }
    }

    @ToJson
    fun toJson(attribute: ApiNftMetadata.Attribute): Map<String, String?> {
        return mapOf("trait_type" to attribute.traitType, "value" to attribute.value)
    }

    private fun readStringCoerced(reader: JsonReader): String? {
        return when (reader.peek()) {
            JsonReader.Token.NULL -> reader.nextNull()
            JsonReader.Token.STRING -> reader.nextString()
            JsonReader.Token.BOOLEAN -> reader.nextBoolean().toString()
            JsonReader.Token.NUMBER -> reader.nextString()
            else -> {
                reader.skipValue()
                null
            }
        }
    }
}