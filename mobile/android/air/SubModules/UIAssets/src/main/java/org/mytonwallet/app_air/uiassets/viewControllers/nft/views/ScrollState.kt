package org.mytonwallet.app_air.uiassets.viewControllers.nft.views

import org.mytonwallet.app_air.uiassets.viewControllers.nft.views.NftHeaderView.Companion.EXPAND_PERCENT
import org.mytonwallet.app_air.uiassets.viewControllers.nft.views.NftHeaderView.Companion.OVERSCROLL_OFFSET
import org.mytonwallet.app_air.uiassets.viewControllers.nft.views.NftHeaderView.Companion.TEXTS_FROM_BOTTOM
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt

sealed class ScrollState() {
    companion object {
        const val TITLE_SCALE_FACTOR = 0.323f
        const val SUBTITLE_SCALE_FACTOR = 0.15f
    }

    // AVATAR IMAGE ////////////////////////////////////////////////////////////////////////////////
    abstract val avatarWidth: Int
    abstract val avatarHeight: Int
    abstract val avatarRounding: Float
    abstract val avatarTranslationX: Float
    abstract val avatarTranslationY: Float
    abstract val avatarScale: Float

    // TEXTS ///////////////////////////////////////////////////////////////////////////////////////
    abstract val titlePivotX: Float
    abstract val titleScale: Float
    abstract val titleTranslationX: Float
    abstract val titleTranslationY: Float
    abstract val subtitlePivotX: Float
    abstract val subtitleScale: Float
    abstract val subtitleTranslationX: Float
    abstract val subtitleTranslationY: Float
    abstract val subtitleAlpha: Float

    // NORMAL TO COMPACT ///////////////////////////////////////////////////////////////////////////
    data class NormalToCompact(val headerView: NftHeaderView, val percent: Float) : ScrollState() {
        override val avatarWidth = headerView.imageSize
        override val avatarHeight = headerView.imageSize
        override val avatarRounding = 12f.dp
        override val avatarTranslationX: Float
            get() {
                return lerp(
                    0f,
                    -(headerView.viewWidth - headerView.imageSize) / 2f + 17f,
                    percent
                )
            }
        override val avatarTranslationY: Float
            get() {
                return with(headerView) {
                    lerp(topExtraPadding.toFloat(), topExtraPadding - 105f.dp, percent)
                }
            }
        override val avatarScale: Float
            get() {
                return 1 - percent * 0.72f
            }

        override val titlePivotX: Float
            get() {
                return if (LocaleController.isRTL) headerView.titleLabel.paint.measureText(
                    headerView.titleLabel.text.toString()
                ) else 0f
            }
        override val titleScale = 1 - percent * TITLE_SCALE_FACTOR
        override val titleTranslationX: Float
            get() {
                return lerp(headerView.titleCompactTranslationX, 96f.dp, percent)
            }
        override val titleTranslationY: Float
            get() {
                with(headerView) {
                    return lerp(topExtraPadding + 157f.dp, topExtraPadding - 53f.dp, percent)
                }
            }
        override val subtitlePivotX: Float
            get() {
                return if (LocaleController.isRTL) headerView.subtitleLabel.paint.measureText(
                    headerView.subtitleLabel.text.toString()
                ) else 0f
            }
        override val subtitleScale = 1 - percent * SUBTITLE_SCALE_FACTOR
        override val subtitleTranslationX: Float
            get() {
                return lerp(headerView.subtitleCompactTranslationX, 98f.dp, percent)
            }
        override val subtitleTranslationY: Float
            get() {
                with(headerView) {
                    return lerp(topExtraPadding + 193f.dp, topExtraPadding - 28f.dp, percent)
                }
            }
        override val subtitleAlpha = 1f
    }

    // NORMAL TO EXPAND ////////////////////////////////////////////////////////////////////////////
    data class NormalToExpand(val headerView: NftHeaderView, val percent: Float) : ScrollState() {
        override val avatarWidth: Int
            get() {
                with(headerView) {
                    return (
                        imageSize +
                            (viewWidth - imageSize) * (percent * EXPAND_PERCENT).pow(2)
                        ).roundToInt()
                }
            }
        override val avatarHeight: Int
            get() {
                return avatarWidth
            }
        override val avatarRounding = 12f.dp
        override val avatarTranslationX: Float = 0f
        override val avatarTranslationY: Float = headerView.topExtraPadding.toFloat()
        override val avatarScale = 1f
        override val titlePivotX: Float
            get() {
                return if (LocaleController.isRTL) headerView.titleLabel.paint.measureText(
                    headerView.titleLabel.text.toString()
                ) else 0f
            }
        override val titleScale = 1f
        override val titleTranslationX: Float
            get() {
                return headerView.titleCompactTranslationX * (1 - percent * EXPAND_PERCENT)
            }
        override val titleTranslationY: Float
            get() {
                with(headerView) {
                    return lerp(
                        topExtraPadding + 157f.dp,
                        viewWidth - TEXTS_FROM_BOTTOM.dp - (realScrollOffset - OVERSCROLL_OFFSET.dp),
                        percent * EXPAND_PERCENT
                    )
                }
            }
        override val subtitlePivotX = 0f
        override val subtitleScale = 1f
        override val subtitleTranslationX: Float
            get() {
                return headerView.subtitleCompactTranslationX * (1 - percent * EXPAND_PERCENT)
            }
        override val subtitleTranslationY: Float
            get() {
                return titleTranslationY + 36.dp + 6.dp * percent * EXPAND_PERCENT
            }
        override val subtitleAlpha = 1f
    }

