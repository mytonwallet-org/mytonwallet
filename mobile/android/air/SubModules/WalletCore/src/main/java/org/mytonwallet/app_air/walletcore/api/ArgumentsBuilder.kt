package org.mytonwallet.app_air.walletcore.api

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Types
import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.WalletCore
import java.lang.reflect.Type
import java.math.BigInteger

class ArgumentsBuilder {
    private val args = mutableListOf<String>()

    fun string(value: String?): ArgumentsBuilder {
        if (value == null) {
            args.add("null")
        } else {
            val adapter = WalletCore.moshi.adapter(String::class.java)
            args.add(adapter.toJson(value))
        }
        return this
    }

    fun boolean(value: Boolean?): ArgumentsBuilder {
        args.add(value.toString())
        return this
    }

    fun number(value: Int): ArgumentsBuilder {
        args.add(value.toString())
        return this
    }

    fun number(value: Float): ArgumentsBuilder {
        args.add(value.toString())
        return this
    }

    fun number(value: Long): ArgumentsBuilder {
        args.add(value.toString())
        return this
    }

    fun number(value: Double): ArgumentsBuilder {
        args.add(value.toString())
        return this
    }

    fun bigInt(value: BigInteger?): ArgumentsBuilder {
        value?.let {
            string("bigint:$value")
        } ?: run {
            args.add("null")
        }
        return this
    }

    fun <T> jsArray(value: List<T>, clazz: Type): ArgumentsBuilder {
        jsObject(value, Types.newParameterizedType(List::class.java, clazz))
        return this
    }

    fun <T> jsObject(value: T, clazz: Type): ArgumentsBuilder {
        value?.let {
            val adapter: JsonAdapter<T> = WalletCore.moshi.adapter(clazz)
            args.add(adapter.toJson(value))
        } ?: run {
            args.add("null")
        }
        return this
    }

    fun jsonObject(value: JSONObject): ArgumentsBuilder {
        args.add(value.toString())
        return this
    }

    fun build(): String {
        return args.joinToString(",", prefix = "[", postfix = "]")
    }
}
