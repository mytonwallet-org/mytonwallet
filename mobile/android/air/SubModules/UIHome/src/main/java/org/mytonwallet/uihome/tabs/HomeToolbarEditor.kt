package org.mytonwallet.uihome.tabs

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewOutlineProvider
import android.view.Window
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.animation.doOnEnd
import androidx.core.view.doOnLayout
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.HomeToolbarActions
import org.mytonwallet.app_air.uicomponents.helpers.HomeToolbarLayout
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.requireDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MToolbarItem
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.uihome.home.actions.HomeActionsSheetVC

internal class HomeToolbarEditor(private val context: Context, private val host: Host) :
    HomeActionsSheetVC.DragHost {

    interface Host {
        val window: WWindow?

        fun getToolbarFrame(): RectF?

        fun beginToolbarEdit(item: MToolbarItem)

        fun moveToolbarEdit(screenX: Float?): Boolean

        fun canToolbarHold(item: MToolbarItem): Boolean

        /** [isAtStart] is the top bar side for [Result.TOP] */
        fun endToolbarEdit(result: Result, drop: Drop? = null, isAtStart: Boolean = false)

        /** Null when the top bar is not shown */
        fun getTopAvatarFrame(isAtStart: Boolean): RectF?

        fun isTopAvatarAtStart(): Boolean

        fun setTopAvatarHeld(isHeld: Boolean)

        fun createToolbarIcon(item: MToolbarItem, scale: Float): View

        fun getToolbarIconSize(item: MToolbarItem): Int

        fun getToolbarButton(item: MToolbarItem): View
    }

    enum class Result { ADD, REMOVE, CANCEL, TOP }

    class Drop(val x: Float, val y: Float, val scale: Float)

    private class Session(
        val item: MToolbarItem,
        var sheet: HomeActionsSheetVC?,
        val isFromToolbar: Boolean,
        val frame: RectF? = null,
        val isFromTop: Boolean = false,
        val onLift: (() -> Unit)? = null
    ) {
        var isPending = onLift != null
        var startX = 0f
        var startY = 0f
        var hasOffset = false
        var offsetX = 0f
        var offsetY = 0f
        var isOnToolbar = isFromToolbar || isFromTop
        var isInside = isFromToolbar
        var isTopAtStart = false

        fun holdFrom(downX: Float, downY: Float) {
            hasOffset = true
            offsetX = x - downX
            offsetY = y - downY
        }

        val isProfile: Boolean
            get() = item == MToolbarItem.ACCOUNTS
        var x = 0f
        var y = 0f
    }

    private var session: Session? = null
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var overlay: Overlay? = null

    val isDragging: Boolean
        get() = session != null

    override fun startActionDrag(sheet: HomeActionsSheetVC, item: MToolbarItem): Boolean {
        if (session != null || overlay != null) return false
        val window = host.window ?: return false
        val frame = sheet.getActionCircleFrame(item) ?: return false
        val overlay = createOverlay(window) ?: return false
        Haptics.play(overlay, HapticType.DRAG)
        overlay.setupGhost(item, sheet, frame)
        overlay.showHint(sheet.screenTop)
        sheet.setDraggedAction(item)
        session = Session(item, sheet, isFromToolbar = false).also {
            it.x = frame.centerX()
            it.y = frame.centerY()
        }
        captureTouches(window)
        return true
    }

    /** With [onLift], the drag waits for the finger to move from [downX], [downY] */
    fun startToolbarDrag(
        item: MToolbarItem,
        frame: RectF,
        onLift: (() -> Unit)? = null,
        downX: Float = frame.centerX(),
        downY: Float = frame.centerY()
    ): Boolean {
        if (session != null || overlay != null) return false
        val window = host.window ?: return false
        val session = Session(item, null, isFromToolbar = true, frame, onLift = onLift).also {
            it.x = frame.centerX()
            it.y = frame.centerY()
            it.startX = downX
            it.startY = downY
            if (onLift != null) it.holdFrom(downX, downY)
        }
        if (onLift == null && !liftToolbarItem(window, session)) return false
        this.session = session
        captureTouches(window)
        return true
    }

    /** Waits for the finger to move from [downX], [downY], then calls [onLift] */
    fun startTopDrag(frame: RectF, onLift: () -> Unit, downX: Float, downY: Float): Boolean {
        if (session != null || overlay != null) return false
        val window = host.window ?: return false
        session = Session(
            MToolbarItem.ACCOUNTS,
            null,
            isFromToolbar = false,
            frame,
            isFromTop = true,
            onLift = onLift
        ).also {
            it.x = frame.centerX()
            it.y = frame.centerY()
            it.startX = downX
            it.startY = downY
            it.holdFrom(downX, downY)
            it.isTopAtStart = host.isTopAvatarAtStart()
        }
        captureTouches(window)
        return true
    }

    private var windowCallback: Window.Callback? = null

    // Takes the rest of the gesture by standing in for the window callback
    private fun captureTouches(activity: WWindow) {
        val window = activity.window
        val original = window.callback
        val now = SystemClock.uptimeMillis()
        val cancel = MotionEvent.obtain(now, now, MotionEvent.ACTION_CANCEL, 0f, 0f, 0)
        original.dispatchTouchEvent(cancel)
        cancel.recycle()
        windowCallback = original
        window.callback = object : Window.Callback by original {
            override fun dispatchTouchEvent(event: MotionEvent): Boolean {
                val action = event.actionMasked
                if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                    releaseTouches()
                }
                onTouch(event)
                return true
            }
        }
    }

    private fun releaseTouches() {
        val original = windowCallback ?: return
        windowCallback = null
        host.window?.window?.callback = original
    }

    private fun liftToolbarItem(window: WWindow, session: Session): Boolean {
        val frame = session.frame ?: return false
        val overlay = createOverlay(window) ?: return false
        Haptics.play(overlay, HapticType.DRAG)
        overlay.setupGhost(session.item, sheet = null, frame)
        host.beginToolbarEdit(session.item)
        overlay.showDim(host.getToolbarFrame())
        if (session.isProfile && showTopTargets(overlay, session)) return true
        if (session.item.isHideable) overlay.showTrash()
        return true
    }

    private fun showTopTargets(overlay: Overlay, session: Session): Boolean {
        val start = host.getTopAvatarFrame(isAtStart = true) ?: return false
        val end = host.getTopAvatarFrame(isAtStart = false) ?: return false
        host.setTopAvatarHeld(true)
        overlay.showTopTargets(start, end)
        overlay.highlightTopTarget(if (session.isInside) null else session.isTopAtStart)
        return true
    }

    fun cancel() {
        val session = session
        this.session = null
        if (session != null) {
            releaseTouches()
            if (!session.isPending) {
                session.sheet?.setDraggedAction(null)
                if (session.isOnToolbar) host.endToolbarEdit(Result.CANCEL)
            }
        }
        host.setTopAvatarHeld(false)
        overlay?.let { removeOverlay(it) }
    }

    private fun createOverlay(window: WWindow): Overlay? {
        val root = window.windowView
        if (!root.isAttachedToWindow) return null
        return Overlay(context).also {
            overlay = it
            root.addView(it, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    private fun removeOverlay(overlay: Overlay) {
        (overlay.parent as? ViewGroup)?.removeView(overlay)
        if (this.overlay === overlay) this.overlay = null
    }

    private fun onTouch(event: MotionEvent) {
        val session = session ?: return
        if (session.isPending && event.actionMasked == MotionEvent.ACTION_MOVE &&
            PopupHelpers.isDragSelecting && isVerticalMove(session, event.rawX, event.rawY)
        ) {
            handOffToMenu(event)
            return
        }
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> move(
                session,
                event.rawX,
                event.rawY
            )

            MotionEvent.ACTION_UP -> drop(session)

            MotionEvent.ACTION_CANCEL -> cancel()
        }
    }

    private fun isVerticalMove(session: Session, x: Float, y: Float): Boolean {
        val dx = x - session.startX
        val dy = y - session.startY
        return hypot(dx, dy) >= touchSlop && abs(dy) > abs(dx)
    }

    private fun handOffToMenu(event: MotionEvent) {
        val original = windowCallback
        session = null
        releaseTouches()
        original?.dispatchTouchEvent(event)
    }

    private fun move(session: Session, x: Float, y: Float) {
        if (session.isPending) {
            if (hypot(x - session.startX, y - session.startY) < touchSlop) return
            session.isPending = false
            session.onLift?.invoke()
            val window = host.window
            if (window == null || !liftToolbarItem(window, session)) {
                this.session = null
                return
            }
        }
        val overlay = overlay ?: return
        if (!session.hasOffset) {
            session.hasOffset = true
            session.offsetX = session.x - x
            session.offsetY = session.y - y
        }
        session.x = x + session.offsetX
        session.y = y + session.offsetY
        overlay.moveGhost(session.x, session.y)
        val sheet = session.sheet
        if (!session.isOnToolbar && sheet != null) {
            if (session.y < sheet.screenTop) {
                moveToToolbar(session, sheet)
            } else if (sheet.moveDraggedAction(session.x, session.y)) {
                Haptics.play(overlay, HapticType.SELECTION)
            }
            return
        }
        val isInside = isInsideToolbar(session.x, session.y)
        val canHold = session.isFromToolbar || host.canToolbarHold(session.item)
        if (host.moveToolbarEdit(if (isInside && canHold) session.x else null)) {
            Haptics.play(overlay, HapticType.SELECTION)
        }
        if (overlay.hasTopTargets) {
            val isAtStart = (session.x < overlay.width / 2f) != LocaleController.isRTL
            if (isInside != session.isInside || isAtStart != session.isTopAtStart) {
                session.isInside = isInside
                session.isTopAtStart = isAtStart
                overlay.highlightTopTarget(if (isInside) null else isAtStart)
                Haptics.play(overlay, HapticType.SELECTION)
            }
            return
        }
        if (isInside != session.isInside) {
            session.isInside = isInside
            if (session.isFromToolbar && session.item.isHideable) {
                overlay.highlightTrash(!isInside)
                Haptics.play(overlay, HapticType.SELECTION)
            }
        }
    }

    private fun moveToToolbar(session: Session, sheet: HomeActionsSheetVC) {
        val overlay = overlay ?: return
        val frame = host.getToolbarFrame()
        sheet.dismissForDrag()
        session.sheet = null
        if (frame == null) {
            cancel()
            return
        }
        session.isOnToolbar = true
        session.isInside = false
        animateOffset(session)
        host.beginToolbarEdit(session.item)
        overlay.hideHint()
        overlay.showDim(frame)
        overlay.morphGhostToToolbar()
    }

    private fun animateOffset(session: Session) {
        val fromX = session.offsetX
        val fromY = session.offsetY
        ValueAnimator.ofFloat(1f, 0f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            addUpdateListener {
                val fraction = it.animatedValue as Float
                val x = session.x - session.offsetX
                val y = session.y - session.offsetY
                session.offsetX = fromX * fraction
                session.offsetY = fromY * fraction
                session.x = x + session.offsetX
                session.y = y + session.offsetY
                if (this@HomeToolbarEditor.session ===
                    session
                ) {
                    overlay?.moveGhost(session.x, session.y)
                }
            }
            start()
        }
    }

    private fun isInsideToolbar(x: Float, y: Float): Boolean {
        val frame = host.getToolbarFrame() ?: return false
        val margin = TOOLBAR_ZONE_MARGIN.dp
        return y >= frame.top - margin && y <= frame.bottom + margin
    }

    private fun drop(session: Session) {
        this.session = null
        if (session.isPending) return
        val overlay = overlay ?: return
        val sheet = session.sheet
        if (!session.isOnToolbar) {
            val frame = sheet?.getActionCircleFrame(session.item)
            sheet?.saveOrder()
            overlay.hideHint()
            overlay.flyGhost(frame, isRemoved = false) {
                sheet?.setDraggedAction(null)
                removeOverlay(overlay)
            }
            return
        }
        val isInside = isInsideToolbar(session.x, session.y)
        val canHold = session.isFromToolbar || host.canToolbarHold(session.item)
        val topFrame = host.getTopAvatarFrame(session.isTopAtStart)
            ?.takeIf { overlay.hasTopTargets && !(isInside && canHold) }
        when {
            topFrame != null -> {
                if (isInside) Haptics.play(overlay, HapticType.ERROR)
                host.endToolbarEdit(Result.TOP, isAtStart = session.isTopAtStart)
                overlay.finish(topFrame, isRemoved = false) {
                    host.setTopAvatarHeld(false)
                    removeOverlay(overlay)
                }
            }

            isInside && canHold -> {
                host.setTopAvatarHeld(false)
                host.endToolbarEdit(
                    Result.ADD,
                    Drop(session.x, session.y, overlay.toolbarScale)
                )
                overlay.settleGhost(host.getToolbarButton(session.item))
                overlay.finish(null, isRemoved = false) { removeOverlay(overlay) }
                Haptics.play(overlay, HapticType.LIGHT_TAP)
            }

            isInside -> {
                host.endToolbarEdit(Result.CANCEL)
                Haptics.play(overlay, HapticType.ERROR)
                overlay.finish(null, isRemoved = true) { removeOverlay(overlay) }
            }

            session.isFromToolbar && session.item.isHideable -> {
                host.endToolbarEdit(Result.REMOVE)
                Haptics.play(overlay, HapticType.LIGHT_TAP)
                overlay.finish(overlay.trashFrame, isRemoved = true) { removeOverlay(overlay) }
            }

            session.isFromToolbar -> {
                host.endToolbarEdit(
                    Result.CANCEL,
                    Drop(session.x, session.y, overlay.toolbarScale)
                )
                overlay.settleGhost(host.getToolbarButton(session.item))
                overlay.finish(null, isRemoved = false) { removeOverlay(overlay) }
            }

            else -> {
                host.endToolbarEdit(Result.CANCEL)
                overlay.finish(null, isRemoved = true) { removeOverlay(overlay) }
            }
        }
    }

    @SuppressLint("ViewConstructor")
    private inner class Overlay(context: Context) : FrameLayout(context) {
        private val dimPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val dimPath = Path()
        private val holePath = Path()
        private val landingPath = Path()
        private val buttonLocation = IntArray(2)
        var landingButton: View? = null
        private var dimAlpha = 0f
        private var hole: RectF? = null
        private var dimAnimator: ValueAnimator? = null
        private val origin = IntArray(2)

        private val ghostSize = SHEET_ICON_SIZE.dp
        private val ghost = FrameLayout(context)
        private val colorLayer = FrameLayout(context)
        private val plainLayer = FrameLayout(context)
        private var ghostScale = 1f

        private val hintLabel = WLabel(context).apply {
            setStyle(14f, WFont.Medium)
            gravity = Gravity.CENTER
            text = LocaleController.getString("Drag here to add to the toolbar")
            setTextColor(WColor.PrimaryText.color)
            setPadding(14.dp, 8.dp, 14.dp, 8.dp)
            setBackgroundColor(WColor.Background.color, 18f.dp)
            elevation = 4f.dp
            alpha = 0f
        }

        private val trashIcon = AppCompatImageView(context).apply {
            setImageDrawable(
                context.requireDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_trash_24)
            )
        }
        private val trashView = FrameLayout(context).apply {
            addView(trashIcon, LayoutParams(24.dp, 24.dp, Gravity.CENTER))
            elevation = 4f.dp
            alpha = 0f
        }

        private val topTargets = List(2) {
            View(context).apply {
                alpha = 0f
                elevation = 4f.dp
            }
        }

        val hasTopTargets: Boolean
            get() = topTargets[0].alpha > 0f

        fun showTopTargets(start: RectF, end: RectF) {
            getLocationOnScreen(origin)
            listOf(start, end).forEachIndexed { index, frame ->
                topTargets[index].apply {
                    translationX = frame.left - origin[0]
                    translationY = frame.top - origin[1]
                    layoutParams = LayoutParams(
                        frame.width().roundToInt(),
                        frame.height().roundToInt(),
                        Gravity.TOP or Gravity.LEFT
                    )
                    alpha = 1f
                }
            }
        }

        /** Null highlights neither */
        fun highlightTopTarget(isAtStart: Boolean?) {
            topTargets.forEachIndexed { index, target ->
                val isHighlighted = isAtStart != null && (index == 0) == isAtStart
                target.background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(WColor.Background.color)
                    setStroke(
                        (if (isHighlighted) 2f.dp else 1f.dp).roundToInt(),
                        if (isHighlighted) WColor.Tint.color else WColor.Separator.color
                    )
                }
                val scale = if (isHighlighted) TRASH_HIGHLIGHT_SCALE else 1f
                target.animate().scaleX(scale).scaleY(scale)
                    .setDuration(AnimationConstants.VERY_VERY_QUICK_ANIMATION).start()
            }
        }

        val trashFrame: RectF
            get() {
                getLocationOnScreen(origin)
                val left = origin[0] + trashView.x
                val top = origin[1] + trashView.y
                return RectF(left, top, left + trashView.width, top + trashView.height)
            }

        init {
            id = generateViewId()
            setWillNotDraw(false)
            clipChildren = false
            addView(
                hintLabel,
                LayoutParams(
                    WRAP_CONTENT,
                    WRAP_CONTENT,
                    Gravity.TOP or Gravity.CENTER_HORIZONTAL
                )
            )
            addView(
                trashView,
                LayoutParams(TRASH_SIZE.dp, TRASH_SIZE.dp, Gravity.TOP or Gravity.CENTER_HORIZONTAL)
            )
            topTargets.forEach {
                addView(
                    it,
                    LayoutParams(
                        TOP_TARGET_SIZE.dp,
                        TOP_TARGET_SIZE.dp,
                        Gravity.TOP or Gravity.LEFT
                    )
                )
            }
            addView(ghost, LayoutParams(ghostSize, ghostSize, Gravity.TOP or Gravity.LEFT))
            ghost.addView(plainLayer, LayoutParams(MATCH_PARENT, MATCH_PARENT))
            ghost.addView(colorLayer, LayoutParams(MATCH_PARENT, MATCH_PARENT))
            ghost.elevation = 6f.dp
            ghost.outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setOval(0, 0, view.width, view.height)
                }
            }
            highlightTrash(false)
        }

        override fun onDraw(canvas: Canvas) {
            if (dimAlpha <= 0f) return
            getLocationOnScreen(origin)
            dimPaint.color = WColor.Background.color.colorWithAlpha((DIM_ALPHA * dimAlpha).toInt())
            dimPath.rewind()
            dimPath.addRect(0f, 0f, width.toFloat(), height.toFloat(), Path.Direction.CW)
            holePath.rewind()
            hole?.let {
                val radius = HomeToolbarLayout.HEIGHT.dp / 2f
                holePath.addRoundRect(
                    it.left - origin[0],
                    it.top - origin[1],
                    it.right - origin[0],
                    it.bottom - origin[1],
                    radius,
                    radius,
                    Path.Direction.CW
                )
            }
            landingButton?.let { button ->
                button.getLocationOnScreen(buttonLocation)
                val radius = button.height * button.scaleY / 2
                landingPath.rewind()
                landingPath.addCircle(
                    buttonLocation[0] + button.width * button.scaleX / 2 - origin[0],
                    buttonLocation[1] + radius - origin[1],
                    radius + HOLE_PADDING.dp,
                    Path.Direction.CW
                )
                holePath.op(landingPath, Path.Op.UNION)
            }
            dimPath.op(holePath, Path.Op.DIFFERENCE)
            canvas.drawPath(dimPath, dimPaint)
        }

        fun setupGhost(item: MToolbarItem, sheet: HomeActionsSheetVC?, frame: RectF) {
            if (sheet != null) {
                colorLayer.background = sheet.createActionDrawable(item)
                colorLayer.addView(
                    AppCompatImageView(context).apply {
                        setImageResource(HomeToolbarActions.getIconRes(item))
                        setColorFilter(Color.WHITE)
                    },
                    LayoutParams(SHEET_INNER_ICON_SIZE.dp, SHEET_INNER_ICON_SIZE.dp, Gravity.CENTER)
                )
            } else {
                colorLayer.alpha = 0f
            }
            plainLayer.setBackgroundColor(WColor.SearchFieldBackground.color, ghostSize / 2f)
            val iconScale = ghostSize.toFloat() / HomeToolbarLayout.HEIGHT.dp
            val iconSize = (host.getToolbarIconSize(item) * iconScale).dp
            plainLayer.addView(
                host.createToolbarIcon(item, iconScale),
                LayoutParams(iconSize.roundToInt(), iconSize.roundToInt(), Gravity.CENTER)
            )
            val baseScale = if (sheet != null) 1f else TOOLBAR_SCALE
            ghostScale = baseScale
            applyGhostScale()
            moveGhost(frame.centerX(), frame.centerY())
            animateGhostScale(baseScale * LIFT_SCALE)
        }

        fun moveGhost(x: Float, y: Float) {
            getLocationOnScreen(origin)
            ghost.translationX = x - origin[0] - ghostSize / 2f
            ghost.translationY = y - origin[1] - ghostSize / 2f
        }

        val toolbarScale: Float
            get() = ghostScale * ghostSize / HomeToolbarLayout.HEIGHT.dp

        // Covers the frames before the landing button's glass draws
        fun settleGhost(button: View) {
            landingButton = button
            ghost.animate().cancel()
            val location = IntArray(2)
            ValueAnimator.ofFloat(1f, 0f).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION
                interpolator = CubicBezierInterpolator.EASE_BOTH
                addUpdateListener {
                    button.getLocationOnScreen(location)
                    val width = button.width * button.scaleX
                    val height = button.height * button.scaleY
                    ghostScale = width / ghostSize
                    applyGhostScale()
                    moveGhost(location[0] + width / 2, location[1] + height / 2)
                    ghost.alpha = it.animatedValue as Float
                }
                start()
            }
        }

        fun morphGhostToToolbar() {
            animateGhostScale(TOOLBAR_SCALE * LIFT_SCALE)
            colorLayer.animate().alpha(
                0f
            ).setDuration(AnimationConstants.VERY_QUICK_ANIMATION).start()
        }

        private fun applyGhostScale() {
            ghost.scaleX = ghostScale
            ghost.scaleY = ghostScale
        }

        private fun animateGhostScale(target: Float, onEnd: (() -> Unit)? = null) {
            val from = ghostScale
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION
                interpolator = CubicBezierInterpolator.EASE_BOTH
                addUpdateListener {
                    ghostScale = from + (target - from) * (it.animatedValue as Float)
                    applyGhostScale()
                }
                onEnd?.let { doOnEnd { _ -> it() } }
                start()
            }
        }

        fun showHint(sheetTop: Float) {
            hintLabel.doOnLayout {
                getLocationOnScreen(origin)
                hintLabel.translationY = sheetTop - origin[1] - hintLabel.height - HINT_GAP.dp
                hintLabel.animate().alpha(1f)
                    .setDuration(AnimationConstants.VERY_QUICK_ANIMATION).start()
            }
        }

        fun hideHint() {
            hintLabel.animate().alpha(
                0f
            ).setDuration(AnimationConstants.VERY_VERY_QUICK_ANIMATION).start()
        }

        fun showDim(hole: RectF?) {
            this.hole = hole?.let {
                val inset = HOLE_PADDING.dp
                RectF(it.left - inset, it.top - inset, it.right + inset, it.bottom + inset)
            }
            if (hole != null) {
                getLocationOnScreen(origin)
                trashView.translationY = hole.top - origin[1] - TRASH_GAP.dp - TRASH_SIZE.dp
            }
            animateDim(1f)
        }

        private fun animateDim(target: Float) {
            dimAnimator?.cancel()
            val from = dimAlpha
            dimAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION
                addUpdateListener {
                    dimAlpha = from + (target - from) * (it.animatedValue as Float)
                    invalidate()
                }
                start()
            }
        }

        fun showTrash() {
            trashView.scaleX = 0.6f
            trashView.scaleY = 0.6f
            trashView.animate().alpha(1f).scaleX(1f).scaleY(1f)
                .setDuration(AnimationConstants.VERY_QUICK_ANIMATION).start()
        }

        fun highlightTrash(isHighlighted: Boolean) {
            trashView.setBackgroundColor(
                if (isHighlighted) WColor.Red.color else WColor.Background.color,
                TRASH_SIZE.dp / 2f
            )
            trashIcon.setColorFilter(if (isHighlighted) Color.WHITE else WColor.Red.color)
            val scale = if (isHighlighted) TRASH_HIGHLIGHT_SCALE else 1f
            if (trashView.alpha > 0f) {
                trashView.animate().scaleX(scale).scaleY(scale)
                    .setDuration(AnimationConstants.VERY_VERY_QUICK_ANIMATION).start()
            }
        }

        fun finish(frame: RectF?, isRemoved: Boolean, onEnd: () -> Unit) {
            trashView.animate().alpha(
                0f
            ).setDuration(AnimationConstants.VERY_QUICK_ANIMATION).start()
            topTargets.forEach {
                it.animate().alpha(0f).setDuration(AnimationConstants.VERY_QUICK_ANIMATION).start()
            }
            animateDim(0f)
            flyGhost(frame, isRemoved, onEnd)
        }

        fun flyGhost(frame: RectF?, isRemoved: Boolean, onEnd: () -> Unit) {
            if (!WGlobalStorage.getAreAnimationsActive()) {
                onEnd()
                return
            }
            if (frame == null && !isRemoved) {
                postDelayed(onEnd, AnimationConstants.VERY_QUICK_ANIMATION)
                return
            }
            if (frame != null) {
                getLocationOnScreen(origin)
                ghost.animate()
                    .translationX(frame.centerX() - origin[0] - ghostSize / 2f)
                    .translationY(frame.centerY() - origin[1] - ghostSize / 2f)
                    .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                    .setInterpolator(CubicBezierInterpolator.EASE_BOTH)
                    .start()
            }
            if (isRemoved) {
                ghost.animate().alpha(
                    0f
                ).setDuration(AnimationConstants.VERY_QUICK_ANIMATION).start()
            }
            val target = when {
                isRemoved -> ghostScale * REMOVED_SCALE
                frame != null -> max(frame.width(), 1f) / ghostSize
                else -> ghostScale
            }
            animateGhostScale(target, onEnd)
        }
    }

    private companion object {
        const val SHEET_ICON_SIZE = 68
        const val SHEET_INNER_ICON_SIZE = 40
        val TOOLBAR_SCALE = HomeToolbarLayout.HEIGHT.toFloat() / SHEET_ICON_SIZE
        const val LIFT_SCALE = 1.12f
        const val REMOVED_SCALE = 0.4f
        const val TOOLBAR_ZONE_MARGIN = 40
        const val HOLE_PADDING = 6
        const val HINT_GAP = 16
        const val TRASH_SIZE = 56
        const val TOP_TARGET_SIZE = 44
        const val TRASH_GAP = 72
        const val TRASH_HIGHLIGHT_SCALE = 1.2f
        const val DIM_ALPHA = 170
    }
}
