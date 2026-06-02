package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.FromJson
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.ToJson
import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.models.AccountMfa

/**
 * Represents the `mfa` field of an `updateAccount` push update.
 *
 * The backend sends one of three states (see `ApiUpdateAccount.mfa: ApiTonWallet['mfa'] | false`):
 * - field absent  -> the value did not change (kept as `null`, so it is skipped)
 * - `false`       -> the MFA was removed ([Clear])
 * - object        -> the new MFA value ([Set])
 */
sealed class MfaUpdate {
    data class Set(val value: AccountMfa) : MfaUpdate()
    data object Clear : MfaUpdate()
}

class MfaUpdateAdapter {
    @FromJson
    fun fromJson(reader: JsonReader): MfaUpdate {
        if (reader.peek() == JsonReader.Token.BOOLEAN) {
            reader.nextBoolean()
            return MfaUpdate.Clear
        }
        @Suppress("UNCHECKED_CAST")
        val map = reader.readJsonValue() as? Map<String, Any?> ?: return MfaUpdate.Clear
        return MfaUpdate.Set(AccountMfa.fromJson(JSONObject(map)))
    }

    @ToJson
    fun toJson(writer: JsonWriter, value: MfaUpdate?) {
        when (value) {
            is MfaUpdate.Set -> writer.valueSink().use { it.writeUtf8(value.value.jsonObject.toString()) }
            MfaUpdate.Clear -> writer.value(false)
            null -> writer.nullValue()
        }
    }
}