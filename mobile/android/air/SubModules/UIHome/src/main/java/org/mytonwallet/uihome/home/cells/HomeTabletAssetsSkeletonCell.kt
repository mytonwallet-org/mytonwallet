package org.mytonwallet.uihome.home.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonContainer
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class HomeTabletAssetsSkeletonCell(
    context: Context,
) : WCell(context), WThemedView, SkeletonContainer {

    companion object {
        private val COLUMN_WIDTH = HomeTabletAssetsCell.COLUMN_WIDTH_DP.dp
        private val COLUMN_GUTTER = HomeTabletAssetsCell.COLUMN_GUTTER_DP.dp

        // Card sits below the header band, exactly like the real ColumnCell content container.
        private val CARD_TOP = HomeTabletAssetsCell.HEADER_HEIGHT_DP.dp

        // Title placeholder, drawn on the page (above the card) like the real column title.
        private val TITLE_BAR_WIDTH = 120.dp
        private val TITLE_BAR_HEIGHT = HomeTabletAssetsCell.TITLE_HEIGHT_DP.dp
        private val TITLE_BAR_RADIUS = 8f.dp

        // Tokens column: token rows (matches SkeletonCell layout).
        private const val TOKEN_ROWS = 5
        private val TOKEN_ROW_HEIGHT = 60.dp

        // Collectibles column: NFT thumbnail grid (matches AssetCell THUMB mode on wide layout).
        private const val NFT_COLUMNS = 3
        private const val NFT_ROWS = 2
        private val NFT_GRID_PADDING = 16.dp
        private val NFT_ITEM_INSET = 4.dp
        private val NFT_ITEM_INSET_Y = 16.dp
        private val NFT_ITEM_RADIUS = 8f.dp
        private val NFT_TITLE_TOP_GAP = 8.dp
        private val NFT_TITLE_HEIGHT = 16.dp
        private val NFT_SUBTITLE_GAP = 6.dp
        private val NFT_SUBTITLE_HEIGHT = 12.dp
        private val NFT_ROW_BOTTOM_GAP = 12.dp

        private const val NFT_COLUMN_INDEX = 1
    }

    private val columnViews = mutableListOf<ColumnView>()

    private val container = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.HORIZONTAL
        clipChildren = false
        clipToPadding = false
    }

    // Item box width inside the NFT grid (3 columns, flush boxes; the gap lives inside each box).
    private val nftItemBox = (COLUMN_WIDTH - 2 * NFT_GRID_PADDING) / NFT_COLUMNS
    private val nftImageSize = nftItemBox - 2 * NFT_ITEM_INSET
    private val nftRowHeight = nftImageSize + NFT_TITLE_TOP_GAP + NFT_TITLE_HEIGHT +
        NFT_SUBTITLE_GAP + NFT_SUBTITLE_HEIGHT + NFT_ROW_BOTTOM_GAP

    private val tokenCardHeight = TOKEN_ROWS * TOKEN_ROW_HEIGHT
    private val nftCardHeight = NFT_ITEM_INSET_Y + NFT_ROWS * nftRowHeight

    override fun setupViews() {
        super.setupViews()
        clipChildren = false
        clipToPadding = false

        // One column per COLUMN_WIDTH+gutter that fits the screen, plus one to cover the edge.
        val screenWidth = context.resources.displayMetrics.widthPixels
        val columnCount = (screenWidth / (COLUMN_WIDTH + COLUMN_GUTTER)).coerceAtLeast(1) + 1
        for (i in 0 until columnCount) {
            val column = ColumnView(context, isNft = i == NFT_COLUMN_INDEX)
            columnViews.add(column)
            container.addView(
                column,
                LinearLayout.LayoutParams(COLUMN_WIDTH, MATCH_PARENT).apply {
                    if (i > 0) marginStart = COLUMN_GUTTER
                }
            )
        }

        addView(container, LayoutParams(WRAP_CONTENT, MATCH_PARENT))
        setConstraints {
            toTop(container)
            toStart(container)
        }
        layoutParams.height =
            CARD_TOP + maxOf(tokenCardHeight, nftCardHeight) + ViewConstants.GAP.dp
        updateTheme()
    }

    override fun updateTheme() {
        columnViews.forEach { it.updateTheme() }
    }

    override fun getChildViewMap(): HashMap<View, Float> {
        val map = HashMap<View, Float>()
        columnViews.forEach { it.collectInto(map) }
        return map
    }

    @SuppressLint("ViewConstructor")
    private inner class ColumnView(context: Context, private val isNft: Boolean) : WView(context) {
        private val titleBar = WBaseView(context)
        private val card = WView(context)

        // Placeholders inside the card, masked by the shimmer (title bar is handled separately).
        private val skeletons = mutableListOf<Pair<View, Float>>()

        init {
            addView(titleBar, LayoutParams(TITLE_BAR_WIDTH, TITLE_BAR_HEIGHT))
            addView(card, LayoutParams(MATCH_PARENT, 0))
            setConstraints {
                toTopPx(titleBar, (CARD_TOP - TITLE_BAR_HEIGHT) / 2)
                toStart(titleBar, 16f)
                toTopPx(card, CARD_TOP)
                toBottomPx(card, ViewConstants.GAP.dp)
                toCenterX(card)
            }

            if (isNft) buildNftGrid() else buildTokenRows()
        }

        private fun buildTokenRows() {
            for (i in 0 until TOKEN_ROWS) {
                val circle = WBaseView(context)
                val title = WBaseView(context)
                val subtitle = WBaseView(context)
                card.addView(circle, LayoutParams(44.dp, 44.dp))
                card.addView(
                    title,
                    LayoutParams(
                        SkeletonCell.TITLE_WIDTH[i % SkeletonCell.TITLE_WIDTH.size].dp,
                        16.dp
                    )
                )
                card.addView(
                    subtitle,
                    LayoutParams(
                        SkeletonCell.SUBTITLE_WIDTH[i % SkeletonCell.SUBTITLE_WIDTH.size].dp,
                        14.dp
                    )
                )
                val top = i * TOKEN_ROW_HEIGHT
                card.setConstraints {
                    toTopPx(circle, top + 6.dp)
                    toStart(circle, 13f)
                    toTopPx(title, top + 12.dp)
                    toStart(title, 68f)
                    toTopPx(subtitle, top + 34.dp)
                    toStart(subtitle, 68f)
                }
                skeletons.add(circle to SkeletonCell.CIRCLE_SKELETON_RADIUS)
                skeletons.add(title to SkeletonCell.TITLE_SKELETON_RADIUS)
                skeletons.add(subtitle to SkeletonCell.SUBTITLE_SKELETON_RADIUS)
            }
        }

        private fun buildNftGrid() {
            for (r in 0 until NFT_ROWS) {
                val rowTop = NFT_ITEM_INSET_Y + r * nftRowHeight
                for (c in 0 until NFT_COLUMNS) {
                    val boxLeft = NFT_GRID_PADDING + c * nftItemBox
                    val image = WBaseView(context)
                    val title = WBaseView(context)
                    val subtitle = WBaseView(context)
                    val titleW = (nftImageSize * 0.7f).toInt()
                    val subtitleW = (nftImageSize * 0.45f).toInt()
                    card.addView(image, LayoutParams(nftImageSize, nftImageSize))
                    card.addView(title, LayoutParams(titleW, NFT_TITLE_HEIGHT))
                    card.addView(subtitle, LayoutParams(subtitleW, NFT_SUBTITLE_HEIGHT))
                    val titleTop = rowTop + nftImageSize + NFT_TITLE_TOP_GAP
                    val subtitleTop = titleTop + NFT_TITLE_HEIGHT + NFT_SUBTITLE_GAP
                    card.setConstraints {
                        toTopPx(image, rowTop)
                        toStartPx(image, boxLeft)
                        toTopPx(title, titleTop)
                        toStartPx(title, boxLeft + 4.dp)
                        toTopPx(subtitle, subtitleTop)
                        toStartPx(subtitle, boxLeft + 4.dp)
                    }
                    skeletons.add(image to NFT_ITEM_RADIUS)
                    skeletons.add(title to SkeletonCell.TITLE_SKELETON_RADIUS)
                    skeletons.add(subtitle to SkeletonCell.SUBTITLE_SKELETON_RADIUS)
                }
            }
        }

        fun updateTheme() {
            card.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp, true)
            titleBar.setBackgroundColor(WColor.ThumbBackground.color, TITLE_BAR_RADIUS)
            skeletons.forEach { (view, radius) ->
                view.setBackgroundColor(WColor.SecondaryBackground.color, radius)
            }
        }

        fun collectInto(map: HashMap<View, Float>) {
            map[titleBar] = TITLE_BAR_RADIUS
            skeletons.forEach { (view, radius) -> map[view] = radius }
        }
    }
}