    // EXPANDED ////////////////////////////////////////////////////////////////////////////////////
    data class Expanded(
        val headerView: NftHeaderView,
        val expandStartPercent: Float,
        val percent: Float
    ) : ScrollState() {
        override val avatarWidth: Int
            get() {
                with(headerView) {
                    val minWidth = imageSize +
                        (viewWidth - imageSize) * expandStartPercent.pow(2)
                    return (minWidth + (viewWidth - minWidth) * percent).roundToInt()
                }
            }
        override val avatarHeight: Int
            get() {
                with(headerView) {
                    val minHeight = imageSize +
                        (viewWidth - imageSize) * expandStartPercent.pow(2)
                    val targetHeight = headerView.layoutParams.height
                    return (minHeight + (targetHeight - minHeight) * percent).roundToInt()
                }
            }
        override val avatarRounding: Float
            get() {
                return 12.dp * (1 - percent)
            }
        override val avatarTranslationX: Float = 0f
        override val avatarTranslationY: Float =
            headerView.topExtraPadding.toFloat() * (1 - percent)
        override val avatarScale = 1f
        override val titlePivotX: Float
            get() {
                return if (LocaleController.isRTL) headerView.titleLabel.paint.measureText(
                    headerView.titleLabel.text.toString()
                ) else 0f
            }
        override val titleScale = 1f
        override val titleTranslationX: Float
            get() {
                return lerp(
                    headerView.titleCompactTranslationX * (1 - expandStartPercent),
                    0f,
                    percent
                )
            }
        override val titleTranslationY: Float
            get() {
                with(headerView) {
                    return lerp(
                        topExtraPadding + 157f.dp,
                        viewWidth - TEXTS_FROM_BOTTOM.dp - (realScrollOffset - OVERSCROLL_OFFSET.dp),
                        expandStartPercent + percent * (1 - expandStartPercent)
                    )
                }
            }
        override val subtitlePivotX = 0f
        override val subtitleScale = 1f
        override val subtitleTranslationX: Float
            get() {
                return lerp(
                    headerView.subtitleCompactTranslationX * (1 - expandStartPercent),
                    0.5f.dp,
                    percent
                )
            }
        private val startSubtitleY = 6.dp * expandStartPercent
        override val subtitleTranslationY: Float
            get() {
                return titleTranslationY + 36.dp + startSubtitleY + (6.dp - startSubtitleY) * percent
            }
        override val subtitleAlpha: Float
            get() {
                return 1 - percent * 0.25f
            }
    }

    // OVERSCROLL //////////////////////////////////////////////////////////////////////////////////
    data class OverScroll(val headerView: NftHeaderView, val overscroll: Int) : ScrollState() {
        val correctOverscroll = max(
            OVERSCROLL_OFFSET.dp - headerView.realScrollOffset,
            overscroll
        )

        override val avatarWidth = headerView.viewWidth
        override val avatarHeight = avatarWidth + correctOverscroll
        override val avatarRounding = 0f
        override val avatarTranslationX = 0f
        override val avatarTranslationY = 0f
        override val avatarScale = 1f

        override val titlePivotX: Float
            get() {
                return if (LocaleController.isRTL) headerView.titleLabel.paint.measureText(
                    headerView.titleLabel.text.toString()
                ) else 0f
            }
        override val titleScale = 1f
        override val titleTranslationX = 0f
        override val titleTranslationY: Float
            get() {
                with(headerView) {
                    return viewWidth - TEXTS_FROM_BOTTOM.dp + correctOverscroll.toFloat()
                }
            }
        override val subtitlePivotX = 0f
        override val subtitleScale = 1f
        override val subtitleTranslationX = 0.5f.dp
        override val subtitleTranslationY = titleTranslationY + 42.dp
        override val subtitleAlpha = 0.75f
    }
}
