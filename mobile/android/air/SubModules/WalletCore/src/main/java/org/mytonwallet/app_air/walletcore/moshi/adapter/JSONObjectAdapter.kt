package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.FromJson
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.ToJson
import okio.Buffer
import org.json.JSONException
import org.json.JSONObject


class JSONObjectAdapter : JsonAdapter<JSONObject>() {
    @FromJson
    override fun fromJson(reader: JsonReader): JSONObject? {
        return try {
            JSONObject(reader.nextSource().readUtf8())
        } catch (e: JSONException) {
            return null
        }
    }

    @ToJson
    override fun toJson(writer: JsonWriter, value: JSONObject?) {
        value?.let { writer.value(Buffer().writeUtf8(it.toString())) }
    }
}
