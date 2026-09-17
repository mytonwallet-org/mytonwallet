package org.mytonwallet.app_air.walletcore.models

import com.squareup.moshi.JsonDataException
import com.squareup.moshi.JsonReader
import org.json.JSONObject

internal interface TokenFields {
    fun optString(name: String): String
    fun optInt(name: String): Int
    fun optDouble(name: String): Double
    fun optBoolean(name: String): Boolean
    fun optStrings(name: String): List<String>?
}

internal class JsonObjectTokenFields(private val json: JSONObject) : TokenFields {
    override fun optString(name: String) = json.optString(name)
    override fun optInt(name: String) = json.optInt(name)
    override fun optDouble(name: String) = json.optDouble(name)
    override fun optBoolean(name: String) = json.optBoolean(name)
    override fun optStrings(name: String) = json.optJSONArray(name)?.let { values ->
        List(values.length()) { values.optString(it) }
    }
}

internal fun readToken(reader: JsonReader): MToken =
    JsonReader.of(reader.nextSource()).use { MToken(readTokenFields(it)) }

private fun readTokenFields(reader: JsonReader): TokenFields {
    if (reader.peek() != JsonReader.Token.BEGIN_OBJECT) {
        reader.skipValue()
        throw JsonDataException("Expected token object")
    }
    val values = Array<Any?>(tokenFieldNames.size) { MissingTokenField }
    reader.beginObject()
    while (reader.hasNext()) {
        val index = reader.selectName(tokenFieldOptions)
        if (index < 0) {
            reader.skipName()
            readTokenValue(reader)
        } else {
            values[index] = readTokenValue(reader)
        }
    }
    reader.endObject()
    return StreamTokenFields(values)
}

private object MissingTokenField

private class StreamTokenFields(private val values: Array<Any?>) : TokenFields {
    private fun value(name: String): Any? {
        val index = tokenFieldIndices[name] ?: return MissingTokenField
        return values[index]
    }

    override fun optString(name: String): String {
        val value = value(name)
        return if (value === MissingTokenField) "" else tokenValueString(value)
    }

    override fun optInt(name: String): Int = when (val value = value(name)) {
        is Number -> value.toInt()
        is String -> value.toDoubleOrNull()?.toInt() ?: 0
        else -> 0
    }

    override fun optDouble(name: String): Double = when (val value = value(name)) {
        is Number -> value.toDouble()
        is String -> value.toDoubleOrNull() ?: Double.NaN
        else -> Double.NaN
    }

    override fun optBoolean(name: String): Boolean = when (val value = value(name)) {
        is Boolean -> value
        is String -> value.equals("true", ignoreCase = true)
        else -> false
    }

    override fun optStrings(name: String): List<String>? =
        (value(name) as? List<*>)?.map(::tokenValueString)
}

private fun tokenValueString(value: Any?): String = when (value) {
    null -> "null"
    is Map<*, *>, is List<*> -> JSONObject.wrap(value).toString()
    else -> value.toString()
}

private fun readTokenValue(reader: JsonReader): Any? = when (reader.peek()) {
    JsonReader.Token.NULL -> reader.nextNull<Any>()

    JsonReader.Token.STRING -> reader.nextString()

    JsonReader.Token.BOOLEAN -> reader.nextBoolean()

    JsonReader.Token.NUMBER -> reader.nextString().let { value ->
        value.toLongOrNull() ?: value.toDouble().also {
            if (!it.isFinite()) throw JsonDataException("Non-finite token number")
        }
    }

    JsonReader.Token.BEGIN_ARRAY -> {
        val values = ArrayList<Any?>()
        reader.beginArray()
        while (reader.hasNext()) values.add(readTokenValue(reader))
        reader.endArray()
        values
    }

    JsonReader.Token.BEGIN_OBJECT -> {
        val values = LinkedHashMap<String, Any?>()
        reader.beginObject()
        while (reader.hasNext()) values[reader.nextName()] = readTokenValue(reader)
        reader.endObject()
        values
    }

    else -> throw JsonDataException("Unexpected token field at ${reader.path}")
}

private val tokenFieldNames = arrayOf(
    "decimals",
    "slug",
    "symbol",
    "name",
    "localizedName",
    "image",
    "minterAddress",
    "tokenAddress",
    "isPopular",
    "chain",
    "blockchain",
    "codeHash",
    "label",
    "percentChange24h",
    "priceUsd",
    "isFromBackend",
    "type",
    "keywords",
    "cmcSlug",
    "color",
    "isGaslessEnabled",
    "isStarsEnabled",
    "isTiny",
    "customPayloadApiUrl"
)
private val tokenFieldOptions = JsonReader.Options.of(*tokenFieldNames)
private val tokenFieldIndices = tokenFieldNames.withIndex().associate { it.value to it.index }
