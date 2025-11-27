package org.mytonwallet.app_air.walletcore.moshi

import android.graphics.Color
import android.net.Uri
import androidx.core.graphics.toColorInt
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.WEquatable
import org.mytonwallet.app_air.walletcore.TON_DNS_COLLECTION
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType.BLACK
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType.GOLD
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType.PLATINUM
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType.SILVER
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore

@JsonClass(generateAdapter = true)
data class MApiCheckNftDraftOptions(
    val accountId: String,
    val nfts: Array<JSONObject>,
    val toAddress: String,
    val comment: String?,
)

@JsonClass(generateAdapter = false)
enum class ApiMtwCardType {
    @Json(name = "black")
    BLACK,

    @Json(name = "platinum")
    PLATINUM,

    @Json(name = "gold")
    GOLD,

    @Json(name = "silver")
    SILVER,

    @Json(name = "standard")
    STANDARD
}

@JsonClass(generateAdapter = false)
enum class ApiMtwCardTextType {
    @Json(name = "light")
    LIGHT,

    @Json(name = "dark")
    DARK
}

@JsonClass(generateAdapter = false)
enum class ApiMtwCardBorderShineType {
    @Json(name = "up")
    UP,

    @Json(name = "down")
    DOWN,

    @Json(name = "left")
    LEFT,

    @Json(name = "right")
    RIGHT,

    @Json(name = "radioactive")
    RADIOACTIVE;
}

@JsonClass(generateAdapter = true)
data class ApiNftMetadata(
    @Json(name = "lottie") val lottie: String? = null,
    @Json(name = "imageUrl") val imageUrl: String? = null,
    @Json(name = "fragmentUrl") val fragmentUrl: String? = null,
    @Json(name = "mtwCardId") val mtwCardId: Int? = null,
    @Json(name = "mtwCardType") val mtwCardType: ApiMtwCardType? = null,
    @Json(name = "mtwCardTextType") val mtwCardTextType: ApiMtwCardTextType? = null,
    @Json(name = "mtwCardBorderShineType") val mtwCardBorderShineType: ApiMtwCardBorderShineType? = null,
    @Json(name = "attributes") val attributes: List<Attribute>? = null,
) {
    companion object {
        const val MTW_CARD_BASE_URL = "https://static.mytonwallet.org/cards/"
    }

    data class Attribute(
        @Json(name = "trait_type") val traitType: String?,
        @Json(name = "value") val value: String?
    )

    fun cardImageUrl(mini: Boolean): String {
        return "${MTW_CARD_BASE_URL}${if (mini) "mini@3x/" else ""}$mtwCardId.webp"
    }

    val mtwCardColors: Pair<Int, Int>
        get() {
            return when (mtwCardType) {
                SILVER -> {
                    Pair(
                        "#272727".toColorInt(),
                        "#272727".toColorInt()
                    )
                }

                GOLD -> {
                    Pair(
                        "#34270A".toColorInt(),
                        "#272727".toColorInt()
                    )
                }

                PLATINUM -> {
                    Pair(Color.WHITE, Color.WHITE)
                }

                BLACK -> {
                    Pair(Color.WHITE, Color.WHITE)
                }

                else -> {
                    return if (mtwCardTextType == ApiMtwCardTextType.LIGHT) {
                        Pair(Color.WHITE, Color.WHITE)
                    } else {
                        Pair(Color.BLACK, Color.BLACK)
                    }
                }
            }
        }
}

@JsonClass(generateAdapter = true)
data class ApiNft(
    // val index: Int?,
    val ownerAddress: String? = null,
    val name: String? = null,
    val address: String,
    val thumbnail: String?,
    val image: String?,
    val description: String? = null,
    val collectionName: String? = null,
    val collectionAddress: String? = null,
    val isOnSale: Boolean,
    val isHidden: Boolean? = null,
    val isOnFragment: Boolean? = null,
    val isTelegramGift: Boolean? = null,
    val isScam: Boolean? = null,
    val metadata: ApiNftMetadata? = null
) : WEquatable<ApiNft> {

    companion object {
        fun fromJson(jsonObject: JSONObject): ApiNft? {
            val adapter = WalletCore.moshi.adapter(ApiNft::class.java)
            return adapter.fromJson(jsonObject.toString())
        }
    }

    fun toDictionary(): JSONObject {
        val adapter = WalletCore.moshi.adapter(ApiNft::class.java)
        return JSONObject(adapter.toJson(this))
    }

    fun isStandalone() = collectionName.isNullOrBlank()

    val isMtwCard: Boolean
        get() {
            return metadata?.mtwCardId != null
        }
    val isInstalledMtwCard: Boolean
        get() {
            val installedCard = WGlobalStorage.getCardBackgroundNft(AccountStore.activeAccountId!!)
            installedCard?.let {
                val installedNft = fromJson(installedCard)!!
                return metadata?.mtwCardId == installedNft.metadata?.mtwCardId
            }
            return false
        }
    val isInstalledMtwCardPalette: Boolean
        get() {
            val installedPaletteNft =
                WGlobalStorage.getAccentColorNft(AccountStore.activeAccountId!!)
            installedPaletteNft?.let {
                val installedNft = fromJson(installedPaletteNft)!!
                return metadata?.mtwCardId == installedNft.metadata?.mtwCardId
            }
            return false
        }

    var fragmentUrl: String? = when {
        metadata?.fragmentUrl != null -> metadata.fragmentUrl
        collectionName?.lowercase()?.contains("numbers") ?: false ->
            "https://fragment.com/number/${name?.replace(Regex("[^0-9]"), "")}"

        else ->
            "https://fragment.com/username/${name?.substring(1).let { Uri.encode(it) } ?: ""}"
    }

    val isTonDns: Boolean
        get() {
            return collectionAddress == TON_DNS_COLLECTION
        }
    val tonDnsUrl: String
        get() {
            return "https://dns.ton.org/#${
                name?.replace(
                    Regex("\\.ton$", RegexOption.IGNORE_CASE),
                    ""
                )
            }"
        }
    val tonscanUrl: String
        get() {
            return "${ExplorerHelpers.tonScanUrl(WalletCore.activeNetwork)}nft/${address}"
        }

    val collectionUrl: String
        get() {
            return "https://getgems.io/collection/${collectionAddress}"
        }

    fun shouldHide(): Boolean {
        if (NftStore.nftData?.whitelistedNftAddresses?.contains(address) == true)
            return false
        return isHidden == true || NftStore.nftData?.blacklistedNftAddresses?.contains(address) == true
    }

    fun canRenew(): Boolean {
        return NftStore.nftData?.expirationByAddress?.contains(address) == true
    }

    fun canLinkToAddress(): Boolean {
        return isTonDns
    }

    override fun isSame(comparing: WEquatable<*>): Boolean {
        if (comparing is ApiNft)
            return address == comparing.address
        return false
    }

    override fun isChanged(comparing: WEquatable<*>): Boolean {
        if (comparing is ApiNft)
            return isHidden != comparing.isHidden || isOnSale != comparing.isOnSale
        return true
    }
}
