package org.mytonwallet.uihome.home.actions

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.GradientDrawables
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.glass.GlassFlavor
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.requireDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent

/**
 * Bottom sheet listing every wallet action as a colored round button. Tapping one hands the
 * identifier to [onAction] right away; see [select] for how the sheet then gets out of the way.
 */
class HomeActionsSheetVC(
    context: Context,
    private val onAction: (HeaderActionsView.Identifier) -> Unit
) : WViewController(context),
    WalletCore.EventObserver {
    @Suppress("PropertyName")
    override val TAG = "HomeActionsSheet"

    override val shouldDisplayTopBar = false
    override val isExpandable = false
    override val isSwipeBackAllowed = false

    private class Action(
        val identifier: HeaderActionsView.Identifier,
        val title: String,
        val icon: Drawable,
        val background: () -> GradientDrawable
    )

    private val actions = listOf(
        Action(
            HeaderActionsView.Identifier.BUY,
            LocaleController.getString("Buy"),
            context.requireDrawableCompat(R.drawable.ic_action_buy)
        ) { GradientDrawables.orangeDrawable },
        Action(
            HeaderActionsView.Identifier.RECEIVE,
            LocaleController.getString("Fund"),
            context.requireDrawableCompat(R.drawable.ic_action_fund)
        ) { GradientDrawables.greenDrawable },
        Action(
            HeaderActionsView.Identifier.SWAP,
            LocaleController.getString("Trade"),
            context.requireDrawableCompat(R.drawable.ic_action_trade)
        ) { GradientDrawables.violetDrawable },
        Action(
            HeaderActionsView.Identifier.SELL,
            LocaleController.getString("Sell"),
            context.requireDrawableCompat(R.drawable.ic_action_sell)
        ) { GradientDrawables.redDrawable },
        Action(
            HeaderActionsView.Identifier.SEND,
            LocaleController.getString("Send"),
            context.requireDrawableCompat(R.drawable.ic_action_send)
        ) { GradientDrawables.blueDrawable },
        Action(
            HeaderActionsView.Identifier.EARN,
            LocaleController.getString("Earn"),
            context.requireDrawableCompat(R.drawable.ic_action_earn)
        ) { GradientDrawables.purpleDrawable },
        Action(
            HeaderActionsView.Identifier.SCAN_QR,
            LocaleController.getString("Scan"),
            context.requireDrawableCompat(R.drawable.ic_action_scan)
        ) { GradientDrawables.grayDrawable }
    )

    private val handleView = View(context).apply { id = View.generateViewId() }

    private val labels = ArrayList<WLabel>()
    private val circles = ArrayList<Pair<FrameLayout, Action>>()
    private val ripples = ArrayList<WRippleDrawable>()

    private val gridView = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
        actions.chunked(COLUMNS).forEachIndexed { rowIndex, row ->
            val rowView = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
            }
            val rowHeight = (ROW_HEIGHT + 2 * RIPPLE_PADDING).dp
            row.forEach { action ->
                rowView.addView(buildItem(action), LinearLayout.LayoutParams(0, rowHeight, 1f))
            }
            repeat(COLUMNS - row.size) {
                rowView.addView(View(context), LinearLayout.LayoutParams(0, rowHeight, 1f))
            }
            addView(
                rowView,
                LinearLayout.LayoutParams(MATCH_PARENT, rowHeight).apply {
                    topMargin = if (rowIndex == 0) 0 else (ROW_SPACING - 2 * RIPPLE_PADDING).dp
                }
            )
        }
    }

    private fun buildItem(action: Action): View {
        val iconView = AppCompatImageView(context).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageDrawable(action.icon)
            setColorFilter(Color.WHITE)
        }
        val circle = FrameLayout(context).apply {
            addView(
                iconView,
                FrameLayout.LayoutParams(ICON_INNER_SIZE.dp, ICON_INNER_SIZE.dp, Gravity.CENTER)
            )
        }
        circles.add(circle to action)
        val label = WLabel(context).apply {
            gravity = Gravity.CENTER
            setSingleLine()
            setStyle(16f, WFont.Medium)
            text = action.title
        }
        labels.add(label)
        val ripple = WRippleDrawable.create(ITEM_RADIUS.dp)
        ripples.add(ripple)
        return FrameLayout(context).apply {
            background = ripple
            isClickable = true
            setOnClickListener { select(action.identifier) }
            addView(
                circle,
                FrameLayout.LayoutParams(ICON_SIZE.dp, ICON_SIZE.dp, Gravity.CENTER_HORIZONTAL)
                    .apply { topMargin = RIPPLE_PADDING.dp }
            )
            addView(
                label,
                FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.BOTTOM)
                    .apply { bottomMargin = RIPPLE_PADDING.dp }
            )
        }
    }

    private var isSelecting = false
    private var pendingRemoveSheet: (() -> Unit)? = null

    // The target screen presents right away on top of this sheet; once that present has finished
    // the sheet is removed from underneath it without any animation. An action that presents
    // nothing (e.g. a dialog) just dismisses the sheet normally.
    private fun select(identifier: HeaderActionsView.Identifier) {
        if (isSelecting) return
        isSelecting = true
        val window = window ?: return
        val ownNav = navigationController ?: return
        val removeSheet: () -> Unit = { window.dismissNav(ownNav) }
        pendingRemoveSheet = removeSheet
        window.doOnNextPresentCompleted(removeSheet)
        onAction(identifier)
        if (window.navigationControllers.lastOrNull() === ownNav) {
            clearPendingRemoveSheet()
            window.dismissLastNav()
        }
    }

    private val contentView = WView(context).apply { id = View.generateViewId() }

    private val blurBackground = WGlassView(context).apply { flavor = GlassFlavor.FROSTED }

    override fun setupViews() {
        super.setupViews()
        WalletCore.registerObserver(this)

        view.addView(blurBackground, ConstraintLayout.LayoutParams(0, 0))
        window?.navigationControllers
            ?.let { navs -> navs.getOrNull(navs.indexOf(navigationController) - 1) }
            ?.let { blurBackground.setupWith(it) }

        contentView.addView(
            handleView,
            ConstraintLayout.LayoutParams(HANDLE_WIDTH.dp, HANDLE_HEIGHT.dp)
        )
        contentView.addView(gridView, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        contentView.setConstraints {
            toTop(handleView, HANDLE_TOP_MARGIN.toFloat())
            toCenterX(handleView)
            topToBottom(gridView, handleView, (GRID_TOP_MARGIN - RIPPLE_PADDING).toFloat())
            toCenterX(gridView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
        }
        view.addView(contentView, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.setConstraints {
            allEdges(blurBackground)
            allEdges(contentView)
        }

        updateTheme()
    }

    private fun clearPendingRemoveSheet() {
        pendingRemoveSheet?.let { window?.removeOnNextPresentCompleted(it) }
        pendingRemoveSheet = null
    }

    override fun onDestroy() {
        super.onDestroy()
        clearPendingRemoveSheet()
        WalletCore.unregisterObserver(this)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        if (walletEvent !is WalletEvent.WideLayoutChanged) return
        window?.dismissNav(navigationController ?: return, animated = false)
    }

    override val isTinted = true
    override fun updateTheme() {
        super.updateTheme()
        val floating = (navigationController?.floatingSheetInset ?: 0) > 0
        view.setBackgroundColor(
            Color.TRANSPARENT,
            ViewConstants.BLOCK_RADIUS.dp,
            if (floating) ViewConstants.BLOCK_RADIUS.dp else 0f,
            clipToBounds = true
        )
        blurBackground.setProvider(
            GlassProviders.plain(WColor.Background, BLUR_OVERLAY_ALPHA / 255f)
        )
        handleView.setBackgroundColor(
            WColor.SecondaryText.color.colorWithAlpha(90),
            HANDLE_HEIGHT.dp / 2f
        )
        labels.forEach { it.setTextColor(WColor.PrimaryText.color) }
        ripples.forEach { it.rippleColor = WColor.BackgroundRipple.color }
        circles.forEach { (circle, action) ->
            val fill = action.background().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = ICON_RADIUS.dp.toFloat()
            }
            circle.background = LayerDrawable(arrayOf(fill, GradientRingDrawable()))
        }
    }

    private val bottomInset: Int
        get() = navigationController?.getSystemBars()?.bottom
            ?: window?.systemBars?.bottom
            ?: 0

    override fun getModalHalfExpandedHeight(): Int {
        val rows = (actions.size + COLUMNS - 1) / COLUMNS
        val gridHeight = rows * ROW_HEIGHT + (rows - 1) * ROW_SPACING
        val contentHeight =
            HANDLE_TOP_MARGIN + HANDLE_HEIGHT + GRID_TOP_MARGIN + gridHeight + BOTTOM_MARGIN
        return contentHeight.dp + bottomInset
    }

    private var appliedHeight: Int? = null
    override fun insetsUpdated() {
        super.insetsUpdated()
        contentView.setPadding(0, 0, 0, BOTTOM_MARGIN.dp + bottomInset)
        val height = getModalHalfExpandedHeight()
        if (appliedHeight != null && appliedHeight != height) {
            navigationController?.onBottomSheetHeightChanged()
        }
        appliedHeight = height
    }

    private class GradientRingDrawable : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = RING_WIDTH.dp.toFloat()
        }
        private val oval = RectF()

        override fun onBoundsChange(bounds: Rect) {
            val inset = paint.strokeWidth / 2f
            oval.set(
                bounds.left + inset,
                bounds.top + inset,
                bounds.right - inset,
                bounds.bottom - inset
            )
            paint.shader = LinearGradient(
                0f,
                oval.top,
                0f,
                oval.bottom,
                Color.BLACK.colorWithAlpha(RING_TOP_ALPHA),
                Color.BLACK.colorWithAlpha(RING_BOTTOM_ALPHA),
                Shader.TileMode.CLAMP
            )
        }

        override fun draw(canvas: Canvas) {
            val radius = ICON_RADIUS.dp - paint.strokeWidth / 2f
            canvas.drawRoundRect(oval, radius, radius, paint)
        }

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    companion object {
        private const val COLUMNS = 3
        private const val RING_WIDTH = 1
        private const val RING_TOP_ALPHA = 13
        private const val RING_BOTTOM_ALPHA = 26
        private const val ICON_SIZE = 68
        private const val ICON_RADIUS = ICON_SIZE / 2
        private const val ITEM_RADIUS = 12f
        private const val RIPPLE_PADDING = 8
        private const val ICON_INNER_SIZE = 40
        private const val ROW_HEIGHT = 96
        private const val ROW_SPACING = 26
        private const val HANDLE_WIDTH = 44
        private const val HANDLE_HEIGHT = 5
        private const val HANDLE_TOP_MARGIN = 13
        private const val GRID_TOP_MARGIN = 24
        private const val BOTTOM_MARGIN = 24
        private const val BLUR_OVERLAY_ALPHA = 204
    }
}
