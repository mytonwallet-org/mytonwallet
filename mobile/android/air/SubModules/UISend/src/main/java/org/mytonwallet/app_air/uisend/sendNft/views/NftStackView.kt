package org.mytonwallet.app_air.uisend.sendNft.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.widget.FrameLayout
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

@SuppressLint("ViewConstructor")
class NftStackView(context: Context, nfts: List<ApiNft>) : FrameLayout(context) {

    companion object {
        private const val MAX_ITEMS = 10
        private const val IMAGE_SIZE_DP = 80
        private const val MIN_OVERLAP_DP = 24
        const val RING_WIDTH_DP = 2
        private const val CORNER_RADIUS_DP = 16f
    }

    private val cards = nfts.take(MAX_ITEMS).map { nft ->
        WCustomImageView(context).apply {
            id = View.generateViewId()
            defaultRounding = Content.Rounding.Radius(CORNER_RADIUS_DP.dp)
            background = GradientDrawable().apply {
                cornerRadius = CORNER_RADIUS_DP.dp + RING_WIDTH_DP.dp
                setColor(WColor.SecondaryBackground.color)
            }
            setPadding(RING_WIDTH_DP.dp, RING_WIDTH_DP.dp, RING_WIDTH_DP.dp, RING_WIDTH_DP.dp)
            set(Content.ofUrl(nft.thumbnail ?: nft.image ?: ""))
        }
    }

    init {
        id = View.generateViewId()
        clipChildren = false
        cards.forEach { addView(it, LayoutParams(0, 0)) }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val cardSize = IMAGE_SIZE_DP.dp + 2 * RING_WIDTH_DP.dp
        val spec = MeasureSpec.makeMeasureSpec(cardSize, MeasureSpec.EXACTLY)
        cards.forEach { it.measure(spec, spec) }
        setMeasuredDimension(width, cardSize)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val width = right - left
        val cardSize = bottom - top
        val count = cards.size
        val step = if (count > 1) {
            min(
                (IMAGE_SIZE_DP - MIN_OVERLAP_DP).dp.toFloat(),
                (width - cardSize).toFloat() / (count - 1)
            )
        } else {
            0f
        }
        val startX = (width - cardSize - step * (count - 1)) / 2f
        cards.forEachIndexed { index, card ->
            val x = (startX + index * step).roundToInt()
            card.layout(x, 0, x + cardSize, cardSize)
        }
    }
}
