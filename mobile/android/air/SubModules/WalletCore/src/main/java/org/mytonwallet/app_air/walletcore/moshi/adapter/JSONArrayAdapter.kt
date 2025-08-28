package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.FromJson
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.ToJson
import okio.Buffer
import org.json.JSONArray
import org.json.JSONException


class JSONArrayAdapter : JsonAdapter<JSONArray>() {
    @FromJson
    override fun fromJson(reader: JsonReader): JSONArray? {
        return try {
            JSONArray(reader.nextSource().readUtf8())
        } catch (e: JSONException) {
            return null
        }
    }

    @ToJson
    override fun toJson(writer: JsonWriter, value: JSONArray?) {
        value?.let { writer.value(Buffer().writeUtf8(it.toString())) }
    }
}
