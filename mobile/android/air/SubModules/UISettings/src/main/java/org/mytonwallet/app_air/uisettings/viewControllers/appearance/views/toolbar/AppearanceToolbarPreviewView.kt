package org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.toolbar

import android.animation.ObjectAnimator
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewTreeObserver
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.isInvisible
import androidx.core.view.updateLayoutParams
import kotlin.math.abs
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.HomeToolbarActions
import org.mytonwallet.app_air.uicomponents.helpers.HomeToolbarBackgrounds
import org.mytonwallet.app_air.uicomponents.helpers.HomeToolbarLayout
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MToolbarItem
import org.mytonwallet.app_air.walletcore.models.MAccount

class AppearanceToolbarPreviewView(context: Context) :
    WView(context),
    WThemedView {

    private companion object {
        const val AVATAR_ICON_SIZE = 40
        const val ICON_SIZE = 24
        const val PLUS_ICON_SIZE = 18
        const val SEARCH_ICON_SIZE = 22
        const val SEARCH_PADDING = 14
        const val SEARCH_HINT_MARGIN = 6
        const val HIDDEN_SCALE = 0.6f
        const val LIFT_SCALE = 0.08f
        const val SHAKE_ANGLE = 2f
    }

    var onOrderChanged: (() -> Unit)? = null

    private val titleLabel = HeaderCell(context).apply {
        configure(
            LocaleController.getString("Toolbar"),
            titleColor = WColor.Tint,
            HeaderCell.TopRounding.NORMAL
        )
    }

    private val searchIcon = AppCompatImageView(context).apply {
        setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_search_22)
    }

    private val searchHintLabel = WLabel(context).apply {
        setStyle(16f)
        isSingleLine = true
        text = LocaleController.getString("Search or Ask")
        setTextColor(WColor.SecondaryText)
    }

    private val searchPill = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPaddingRelative(SEARCH_PADDING.dp, 0, SEARCH_PADDING.dp, 0)
        addView(searchIcon, LinearLayout.LayoutParams(SEARCH_ICON_SIZE.dp, SEARCH_ICON_SIZE.dp))
        addView(
            searchHintLabel,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = SEARCH_HINT_MARGIN.dp
            }
        )
    }

    private val accountIconView = AccountIconView(context, AccountIconView.Usage.ViewItem(14f.dp))
    private val accountsCircle = WFrameLayout(context).apply {
        addView(
            accountIconView,
            FrameLayout.LayoutParams(AVATAR_ICON_SIZE.dp, AVATAR_ICON_SIZE.dp, Gravity.CENTER)
        )
    }

    private val scanIcon = AppCompatImageView(context).apply {
        setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_qr_code_scan_18_24)
    }
    private val scanCircle = WFrameLayout(context).apply {
        addView(scanIcon, FrameLayout.LayoutParams(ICON_SIZE.dp, ICON_SIZE.dp, Gravity.CENTER))
    }

    private val plusIcon = AppCompatImageView(context).apply {
        setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_plus_thick)
    }
    private val plusCircle = WFrameLayout(context).apply {
        addView(
            plusIcon,
            FrameLayout.LayoutParams(PLUS_ICON_SIZE.dp, PLUS_ICON_SIZE.dp, Gravity.CENTER)
        )
    }

    private val actionIcons = mutableListOf<AppCompatImageView>()
    private val actionCircles = MToolbarItem.ACTION_ITEMS.filter { it != MToolbarItem.SCAN }
        .associateWith { item ->
            val icon = AppCompatImageView(context).apply {
                setImageResource(HomeToolbarActions.getToolbarIconRes(item))
            }
            actionIcons += icon
            WFrameLayout(context).apply {
                addView(icon, FrameLayout.LayoutParams(ICON_SIZE.dp, ICON_SIZE.dp, Gravity.CENTER))
            }
        }

    private val backgroundsSync = HomeToolbarBackgrounds(context, ::getItemView)
    private val backgroundsListener = ViewTreeObserver.OnPreDrawListener {
        backgroundsSync.sync(order, isSharedBackground, liftedItem, liftProgress)
        true
    }

    private val toolbarRow = object : WFrameLayout(context) {
        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            post { applyLayout() }
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean = handleTouch(event)
    }.apply {
        id = generateViewId()
        clipChildren = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        // Anchored left; RTL mirrors the offsets
        val gravity = Gravity.TOP or Gravity.LEFT
        val height = HomeToolbarLayout.HEIGHT.dp
        for (background in backgroundsSync.views) {
            background.visibility = GONE
            addView(background, FrameLayout.LayoutParams(height, height, gravity))
        }
        for (item in MToolbarItem.entries) {
            val width = if (item == MToolbarItem.SEARCH) 0 else height
            addView(getItemView(item), FrameLayout.LayoutParams(width, height, gravity))
        }
    }

    private val glassViews = (listOf<View>(searchPill) + backgroundsSync.views).associateWith {
        WGlassView.attachTo(
            it,
            HomeToolbarLayout.HEIGHT.dp / 2f,
            GlassProviders.pill(WColor.SearchFieldBackground),
            root = null
        )
    }

    private var order = WGlobalStorage.getToolbarConfiguration().order
    private var isSharedBackground = WGlobalStorage.getToolbarConfiguration().isSharedBackground

    private val shownProgress = FloatArray(MToolbarItem.entries.size) {
        getShownProgress(MToolbarItem.entries[it])
    }
    private var visibilityAnimator: ValueAnimator? = null
    private val visibility: (MToolbarItem) -> Float = { item ->
        if (item.isHideable) shownProgress[item.ordinal] else 1f
    }

    private val shownStarts = FloatArray(MToolbarItem.entries.size)
    private var shownFieldWidth = 0f
    private val targetStarts = FloatArray(MToolbarItem.entries.size)
    private val candidateStarts = FloatArray(MToolbarItem.entries.size)

    private val reflowFromStarts = FloatArray(MToolbarItem.entries.size)
    private var reflowFromFieldWidth = 0f
    private var reflowProgress = 1f
    private var reflowAnimator: ValueAnimator? = null

    private var draggedItem: MToolbarItem? = null
    private var dragStart = 0f
    private var liftedItem: MToolbarItem? = null
    private var liftProgress = 0f
    private var liftAnimator: ValueAnimator? = null

    private val shakeAnimators = mutableListOf<ObjectAnimator>()

    private var pressedItem: MToolbarItem? = null
    private var downX = 0f
    private var downY = 0f
    private var pressStart = 0f
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private val startDrag = Runnable { beginDrag() }

    override fun setupViews() {
        super.setupViews()

        clipChildren = false
        addView(titleLabel)
        addView(toolbarRow, LayoutParams(0, HomeToolbarLayout.HEIGHT.dp))

        setConstraints {
            toTop(titleLabel)
            toStart(titleLabel)
            topToBottom(toolbarRow, titleLabel, 12f)
            toCenterX(toolbarRow, 12f)
            toBottom(toolbarRow, 20f)
        }

        updateTheme()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        toolbarRow.viewTreeObserver.addOnPreDrawListener(backgroundsListener)
    }

    override fun onDetachedFromWindow() {
        toolbarRow.viewTreeObserver.removeOnPreDrawListener(backgroundsListener)
        stopShake()
        super.onDetachedFromWindow()
    }

    fun configure(account: MAccount?) {
        account?.let { accountIconView.config(it) }
    }

    fun update(animated: Boolean) {
        val isShared = WGlobalStorage.getToolbarConfiguration().isSharedBackground
        if (isShared != isSharedBackground) {
            snapshotReflow()
            isSharedBackground = isShared
            if (animated && isAttachedToWindow) startReflow() else reflowProgress = 1f
        }
        val configuration = WGlobalStorage.getToolbarConfiguration()
        if (configuration.order != order && draggedItem == null) {
            snapshotReflow()
            order = configuration.order
            if (animated && isAttachedToWindow) startReflow() else reflowProgress = 1f
        }
        val targets = FloatArray(shownProgress.size) { getShownProgress(MToolbarItem.entries[it]) }
        visibilityAnimator?.cancel()
        visibilityAnimator = null
        if (!animated || !WGlobalStorage.getAreAnimationsActive() || !isAttachedToWindow) {
            targets.copyInto(shownProgress)
            applyLayout()
            return
        }
        val from = shownProgress.copyOf()
        visibilityAnimator = createAnimator { fraction ->
            for (index in shownProgress.indices) {
                shownProgress[index] = from[index] + (targets[index] - from[index]) * fraction
            }
        }
    }

    private fun getShownProgress(item: MToolbarItem): Float =
        if (WGlobalStorage.getToolbarConfiguration().isShown(item)) 1f else 0f

    private fun getItemView(item: MToolbarItem): View = when (item) {
        MToolbarItem.SEARCH -> searchPill
        MToolbarItem.ACCOUNTS -> accountsCircle
        MToolbarItem.SCAN -> scanCircle
        MToolbarItem.ACTIONS -> plusCircle
        else -> actionCircles.getValue(item)
    }

    private fun getItemWidth(item: MToolbarItem, fieldWidth: Float): Float =
        if (item == MToolbarItem.SEARCH) fieldWidth else HomeToolbarLayout.HEIGHT.dp.toFloat()

    private fun createAnimator(onFraction: (Float) -> Unit): ValueAnimator =
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener {
                onFraction(it.animatedValue as Float)
                applyLayout()
            }
            start()
        }

    private fun applyLayout() {
        val width = toolbarRow.width
        if (width == 0) return
        val targetFieldWidth = HomeToolbarLayout.layout(
            order,
            width,
            isSharedBackground,
            visibility,
            targetStarts
        )
        shownFieldWidth =
            reflowFromFieldWidth + (targetFieldWidth - reflowFromFieldWidth) * reflowProgress
        for (item in MToolbarItem.entries) {
            val index = item.ordinal
            shownStarts[index] = if (item == draggedItem) {
                dragStart
            } else {
                reflowFromStarts[index] +
                    (targetStarts[index] - reflowFromStarts[index]) * reflowProgress
            }
        }
        val fieldWidth = shownFieldWidth.roundToInt()
        if (searchPill.layoutParams.width != fieldWidth) {
            searchPill.updateLayoutParams { this.width = fieldWidth }
        }
        updateSearchHint(fieldWidth)
        for (item in MToolbarItem.entries) {
            placeItem(item, width)
        }
    }

    private fun updateSearchHint(fieldWidth: Int) {
        val fullHint = LocaleController.getString("Search or Ask")
        val labelWidth =
            fieldWidth - (2 * SEARCH_PADDING + SEARCH_ICON_SIZE + SEARCH_HINT_MARGIN).dp
        val hint = if (searchHintLabel.paint.measureText(fullHint) <= labelWidth) {
            fullHint
        } else {
            LocaleController.getString("Search")
        }
        if (searchHintLabel.text != hint) searchHintLabel.text = hint
    }

    private fun placeItem(item: MToolbarItem, rowWidth: Int) {
        val view = getItemView(item)
        val start = shownStarts[item.ordinal]
        view.translationX = if (LocaleController.isRTL) {
            rowWidth - start - getItemWidth(item, shownFieldWidth)
        } else {
            start
        }
        val progress = visibility(item)
        val lift = if (item == liftedItem) 1 + LIFT_SCALE * liftProgress else 1f
        val scale = (HIDDEN_SCALE + (1 - HIDDEN_SCALE) * progress) * lift
        view.scaleX = scale
        view.scaleY = scale
        view.alpha = progress
        view.isInvisible = progress == 0f
    }

    private fun handleTouch(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val item = findItem(event.x) ?: return false
                pressedItem = item
                downX = event.x
                downY = event.y
                pressStart = shownStarts[item.ordinal]
                toolbarRow.postDelayed(startDrag, ViewConfiguration.getLongPressTimeout().toLong())
                return true
            }

            MotionEvent.ACTION_MOVE -> {
                if (draggedItem == null) {
                    if (abs(event.x - downX) > touchSlop || abs(event.y - downY) > touchSlop) {
                        cancelPress()
                        return false
                    }
                    return true
                }
                drag(event.x)
                return true
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                cancelPress()
                endDrag()
                return true
            }
        }
        return true
    }

    private fun findItem(x: Float): MToolbarItem? = MToolbarItem.entries.firstOrNull { item ->
        val view = getItemView(item)
        visibility(item) > 0.5f && x >= view.x && x <= view.x + view.width
    }

    private fun cancelPress() {
        toolbarRow.removeCallbacks(startDrag)
        pressedItem = null
    }

    private fun beginDrag() {
        val item = pressedItem ?: return
        pressedItem = null
        toolbarRow.parent?.requestDisallowInterceptTouchEvent(true)
        Haptics.play(toolbarRow, HapticType.DRAG)
        snapshotReflow()
        draggedItem = item
        dragStart = pressStart
        val background = if (item == MToolbarItem.SEARCH) {
            searchPill
        } else {
            backgroundsSync.getOwnBackground(item)
        }
        glassViews[background]?.bringToFront()
        background.bringToFront()
        getItemView(item).bringToFront()
        animateLift(item, lifted = true)
        startShake(item)
    }

    private fun drag(x: Float) {
        val item = draggedItem ?: return
        val width = toolbarRow.width
        val delta = if (LocaleController.isRTL) downX - x else x - downX
        val maxStart = width - getItemWidth(item, shownFieldWidth)
        dragStart = (pressStart + delta).coerceIn(0f, maxStart)
        val newOrder = findOrder(item, width)
        if (newOrder != order) {
            snapshotReflow()
            order = newOrder
            Haptics.play(toolbarRow, HapticType.SELECTION)
            startReflow()
        } else {
            applyLayout()
        }
    }

    /** The order placing [item]'s center closest to where it is held */
    private fun findOrder(item: MToolbarItem, width: Int): List<MToolbarItem> {
        val others = order - item
        val center = dragStart + getItemWidth(item, shownFieldWidth) / 2
        // A tie keeps the current order, so a hidden item does not move unseen
        var bestOrder = order
        var bestDistance = getDistance(order, item, width, center)
        for (index in 0..others.size) {
            val candidate = others.toMutableList().apply { add(index, item) }
            val distance = getDistance(candidate, item, width, center)
            if (distance < bestDistance) {
                bestDistance = distance
                bestOrder = candidate
            }
        }
        return bestOrder
    }

    private fun getDistance(
        candidate: List<MToolbarItem>,
        item: MToolbarItem,
        width: Int,
        center: Float
    ): Float {
        val fieldWidth = HomeToolbarLayout.layout(
            candidate,
            width,
            isSharedBackground,
            visibility,
            candidateStarts
        )
        return abs(candidateStarts[item.ordinal] + getItemWidth(item, fieldWidth) / 2 - center)
    }

    private fun endDrag() {
        val item = draggedItem ?: return
        snapshotReflow()
        draggedItem = null
        stopShake()
        startReflow()
        animateLift(item, lifted = false)
        val configuration = WGlobalStorage.getToolbarConfiguration()
        if (order != configuration.order) {
            WGlobalStorage.setToolbarConfiguration(configuration.copy(order = order))
            onOrderChanged?.invoke()
        }
    }

    private fun startShake(draggedItem: MToolbarItem) {
        stopShake()
        if (!WGlobalStorage.getAreAnimationsActive()) return
        for (item in MToolbarItem.entries) {
            if (item == draggedItem || visibility(item) == 0f) continue
            val view = getItemView(item)
            // Smaller angle for the wide field
            val angle = SHAKE_ANGLE * HomeToolbarLayout.HEIGHT.dp / view.width.coerceAtLeast(1)
            val rotation = PropertyValuesHolder.ofFloat(
                View.ROTATION,
                0f,
                -angle / 2,
                angle,
                -angle / 2,
                angle,
                0f
            )
            shakeAnimators += ObjectAnimator.ofPropertyValuesHolder(view, rotation).apply {
                duration = AnimationConstants.SLOW_ANIMATION
                repeatCount = ObjectAnimator.INFINITE
                interpolator = LinearInterpolator()
                start()
                currentPlayTime = duration * item.ordinal / MToolbarItem.entries.size
            }
        }
    }

    private fun stopShake() {
        shakeAnimators.forEach { it.cancel() }
        shakeAnimators.clear()
        for (item in MToolbarItem.entries) getItemView(item).rotation = 0f
    }

    private fun snapshotReflow() {
        shownStarts.copyInto(reflowFromStarts)
        reflowFromFieldWidth = shownFieldWidth
        reflowAnimator?.cancel()
        reflowAnimator = null
        reflowProgress = 0f
    }

    private fun startReflow() {
        if (!WGlobalStorage.getAreAnimationsActive()) {
            reflowProgress = 1f
            applyLayout()
            return
        }
        reflowAnimator = createAnimator { reflowProgress = it }
    }

    private fun animateLift(item: MToolbarItem, lifted: Boolean) {
        liftAnimator?.cancel()
        liftedItem = item
        val from = liftProgress
        val target = if (lifted) 1f else 0f
        if (!WGlobalStorage.getAreAnimationsActive()) {
            liftProgress = target
            applyLayout()
            return
        }
        liftAnimator = createAnimator { liftProgress = from + (target - from) * it }
    }

    override val isTinted = true
    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp, 0f)
        for (item in MToolbarItem.entries) {
            getItemView(item).setBackgroundColor(
                Color.TRANSPARENT,
                HomeToolbarLayout.HEIGHT.dp / 2f,
                clipToBounds = true
            )
        }
        glassViews.values.forEach { it.updateTheme() }
        val iconColor = WColor.SecondaryText.color
        searchIcon.setColorFilter(iconColor)
        scanIcon.setColorFilter(iconColor)
        plusIcon.setColorFilter(iconColor)
        actionIcons.forEach { it.setColorFilter(iconColor) }
        accountIconView.updateTheme()
    }
}
