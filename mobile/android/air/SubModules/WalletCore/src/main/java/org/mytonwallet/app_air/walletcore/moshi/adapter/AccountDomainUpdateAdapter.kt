package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.FromJson
import com.squareup.moshi.JsonDataException
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.ToJson

sealed class AccountDomainUpdate {
    data class Set(val value: String) : AccountDomainUpdate()
    data object Clear : AccountDomainUpdate()
}

class AccountDomainUpdateAdapter {
    @FromJson
    fun fromJson(reader: JsonReader): AccountDomainUpdate {
        return when (reader.peek()) {
            JsonReader.Token.STRING -> AccountDomainUpdate.Set(reader.nextString())
            JsonReader.Token.BOOLEAN -> {
                if (reader.nextBoolean()) {
                    throw JsonDataException("Expected domain string or false at ${reader.path}")
                }
                AccountDomainUpdate.Clear
            }

            else -> throw JsonDataException("Expected domain string or false at ${reader.path}")
        }
    }

    @ToJson
    fun toJson(writer: JsonWriter, value: AccountDomainUpdate?) {
        when (value) {
            is AccountDomainUpdate.Set -> writer.value(value.value)
            AccountDomainUpdate.Clear -> writer.value(false)
            null -> writer.nullValue()
        }
    }
}
