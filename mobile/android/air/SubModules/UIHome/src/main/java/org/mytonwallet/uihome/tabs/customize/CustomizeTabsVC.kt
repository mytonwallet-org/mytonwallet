package org.mytonwallet.uihome.tabs.customize

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Rect
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.constraintlayout.widget.ConstraintLayout
import kotlin.math.abs
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.uihome.tabs.AppTabsManager

class CustomizeTabsVC(context: Context) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "CustomizeTabs"

    override val shouldDisplayBottomBar = true

    companion object {
        private const val TOP_PADDING = 16
        private const val ZONE_HEIGHT = 70
        private const val SEPARATOR_HEIGHT = 60
        private const val CONTENT_HEIGHT =
            TOP_PADDING + ZONE_HEIGHT + SEPARATOR_HEIGHT + ZONE_HEIGHT
        private const val EDGE_MARGIN = 16
        private const val TILE_WIDTH = 72
        private const val ICON_SIZE = 28
        private const val LABEL_SIZE = 12f
        private const val DRAG_SCALE = 1.1f
        private const val ANIMATION_DURATION = 200L
    }

    private val twoZoneView = TwoZoneView(context).apply {
        id = View.generateViewId()
    }

    private val hintLabel = WLabel(context).apply {
        id = View.generateViewId()
        text = LocaleController.getString("Tap or drag to add tabs.")
        setStyle(13f)
        gravity = Gravity.CENTER
    }

    private val resetButton = WButton(context).apply {
        id = View.generateViewId()
        text = LocaleController.getString("Reset")
        setOnClickListener { twoZoneView.resetToDefault() }
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Customize Tabs"))
        setupNavBar(true)

        view.addView(twoZoneView, ConstraintLayout.LayoutParams(0, CONTENT_HEIGHT.dp))
        view.addView(
            hintLabel,
            ConstraintLayout.LayoutParams(
                ConstraintLayout.LayoutParams.WRAP_CONTENT,
                ConstraintLayout.LayoutParams.WRAP_CONTENT
            )
        )
        view.addView(resetButton, ConstraintLayout.LayoutParams(0, 50.dp))
        view.setConstraints {
            topToBottom(twoZoneView, navigationBar!!)
            toCenterX(twoZoneView)
            topToBottom(hintLabel, twoZoneView, 16f)
            toCenterX(hintLabel)
            toCenterX(resetButton, 16f)
        }

        twoZoneView.onOrderChanged = { updateResetButton() }
        updateResetButton()
        updateTheme()
        insetsUpdated()
    }

    private fun updateResetButton() {
        resetButton.isEnabled = AppTabsManager.isCustomized
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        hintLabel.setTextColor(WColor.SecondaryText.color)
        twoZoneView.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setConstraints {
            toBottomPx(
                resetButton,
                16.dp + (navigationController?.bottomInset ?: 0)
            )
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        twoZoneView.cancelInteractions()
    }

    // Two-zone drag view //////////////////////////////////////////////////////////////////////////

    private inner class TileView(val tab: AppTabsManager.AppTab) : FrameLayout(context) {
        private val icon = ImageView(context).apply {
            setImageResource(tab.filledIconRes)
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        private val label = WLabel(context).apply {
            text = LocaleController.getString(tab.labelKey)
            textSize = LABEL_SIZE
            typeface = WFont.Medium.typeface
            gravity = Gravity.CENTER
            setSingleLine(true)
        }

        init {
            addView(
                icon,
                LayoutParams(
                    ICON_SIZE.dp,
                    ICON_SIZE.dp,
                    Gravity.CENTER_HORIZONTAL or Gravity.TOP
                ).apply { topMargin = 13.dp }
            )
            addView(
                label,
                LayoutParams(
                    LayoutParams.WRAP_CONTENT,
                    LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER_HORIZONTAL or Gravity.BOTTOM
                ).apply { bottomMargin = 13.dp }
            )
            applyTint()
        }

        fun applyTint() {
            val tint = if (tab.isRequired) WColor.SecondaryText.color else WColor.PrimaryText.color
            icon.setColorFilter(tint)
            label.setTextColor(tint)
        }
    }

    private inner class TwoZoneView(context: Context) : ViewGroup(context) {
        private val barBackground = View(context)
        private val paletteBackground = View(context)
        private val separatorLabel = WLabel(context).apply {
            text = LocaleController.getString("Add Tab")
            setStyle(17f, WFont.Medium)
            gravity = Gravity.CENTER
        }
        private val tiles = LinkedHashMap<String, TileView>()

        private var barIds = AppTabsManager.orderedTabIds.toMutableList()
        var onOrderChanged: (() -> Unit)? = null

        private val barRect = Rect()
        private val paletteRect = Rect()

        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private var touchTileId: String? = null
        private var longPressPending = false
        private var downX = 0f
        private var downY = 0f
        private var lastX = 0f
        private var lastY = 0f
        private val longPressRunnable = Runnable { touchTileId?.let { beginDrag(it) } }

        // Drag state: while draggedId is set, it is excluded from slot layout and the gap
        // (gapBarIndex XOR gapPaletteIndex) marks where it would land.
        private var draggedId: String? = null
        private var gapBarIndex = -1
        private var gapPaletteIndex = -1
        private var settling = false

        init {
            clipChildren = false
            addView(barBackground)
            addView(paletteBackground)
            addView(separatorLabel)
            AppTabsManager.registeredTabs.forEach { tab ->
                tiles[tab.id] = TileView(tab).also(::addView)
            }
        }

        fun updateTheme() {
            barBackground.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
            paletteBackground.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BLOCK_RADIUS.dp
            )
            separatorLabel.setTextColor(WColor.SecondaryText.color)
            tiles.values.forEach { it.applyTint() }
        }

        fun cancelInteractions() {
            removeCallbacks(longPressRunnable)
            tiles.values.forEach { it.animate().cancel() }
        }

        fun resetToDefault() {
            if (draggedId != null || settling) return
            barIds = AppTabsManager.defaultTabIds.toMutableList()
            layoutTiles(animated = true)
            commitOrder()
        }

        // Geometry ////////////////////////////////////////////////////////////////////////////////

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val width = MeasureSpec.getSize(widthMeasureSpec)
            setMeasuredDimension(width, CONTENT_HEIGHT.dp)
            val zoneWidthSpec =
                MeasureSpec.makeMeasureSpec(width - 2 * EDGE_MARGIN.dp, MeasureSpec.EXACTLY)
            val zoneHeightSpec = MeasureSpec.makeMeasureSpec(ZONE_HEIGHT.dp, MeasureSpec.EXACTLY)
            barBackground.measure(zoneWidthSpec, zoneHeightSpec)
            paletteBackground.measure(zoneWidthSpec, zoneHeightSpec)
            separatorLabel.measure(
                zoneWidthSpec,
                MeasureSpec.makeMeasureSpec(SEPARATOR_HEIGHT.dp, MeasureSpec.EXACTLY)
            )
            val tileWidthSpec = MeasureSpec.makeMeasureSpec(TILE_WIDTH.dp, MeasureSpec.EXACTLY)
            tiles.values.forEach { it.measure(tileWidthSpec, zoneHeightSpec) }
        }

        override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
            barRect.set(
                EDGE_MARGIN.dp,
                TOP_PADDING.dp,
                width - EDGE_MARGIN.dp,
                TOP_PADDING.dp + ZONE_HEIGHT.dp
            )
            paletteRect.set(
                barRect.left,
                barRect.bottom + SEPARATOR_HEIGHT.dp,
                barRect.right,
                barRect.bottom + SEPARATOR_HEIGHT.dp + ZONE_HEIGHT.dp
            )
            barBackground.layout(barRect.left, barRect.top, barRect.right, barRect.bottom)
            paletteBackground.layout(
                paletteRect.left,
                paletteRect.top,
                paletteRect.right,
                paletteRect.bottom
            )
            separatorLabel.layout(barRect.left, barRect.bottom, barRect.right, paletteRect.top)
            // Tiles are laid out at the origin and positioned purely via x/y translations, so
            // layout passes never move them behind the animations' back.
            tiles.values.forEach { it.layout(0, 0, TILE_WIDTH.dp, ZONE_HEIGHT.dp) }
            if (changed) layoutTiles(animated = false)
        }

        private fun paletteIds(): List<String> {
            val dragged = draggedId
            return AppTabsManager.registeredTabs.map { it.id }
                .filter { it !in barIds && it != dragged }
        }

        /** Palette index the dragged tab would take (registered order among the future palette). */
        private fun palettePreviewIndex(id: String): Int =
            AppTabsManager.registeredTabs.map { it.id }
                .filter { it == id || it !in barIds }
                .indexOf(id)
                .coerceAtLeast(0)

        private fun barSlotX(index: Int, count: Int): Float {
            val visualIndex = if (LocaleController.isRTL) count - 1 - index else index
            val slotWidth = barRect.width().toFloat() / count
            return barRect.left + slotWidth * visualIndex + (slotWidth - TILE_WIDTH.dp) / 2f
        }

        private fun paletteSlotX(index: Int, count: Int): Float {
            val visualIndex = if (LocaleController.isRTL) count - 1 - index else index
            val start = paletteRect.left + (paletteRect.width() - count * TILE_WIDTH.dp) / 2f
            return start + visualIndex * TILE_WIDTH.dp
        }

        /** Moves every tile (except the dragged one) to its slot, leaving room for the gap. */
        private fun layoutTiles(animated: Boolean) {
            if (width == 0) return
            val dragged = draggedId
            val bar = mutableListOf<String?>()
            barIds.forEach { if (it != dragged) bar.add(it) }
            if (dragged != null && gapBarIndex >= 0) {
                bar.add(gapBarIndex.coerceIn(0, bar.size), null)
            }
            val palette = mutableListOf<String?>()
            paletteIds().forEach { palette.add(it) }
            if (dragged != null && gapPaletteIndex >= 0) {
                palette.add(gapPaletteIndex.coerceIn(0, palette.size), null)
            }

            bar.forEachIndexed { index, id ->
                id?.let {
                    positionTile(
                        tiles[it] ?: return@let,
                        barSlotX(index, bar.size),
                        barRect.top.toFloat(),
                        animated
                    )
                }
            }
            palette.forEachIndexed { index, id ->
                id?.let {
                    positionTile(
                        tiles[it] ?: return@let,
                        paletteSlotX(index, palette.size),
                        paletteRect.top.toFloat(),
                        animated
                    )
                }
            }
        }

        private fun positionTile(tile: View, x: Float, y: Float, animated: Boolean) {
            if (animated && WGlobalStorage.getAreAnimationsActive()) {
                if (tile.x == x && tile.y == y) return
                tile.animate().x(x).y(y)
                    .setDuration(ANIMATION_DURATION)
                    .setInterpolator(CubicBezierInterpolator.EASE_OUT)
                    .start()
            } else {
                tile.animate().cancel()
                tile.x = x
                tile.y = y
            }
        }

        // Gestures ////////////////////////////////////////////////////////////////////////////////

        private fun findTileAt(x: Float, y: Float): TileView? = tiles.values.lastOrNull {
            x >= it.x && x <= it.x + it.width && y >= it.y && y <= it.y + it.height
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(ev: MotionEvent): Boolean {
            lastX = ev.x
            lastY = ev.y
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    if (settling) return false
                    val tile = findTileAt(ev.x, ev.y) ?: return false
                    touchTileId = tile.tab.id
                    longPressPending = true
                    downX = ev.x
                    downY = ev.y
                    parent?.requestDisallowInterceptTouchEvent(true)
                    postDelayed(longPressRunnable, ViewConfiguration.getLongPressTimeout().toLong())
                    return true
                }

                MotionEvent.ACTION_MOVE -> {
                    if (draggedId != null) {
                        onDragMove(ev.x, ev.y)
                    } else if (longPressPending &&
                        (abs(ev.x - downX) > touchSlop || abs(ev.y - downY) > touchSlop)
                    ) {
                        longPressPending = false
                        removeCallbacks(longPressRunnable)
                    }
                    return true
                }

                MotionEvent.ACTION_UP -> {
                    removeCallbacks(longPressRunnable)
                    if (draggedId != null) {
                        finishDrag()
                    } else if (longPressPending) {
                        touchTileId?.let { onTileTap(it) }
                    }
                    longPressPending = false
                    touchTileId = null
                    return true
                }

                MotionEvent.ACTION_CANCEL -> {
                    removeCallbacks(longPressRunnable)
                    if (draggedId != null) finishDrag()
                    longPressPending = false
                    touchTileId = null
                    return true
                }
            }
            return super.onTouchEvent(ev)
        }

        private fun onTileTap(id: String) {
            val tile = tiles[id] ?: return
            if (tile.tab.isRequired) return
            if (id in barIds) barIds.remove(id) else barIds.add(id)
            Haptics.play(this, HapticType.LIGHT_TAP)
            layoutTiles(animated = true)
            commitOrder()
        }

        private fun beginDrag(id: String) {
            if (draggedId != null || settling) return
            val tile = tiles[id] ?: return
            longPressPending = false
            draggedId = id
            grabDX = lastX - tile.x
            grabDY = lastY - tile.y
            if (id in barIds) {
                gapBarIndex = barIds.indexOf(id)
                gapPaletteIndex = -1
            } else {
                gapBarIndex = -1
                gapPaletteIndex = palettePreviewIndex(id)
            }
            tile.elevation = 8f.dp
            if (WGlobalStorage.getAreAnimationsActive()) {
                tile.animate().scaleX(DRAG_SCALE).scaleY(DRAG_SCALE)
                    .setDuration(120)
                    .setInterpolator(CubicBezierInterpolator.EASE_OUT)
                    .start()
            }
            parent?.requestDisallowInterceptTouchEvent(true)
            Haptics.play(this, HapticType.DRAG)
        }

        private var grabDX = 0f
        private var grabDY = 0f

        private fun onDragMove(x: Float, y: Float) {
            val id = draggedId ?: return
            val tile = tiles[id] ?: return
            var tileX = x - grabDX
            var tileY = y - grabDY
            if (tile.tab.isRequired) {
                // Locked tabs never leave the bar.
                tileX = tileX.coerceIn(
                    barRect.left.toFloat(),
                    (barRect.right - TILE_WIDTH.dp).toFloat()
                )
                tileY = tileY.coerceIn(
                    barRect.top.toFloat(),
                    (barRect.bottom - ZONE_HEIGHT.dp).toFloat()
                )
            }
            tile.x = tileX
            tile.y = tileY

            val centerX = tileX + TILE_WIDTH.dp / 2f
            val centerY = tileY + ZONE_HEIGHT.dp / 2f
            if (tile.tab.isRequired || barRect.contains(centerX.toInt(), centerY.toInt())) {
                // Hover slot from fixed slot geometry (not animating view positions), so the gap
                // never oscillates.
                val count = barIds.count { it != id } + 1
                val slotWidth = barRect.width().toFloat() / count
                val visualIndex =
                    ((centerX - barRect.left) / slotWidth).toInt().coerceIn(0, count - 1)
                val index = if (LocaleController.isRTL) count - 1 - visualIndex else visualIndex
                if (gapBarIndex != index || gapPaletteIndex != -1) {
                    gapBarIndex = index
                    gapPaletteIndex = -1
                    layoutTiles(animated = true)
                    Haptics.play(this, HapticType.DRAG)
                }
            } else {
                val index = palettePreviewIndex(id)
                if (gapPaletteIndex != index || gapBarIndex != -1) {
                    gapPaletteIndex = index
                    gapBarIndex = -1
                    layoutTiles(animated = true)
                    Haptics.play(this, HapticType.DRAG)
                }
            }
        }

        private fun finishDrag() {
            val id = draggedId ?: return
            val tile = tiles[id] ?: return

            val newBarIds = barIds.filter { it != id }.toMutableList()
            val targetX: Float
            val targetY: Float
            if (gapBarIndex >= 0) {
                val index = gapBarIndex.coerceIn(0, newBarIds.size)
                newBarIds.add(index, id)
                targetX = barSlotX(index, newBarIds.size)
                targetY = barRect.top.toFloat()
            } else {
                val paletteCount = AppTabsManager.registeredTabs.size - newBarIds.size
                targetX = paletteSlotX(palettePreviewIndex(id), paletteCount)
                targetY = paletteRect.top.toFloat()
            }
            barIds = newBarIds

            fun settleEnd() {
                tile.elevation = 0f
                draggedId = null
                gapBarIndex = -1
                gapPaletteIndex = -1
                settling = false
                layoutTiles(animated = false)
                commitOrder()
            }

            if (WGlobalStorage.getAreAnimationsActive()) {
                settling = true
                // Keep draggedId set so slot layout keeps the gap open while the tile flies in.
                gapBarIndex = if (gapBarIndex >= 0) barIds.indexOf(id) else -1
                layoutTiles(animated = true)
                tile.animate().x(targetX).y(targetY).scaleX(1f).scaleY(1f)
                    .setDuration(ANIMATION_DURATION)
                    .setInterpolator(CubicBezierInterpolator.EASE_OUT)
                    .withEndAction { settleEnd() }
                    .start()
            } else {
                tile.scaleX = 1f
                tile.scaleY = 1f
                settleEnd()
            }
        }

        private fun commitOrder() {
            AppTabsManager.setTabIds(barIds)
            barIds = AppTabsManager.orderedTabIds.toMutableList()
            onOrderChanged?.invoke()
        }
    }
}
