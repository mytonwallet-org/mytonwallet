package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.FromJson
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.ToJson
import java.math.BigDecimal

class BigDecimalJsonAdapter : JsonAdapter<BigDecimal>() {
    @ToJson
    override fun toJson(writer: JsonWriter, value: BigDecimal?) {
        val bigDecimal = value ?: run {
            writer.nullValue()
            return
        }

        writer.value(bigDecimal.stripTrailingZeros().toPlainString())
    }

    @FromJson
    override fun fromJson(reader: JsonReader): BigDecimal {
        val toParse = reader.nextString()
        return BigDecimal(toParse)
    }
}
