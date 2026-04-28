package org.mytonwallet.app_air.uisend.sendNft.views

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextPaint
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import com.google.android.material.chip.ChipGroup
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.sp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WTagView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import kotlin.math.ceil

class WNftTagsChipGroup(context: Context) : ChipGroup(context) {

    private var nfts: List<ApiNft> = emptyList()
    private var renderedVisibleCount: Int? = null
    private var renderedContentWidth: Int? = null

    private val tagTextPaint: TextPaint by lazy {
        TextPaint().apply {
            isAntiAlias = true
            typeface = WFont.Regular.typeface
            textSize = TAG_TEXT_SIZE_SP.sp
        }
    }

    var onMoreClickListener: (() -> Unit)? = null

    init {
        setPaddingDp(16)
        isSingleLine = false
        chipSpacingHorizontal = CHIP_SPACING_DP.dp
        chipSpacingVertical = CHIP_SPACING_DP.dp
    }

    fun configure(nfts: List<ApiNft>) {
        this.nfts = nfts
        renderedVisibleCount = null
        renderedContentWidth = null
        requestLayout()
    }

    @SuppressLint("RestrictedApi")
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val contentWidth = MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight
        if (contentWidth > 0 && renderedContentWidth != contentWidth) {
            renderForWidth(contentWidth)
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    private fun renderForWidth(contentWidth: Int) {
        val visibleCount = calculateVisibleCount(contentWidth)
        if (renderedVisibleCount == visibleCount) {
            return
        }

        removeAllViews()
        nfts.take(visibleCount).forEach { nft ->
            addView(WTagView(context).apply {
                configure(Content.ofUrl(nft.thumbnail ?: nft.image ?: ""), nft.name)
            })
        }

        val remainingNfts = nfts.size - visibleCount
        if (remainingNfts > 0) {
            addView(
                remainingLabel(remainingNfts),
                ViewGroup.LayoutParams(WRAP_CONTENT, TAG_HEIGHT_DP.dp)
            )
        }
        renderedVisibleCount = visibleCount
        renderedContentWidth = contentWidth
    }

    private fun calculateVisibleCount(contentWidth: Int): Int {
        val initialVisibleCount = MAX_ROWS - 1
        if (nfts.size <= initialVisibleCount) {
            return nfts.size
        }
        if (contentWidth <= 0) {
            return initialVisibleCount
        }

        var rows = 1
        var rowWidth = 0
        // guarantee fit, simplified calculation
        repeat(initialVisibleCount) { index ->
            val width = nftTagWidth(nfts[index].name)
            val spacing = if (rowWidth == 0) 0 else CHIP_SPACING_DP.dp
            if (rowWidth > 0 && rowWidth + spacing + width > contentWidth) {
                rows += 1
                rowWidth = width
            } else {
                rowWidth += spacing + width
            }
        }
        var visibleCount = initialVisibleCount

        // try to put as much as we can
        while (visibleCount < nfts.size) {
            val nftWidth = nftTagWidth(nfts[visibleCount].name)
            val nftSpacing = if (rowWidth == 0) 0 else CHIP_SPACING_DP.dp
            val nextRows: Int
            val nextRowWidth: Int
            if (rowWidth > 0 && rowWidth + nftSpacing + nftWidth > contentWidth) {
                nextRows = rows + 1
                nextRowWidth = nftWidth
            } else {
                nextRows = rows
                nextRowWidth = rowWidth + nftSpacing + nftWidth
            }

            val remainingCount = nfts.size - visibleCount - 1
            val rowsWithLabel = if (remainingCount > 0) {
                val labelWidth = remainingLabelWidth(remainingCount)
                val labelSpacing = if (nextRowWidth == 0) 0 else CHIP_SPACING_DP.dp
                if (nextRowWidth > 0 && nextRowWidth + labelSpacing + labelWidth > contentWidth) {
                    nextRows + 1
                } else {
                    nextRows
                }
            } else {
                nextRows
            }

            if (rowsWithLabel > MAX_ROWS) {
                break
            }

            rows = nextRows
            rowWidth = nextRowWidth
            visibleCount += 1
        }

        return visibleCount
    }

    private fun nftTagWidth(title: CharSequence?): Int {
        return TAG_ICON_WIDTH_DP.dp +
            TAG_TEXT_HORIZONTAL_PADDING_DP.dp +
            tagTextPaint.measureTextCeil(title?.toString().orEmpty())
    }

    private fun remainingLabelWidth(remainingCount: Int): Int {
        return tagTextPaint.measureTextCeil(remainingText(remainingCount))
    }

    private fun remainingLabel(remainingCount: Int): WLabel {
        return WLabel(context).apply {
            setStyle(TAG_TEXT_SIZE_SP, WFont.Regular)
            setTextColor(WColor.SecondaryText)
            gravity = Gravity.CENTER_VERTICAL
            text = remainingText(remainingCount)
            setOnClickListener {
                onMoreClickListener?.invoke()
            }
        }
    }

    private fun remainingText(remainingCount: Int): String {
        return LocaleController.getString("%amount% NFTs")
            .replace("%amount%", "+$remainingCount")
    }

    private fun TextPaint.measureTextCeil(text: String): Int {
        return ceil(measureText(text)).toInt()
    }

    private companion object {
        const val MAX_ROWS = 5
        const val TAG_TEXT_SIZE_SP = 14f
        const val TAG_ICON_WIDTH_DP = 28
        const val TAG_TEXT_HORIZONTAL_PADDING_DP = 12
        const val TAG_HEIGHT_DP = 28
        const val CHIP_SPACING_DP = 8
    }
}
