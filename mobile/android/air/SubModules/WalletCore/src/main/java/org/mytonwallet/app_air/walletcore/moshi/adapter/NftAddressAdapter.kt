package org.mytonwallet.app_air.walletcore.moshi.adapter

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.JsonWriter
import com.squareup.moshi.Moshi
import java.lang.reflect.Type
import org.mytonwallet.app_air.walletcontext.utils.normalizeNftAddress
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

object NftAddressAdapter : JsonAdapter.Factory {
    override fun create(type: Type, annotations: Set<Annotation>, moshi: Moshi): JsonAdapter<*>? {
        if (type != ApiNft::class.java || annotations.isNotEmpty()) return null
        val delegate = moshi.nextAdapter<ApiNft>(this, type, annotations)
        return object : JsonAdapter<ApiNft>() {
            override fun fromJson(reader: JsonReader): ApiNft? {
                val nft = delegate.fromJson(reader) ?: return null
                val address = normalizeNftAddress(nft.address)
                return if (address == nft.address) nft else nft.copy(address = address)
            }

            override fun toJson(writer: JsonWriter, value: ApiNft?) {
                delegate.toJson(writer, value)
            }
        }
    }
}
