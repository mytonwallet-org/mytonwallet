package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.FromJson
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.ToJson
import java.math.BigInteger

class BigIntegerJsonAdapter: JsonAdapter<BigInteger>() {
    @ToJson
    override fun toJson(writer: JsonWriter, value: BigInteger?) {
        val bigint = value ?: run {
            writer.nullValue()
            return
        }

        writer.value("bigint:$bigint")
    }

    @FromJson
    override fun fromJson(reader: JsonReader): BigInteger {
        val toParse = reader.nextString()
        if (toParse.startsWith("bigint:")) {
            return BigInteger(toParse.substring(7))
        }

        return BigInteger(toParse)
    }
}
