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
                        "trait_type" -> traitType =
                            if (reader.peek() == JsonReader.Token.NULL) reader.nextNull() else reader.nextString()

                        "value" -> value =
                            if (reader.peek() == JsonReader.Token.NULL) reader.nextNull() else reader.nextString()

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
}
