package org.mytonwallet.app_air.walletcore.moshi

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.net.Uri
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.WEquatable
import org.mytonwallet.app_air.walletcore.TON_DNS_COLLECTION
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.DOWN
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.LEFT
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.RADIOACTIVE
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.RIGHT
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.UP
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
    data class Attribute(
        @Json(name = "trait_type") val traitType: String,
        @Json(name = "value") val value: String?
    )

    val cardImageUrl: String
        get() {
            return "https://static.mytonwallet.org/cards/$mtwCardId.webp"
        }

    fun gradient(radius: Float): LayerDrawable {
        return when (mtwCardBorderShineType) {
            UP -> LayerDrawable(
                arrayOf(
                    ScaledDrawable(createRadialGradient(0.5f, 0f, radius), 0.5f, 1.0f),
                    createLinearGradient()
                )
            )

            DOWN -> LayerDrawable(
                arrayOf(
                    ScaledDrawable(createRadialGradient(0.5f, 1f, radius), 0.5f, 1.0f),
                    createLinearGradient()
                )
            )

            LEFT -> LayerDrawable(
                arrayOf(
                    ScaledDrawable(createRadialGradient(0f, 0.5f, radius), 1.0f, 0.5f),
                    createLinearGradient()
                )
            )

            RIGHT -> LayerDrawable(
                arrayOf(
                    ScaledDrawable(createRadialGradient(1f, 0.5f, radius), 1.0f, 0.5f),
                    createLinearGradient()
                )
            )

            RADIOACTIVE, null -> {
                LayerDrawable(
                    arrayOf(
                        createLinearGradient()
                    )
                )
            }
        }
    }

    class ScaledDrawable(
        private val drawable: Drawable,
        private val scaleX: Float,
        private val scaleY: Float
    ) : Drawable() {

        override fun draw(canvas: Canvas) {
            canvas.save()
            val centerX = bounds.exactCenterX()
            val centerY = bounds.exactCenterY()
            canvas.scale(scaleX, scaleY, centerX, centerY)
            drawable.bounds = bounds
            drawable.draw(canvas)
            canvas.restore()
        }

        override fun setAlpha(alpha: Int) {
            drawable.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            drawable.colorFilter = colorFilter
        }

        override fun getOpacity(): Int {
            return drawable.opacity
        }
    }

    private fun createRadialGradient(
        centerX: Float,
        centerY: Float,
        radius: Float
    ): GradientDrawable {
        return GradientDrawable().apply {
            gradientType = GradientDrawable.RADIAL_GRADIENT
            gradientRadius = radius
            setGradientCenter(centerX, centerY)
            colors = intArrayOf(
                Color.WHITE,
                Color.argb(0, 255, 255, 255)
            )
        }
    }

    val gradientColors: IntArray
        get() {
            if (mtwCardBorderShineType == RADIOACTIVE) {
                val greenColor = Color.parseColor("#5CE850")
                return intArrayOf(greenColor, greenColor)
            }
            return when (mtwCardType) {
                ApiMtwCardType.BLACK -> {
                    intArrayOf(
                        Color.rgb(41, 41, 41),
                        Color.rgb(20, 21, 24),
                    )
                }

                else -> {
                    intArrayOf(
                        Color.argb(217, 186, 188, 194),
                        Color.argb(128, 140, 148, 176),
                    )
                }
            }
        }

    private fun createLinearGradient(): GradientDrawable {
        return GradientDrawable(
            GradientDrawable.Orientation.LEFT_RIGHT,
            gradientColors
        ).apply {
            gradientType = GradientDrawable.LINEAR_GRADIENT
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
