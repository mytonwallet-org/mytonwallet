package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.FromJson
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.ToJson
import org.mytonwallet.app_air.walletcore.moshi.ReturnStrategy

class ReturnStrategyAdapter : JsonAdapter<ReturnStrategy>() {
    @ToJson
    override fun toJson(writer: JsonWriter, value: ReturnStrategy?) {
        val strategy = value ?: run {
            writer.nullValue()
            return
        }

        when (strategy) {
            is ReturnStrategy.None -> writer.value("none")
            is ReturnStrategy.Back -> writer.value("back")
            is ReturnStrategy.Empty -> writer.value("empty")
            is ReturnStrategy.Url -> writer.value(strategy.url)
        }
    }

    @FromJson
    override fun fromJson(reader: JsonReader): ReturnStrategy {
        return when (val url = reader.nextString()) {
            "none" -> ReturnStrategy.None
            "back" -> ReturnStrategy.Back
            else -> ReturnStrategy.Url(url)
        }
    }
}
