package org.mytonwallet.app_air.walletcore.models

import android.net.Uri
import androidx.core.net.toUri
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.utils.WEquatable
import org.mytonwallet.app_air.walletcore.moshi.IDapp
import org.mytonwallet.app_air.walletcore.stores.ConfigStore

class MExploreSite(json: JSONObject) : WEquatable<MExploreSite>, IDapp {

    override fun isSame(comparing: WEquatable<*>): Boolean {
        if (comparing is MExploreSite)
            return url == comparing.url
        return false
    }

    override fun isChanged(comparing: WEquatable<*>): Boolean {
        if (comparing is MExploreSite)
            return canBeRestricted != comparing.canBeRestricted ||
                isExternal != comparing.isExternal ||
                manifestUrl != comparing.manifestUrl ||
                url != comparing.url
        return true
    }

    override val name: String? = json.optString("name")
    val canBeRestricted: Boolean = json.optBoolean("canBeRestricted")
    val isVerified: Boolean = json.optBoolean("isVerified")
    val isExternal: Boolean = json.optBoolean("isExternal")
    val manifestUrl: String? = json.optString("manifestUrl")
    val description: String? = json.optString("description")
    override val iconUrl: String? = json.optString("icon")
    override val url: String? = json.optString("url")
    val uri: Uri? by lazy { url?.toUri() }
    val isFeatured = json.optBoolean("isFeatured")
    val categoryId = json.optInt("categoryId")
    val extendedIcon: String = json.optString("extendedIcon")
    val badgeText: String = json.optString("badgeText")
    val withBorder: Boolean = json.optBoolean("withBorder")

    val isTelegram: Boolean
        get() {
            return url?.startsWith("https://t.me/") == true
        }

    val canBeShown: Boolean
        get() {
            return ConfigStore.isLimited != true || !canBeRestricted
        }
}
