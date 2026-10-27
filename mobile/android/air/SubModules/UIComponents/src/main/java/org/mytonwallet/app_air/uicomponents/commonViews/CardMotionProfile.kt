package org.mytonwallet.app_air.uicomponents.commonViews

import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardTextType
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

internal data class CardMotionProfile(
    val custom: Boolean,
    val gram: Boolean,
    val material: Int,
    val intensity: Float,
    val black: Boolean,
    val restAngle: Float,
    val contrastLight: Boolean?
) {
    companion object {
        fun from(nft: ApiNft?): CardMotionProfile {
            val custom = nft?.isMtwCard == true
            val type = nft?.metadata?.mtwCardType
            val material = when (type) {
                ApiMtwCardType.BLACK -> 2
                ApiMtwCardType.SILVER, ApiMtwCardType.GOLD, ApiMtwCardType.PLATINUM -> 1
                else -> 0
            }
            val gram = nft == null && ApplicationContextHolder.isGramApp
            val intensity = when {
                gram -> 0f
                !custom -> .28f
                type == ApiMtwCardType.BLACK -> .22f
                type == ApiMtwCardType.PLATINUM -> .22f
                type == ApiMtwCardType.GOLD -> .48f
                else -> .62f
            }
            val angle = if (material != 0) {
                -45f
            } else {
                when (nft?.metadata?.mtwCardBorderShineType) {
                    ApiMtwCardBorderShineType.UP -> -80f
                    ApiMtwCardBorderShineType.DOWN -> 70f
                    ApiMtwCardBorderShineType.LEFT -> -190f
                    ApiMtwCardBorderShineType.RIGHT -> 10f
                    else -> -45f
                }
            }
            return CardMotionProfile(
                custom,
                gram,
                material,
                intensity,
                type == ApiMtwCardType.BLACK,
                angle,
                if (custom &&
                    material == 0
                ) {
                    nft?.metadata?.mtwCardTextType == ApiMtwCardTextType.DARK
                } else {
                    null
                }
            )
        }
    }
}
