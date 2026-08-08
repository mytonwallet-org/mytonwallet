package org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.views

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.view.View
import kotlin.math.exp
import kotlin.math.max
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain

class ChainIconStackView(context: Context) : View(context) {

    companion object {
        val ICON_SIZE = 36.dp
        private val MAX_SPACING = ICON_SIZE * 13f / 14f
        private val MIN_SPACING = ICON_SIZE * 2f / 7f
        private const val SPACING_DECAY = 0.12f
        private val MASK_GAP = ICON_SIZE / 18f * 0.7f
    }

    init {
        id = generateViewId()
    }

    private var icons: List<Drawable> = emptyList()

    fun configure(chains: List<MBlockchain>) {
        icons = chains.mapNotNull { chain -> context.getDrawableCompat(chain.icon) }
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (icons.isEmpty()) return

        val iconSize = ICON_SIZE.toFloat()
        val spacings = spacings(icons.size, width.toFloat())
        val isRtl = layoutDirection == LAYOUT_DIRECTION_RTL
        val direction = if (isRtl) -1f else 1f
        val top = (height - iconSize) / 2f

        val positions = FloatArray(icons.size)
        var x = if (isRtl) width - iconSize else 0f
        for (index in icons.indices) {
            positions[index] = x
            if (index < spacings.size) x += direction * spacings[index]
        }

        for (index in icons.indices.reversed()) {
            val left = positions[index]
            val path = Path().apply {
                fillType = Path.FillType.EVEN_ODD
                addOval(RectF(left, top, left + iconSize, top + iconSize), Path.Direction.CW)
                if (index > 0) {
                    val previousLeft = positions[index - 1]
                    addOval(
                        RectF(
                            previousLeft - MASK_GAP,
                            top - MASK_GAP,
                            previousLeft + iconSize + MASK_GAP,
                            top + iconSize + MASK_GAP
                        ),
                        Path.Direction.CW
                    )
                }
            }
            val checkpoint = canvas.save()
            canvas.clipPath(path)
            icons[index].setBounds(
                left.toInt(),
                top.toInt(),
                (left + iconSize).toInt(),
                (top + iconSize).toInt()
            )
            icons[index].draw(canvas)
            canvas.restoreToCount(checkpoint)
        }
    }

    private fun spacings(iconCount: Int, availableWidth: Float): List<Float> {
        if (iconCount <= 1) return emptyList()

        val spacingCount = iconCount - 1
        val availableSpacing = max(0f, availableWidth - ICON_SIZE)
        val uniformWidth = MAX_SPACING * spacingCount
        if (availableSpacing >= uniformWidth) return List(spacingCount) { MAX_SPACING }

        val tightenedSpacings = List(spacingCount) { tightenedSpacing(it) }
        val tightenedWidth = tightenedSpacings.sum()
        if (availableSpacing <= tightenedWidth || tightenedWidth >= uniformWidth) {
            val scale = availableSpacing / tightenedWidth
            return tightenedSpacings.map { it * scale }
        }

        val tightening = (uniformWidth - availableSpacing) / (uniformWidth - tightenedWidth)
        return tightenedSpacings.map { MAX_SPACING + tightening * (it - MAX_SPACING) }
    }

    private fun tightenedSpacing(index: Int): Float =
        MIN_SPACING + (MAX_SPACING - MIN_SPACING) * exp(-SPACING_DECAY * index)
}
