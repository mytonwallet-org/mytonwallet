package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.style.ReplacementSpan
import android.view.Choreographer
import android.view.Gravity
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import androidx.core.view.isVisible
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiagent.R as UIAgentR
import org.mytonwallet.app_air.uiagent.agentV2.resolveAgentThreadTitle
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentSupportLabelStyle
import org.mytonwallet.app_air.uiagent.viewControllers.agent.getAgentSupportLabelStyle
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSpinningTopView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentStatusTextView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentUnreadBadgeDrawable
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentUnreadDotView
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem

/** The row layout of the Agent list, shared by chats and the News row */
internal object AgentThreadRowMetrics {
    const val MIN_HEIGHT = 80
    const val VERTICAL_PADDING = 8
    const val HORIZONTAL_PADDING = 12
    const val AVATAR = 44
    const val AVATAR_GAP = 12
    const val TITLE_LINE = 24
    const val PREVIEW_BOX = 40
    const val PIN_WIDTH = 14
    const val PIN_HEIGHT = 20
    const val PIN_GAP = 4
    const val TIME_GAP = 8
    const val UNREAD_DOT = 8
    const val UNREAD_GAP = 8

    const val UNREAD_BADGE_HEIGHT = 22
    const val UNREAD_BADGE_PADDING = 6
    const val UNREAD_BADGE_TEXT_SIZE = 12f

    const val PREVIEW_THUMBNAIL = 18
    const val PREVIEW_THUMBNAIL_RADIUS = 2f
    const val PREVIEW_THUMBNAIL_GAP = 5
    const val PREVIEW_THUMBNAIL_SPACE = PREVIEW_THUMBNAIL + PREVIEW_THUMBNAIL_GAP

    const val ACTIVITY_TOP_BOX_WIDTH = 24
    const val ACTIVITY_TOP = 20
    const val ACTIVITY_TOP_INSET = 3
    const val CARD_RADIUS = 20f

    val contentStart: Int get() = (HORIZONTAL_PADDING + AVATAR + AVATAR_GAP).dp
}

/**
 * A chat's row: avatar, title, time, the preview or what the Agent is doing while it answers, and the unread dot.
 * Under a swipe the row becomes a card and uncovers Rename, Pin and Delete, as Telegram's chat list does.
 */
@SuppressLint("ViewConstructor")
internal class AgentThreadCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {
    private val avatarView = AgentThreadAvatarView(context, AgentThreadRowMetrics.AVATAR.dp)
    val rowView = AgentThreadRowView(context, avatarView)
    private val actionsLayer = SwipeActionsLayer(context)
    private val renameButton =
        SwipeActionButton(context, UIComponentsR.id.agent_thread_swipe_rename)
    private val pinButton = SwipeActionButton(context, UIComponentsR.id.agent_thread_swipe_pin)
    private val deleteButton =
        SwipeActionButton(context, UIComponentsR.id.agent_thread_swipe_delete)

    // The trailing strip a swipe may start in: the rest of the row pages between the tabs
    private val swipeHandle = SwipeHandleView(context)
    private val motion = AgentThreadSwipeMotion()
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var velocityTracker: VelocityTracker? = null
    private var downX = 0f
    private var downY = 0f
    private var isSwipeCandidate = false
    private var isSwiping = false
    private var shouldCloseOnTap = false
    private var isFrameScheduled = false
    private var lastFrameNanos = 0L
    private var threadId: String? = null
    private val actionIds = mutableMapOf<Int, Int>()

    var onTap: (() -> Unit)? = null
    var onLongPress: (() -> Unit)? = null
    var onRename: (() -> Unit)? = null
    var onTogglePin: (() -> Unit)? = null
    var onDelete: (() -> Unit)? = null
    var onSwipeBegan: (() -> Unit)? = null

    var isMenuShown = false

    private val isSwipeOpen: Boolean get() = motion.state != AgentThreadSwipeMotion.State.CLOSED

    private val swipeSign: Float get() = if (LocaleController.isRTL) -1f else 1f

    private val frameCallback = Choreographer.FrameCallback { frameTimeNanos ->
        isFrameScheduled = false
        val deltaSeconds = if (lastFrameNanos ==
            0L
        ) {
            0.0
        } else {
            (frameTimeNanos - lastFrameNanos) / 1e9
        }
        lastFrameNanos = frameTimeNanos
        motion.advance(min(deltaSeconds, MAX_FRAME_SECONDS))
        renderSwipe()
        scheduleSwipeFrameIfNeeded()
    }

    init {
        clipChildren = true
        actionsLayer.addView(renameButton)
        actionsLayer.addView(pinButton)
        actionsLayer.addView(deleteButton)
        addView(actionsLayer, LayoutParams(0, 0))
        addView(rowView, LayoutParams(0, WRAP_CONTENT))
        addView(swipeHandle, LayoutParams(0, 0))
        setConstraints {
            toStart(rowView)
            toEnd(rowView)
            toTop(rowView)
            allEdges(actionsLayer)
            toTop(swipeHandle)
            toBottom(swipeHandle)
            toEnd(swipeHandle)
        }
        rowView.setOnClickListener { onTap?.invoke() }
        rowView.setOnLongClickListener {
            if (isSwipeOpen) return@setOnLongClickListener false
            onLongPress?.invoke()
            onLongPress != null
        }
        renameButton.setOnClickListener { closeSwipe(isAnimated = true) { onRename?.invoke() } }
        pinButton.setOnClickListener { closeSwipe(isAnimated = true) { onTogglePin?.invoke() } }
        deleteButton.setOnClickListener { closeSwipe(isAnimated = true) { onDelete?.invoke() } }
        renameButton.configure(UIAgentR.drawable.ic_agent_swipe_rename, 30)
        deleteButton.configure(UIAgentR.drawable.ic_agent_trash_filled, 30)
        motion.configure(AgentThreadSwipeParameters(count = 3))
        updateTheme()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val density = resources.displayMetrics.density.toDouble()
        motion.configure(
            AgentThreadSwipeParameters(width = w / density, count = 3, density = density)
        )
        swipeHandle.layoutParams = swipeHandle.layoutParams.apply { width = computeEdgeZoneWidth() }
        renderSwipe()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        // The actions are placed against the layer's own size, known only now
        if (changed) renderSwipe()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        isFrameScheduled = false
        rowView.shouldHoldHighlight = false
        resetSwipe()
    }

    fun configure(
        item: AgentV2ThreadListItem,
        activityText: String?,
        isUnread: Boolean,
        is24HourFormat: Boolean
    ) {
        val thread = item.thread
        if (threadId != thread.id) {
            threadId = thread.id
            rowView.shouldHoldHighlight = false
            resetSwipe()
        }
        val title = thread.title?.takeIf { it.isNotBlank() }
        val preview = item.preview?.takeIf { it.isNotBlank() }
        val isPinned = thread.isPinned == true
        avatarView.configure(thread.id, thread.icon)
        rowView.setTexts(
            title = title ?: preview ?: resolveAgentThreadTitle(thread),
            preview = if (title == null) null else preview,
            time = AgentThreadDateFormatting.formatRowTimestamp(
                agentThreadActivityDate(thread),
                Date(),
                shouldShowDateWhenNotToday = isPinned,
                is24HourFormat = is24HourFormat,
                locale = Locale.forLanguageTag(LocaleController.activeLanguage.langCode)
            ),
            previewImageUrl = agentThreadPreviewImageUrl(thread),
            supportLabel = getAgentSupportLabelStyle(thread.support)
        )
        rowView.isPinned = isPinned
        rowView.isUnread = isUnread
        rowView.setActivity(activityText, isAnimated = false)
        val pinIcon = if (isPinned) {
            UIAgentR.drawable.ic_agent_swipe_unpin
        } else {
            UIAgentR.drawable.ic_agent_swipe_pin
        }
        pinButton.configure(pinIcon, 20)
        pinButton.contentDescription = LocaleController.getString(if (isPinned) "Unpin" else "Pin")
        renameButton.contentDescription = LocaleController.getString("Rename")
        deleteButton.contentDescription = LocaleController.getString("Delete")
        updateAccessibility(isPinned)
        // A theme change reaches the rows only as they rebind
        updateTheme()
    }

    /** Shows what the Agent is doing while it answers in place of the preview, or the preview again */
    fun setActivity(text: String?, isUnread: Boolean) {
        rowView.isUnread = isUnread
        rowView.setActivity(text, isAnimated = true)
        updateAccessibility(rowView.isPinned)
    }

    fun closeSwipe(isAnimated: Boolean, then: (() -> Unit)? = null) {
        if (!isSwipeOpen) {
            then?.invoke()
            return
        }
        isSwiping = false
        motion.settle(0.0, 0.0, isAnimated && WGlobalStorage.getAreAnimationsActive())
        renderSwipe()
        scheduleSwipeFrameIfNeeded()
        then?.invoke()
    }

    private fun resetSwipe() {
        isSwiping = false
        motion.reset()
        renderSwipe()
    }

    private fun updateAccessibility(isPinned: Boolean) {
        rowView.contentDescription = listOfNotNull(
            rowView.titleText,
            LocaleController.getString("\$agent_support_label").takeIf { rowView.hasSupportLabel },
            rowView.activityText ?: rowView.previewText,
            rowView.timeText,
            LocaleController.getString("Pinned").takeIf { isPinned },
            LocaleController.getString("Unread").takeIf { rowView.isUnreadDotShown }
        ).filter { it.isNotEmpty() }.joinToString(", ")
        listOf(
            ACTION_RENAME to LocaleController.getString("Rename"),
            ACTION_PIN to LocaleController.getString(if (isPinned) "Unpin" else "Pin"),
            ACTION_DELETE to LocaleController.getString("Delete")
        ).forEach { (key, label) ->
            ViewCompat.removeAccessibilityAction(rowView, actionIds[key] ?: View.NO_ID)
            actionIds[key] = ViewCompat.addAccessibilityAction(rowView, label) { _, _ ->
                when (key) {
                    ACTION_RENAME -> onRename?.invoke()
                    ACTION_PIN -> onTogglePin?.invoke()
                    else -> onDelete?.invoke()
                }
                true
            }
        }
    }

    // Swipe

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        trackVelocity(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x
                downY = event.y
                isSwiping = false
                isSwipeCandidate = canBeginSwipe(event.x, event.y)
                // A tap on an open row, or beside its actions, closes it rather than opening the chat
                shouldCloseOnTap = isSwipeOpen && !actionsLayer.isOnVisibleButton(event.x, event.y)
                if (shouldCloseOnTap) return true
            }

            MotionEvent.ACTION_MOVE -> if (shouldBeginSwipe(event)) {
                beginSwipe()
                return true
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> recycleVelocityTracker()
        }
        return isSwiping
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        trackVelocity(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_MOVE -> {
                if (!isSwiping && shouldBeginSwipe(event)) beginSwipe()
                if (isSwiping) changeSwipe(event)
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val isCancelled = event.actionMasked == MotionEvent.ACTION_CANCEL
                when {
                    isSwiping -> endSwipe(isCancelled)
                    shouldCloseOnTap && !isCancelled -> closeSwipe(isAnimated = true)
                }
                shouldCloseOnTap = false
                recycleVelocityTracker()
            }
        }
        return isSwiping || shouldCloseOnTap
    }

    override fun canScrollHorizontally(direction: Int): Boolean =
        isSwipeOpen || super.canScrollHorizontally(direction)

    private fun canBeginSwipe(x: Float, y: Float): Boolean {
        if (isMenuShown || onDelete == null) return false
        // A touch on an action stays a tap on it
        if (actionsLayer.isOnVisibleButton(x, y)) return false
        if (isSwipeOpen) return true
        return if (LocaleController.isRTL) {
            x <= computeEdgeZoneWidth()
        } else {
            x >=
                width - computeEdgeZoneWidth()
        }
    }

    private fun shouldBeginSwipe(event: MotionEvent): Boolean {
        if (isSwiping || !isSwipeCandidate) return false
        val dx = event.x - downX
        val dy = event.y - downY
        if (abs(dx) <= touchSlop || abs(dx) <= abs(dy) * SWIPE_DIRECTION_RATIO) return false
        // A closed row opens only toward the leading edge
        return isSwipeOpen || dx * swipeSign < 0
    }

    private fun beginSwipe() {
        isSwiping = true
        shouldCloseOnTap = false
        parent?.requestDisallowInterceptTouchEvent(true)
        rowView.isPressed = false
        rowView.cancelLongPress()
        motion.begin()
        onSwipeBegan?.invoke()
        renderSwipe()
    }

    private fun changeSwipe(event: MotionEvent) {
        val density = resources.displayMetrics.density
        val translation = -(event.x - downX) * swipeSign / density
        val velocity = computeCurrentVelocity()
        val hasBeenArmed = motion.isArmed
        val distanceFromCommitEdge = if (LocaleController.isRTL) width - event.x else event.x
        motion.change(
            translation.toDouble(),
            velocity,
            (distanceFromCommitEdge / density).toDouble(),
            isReducedMotion = !WGlobalStorage.getAreAnimationsActive()
        )
        if (hasBeenArmed != motion.isArmed) Haptics.play(this, HapticType.SELECTION)
        renderSwipe()
        scheduleSwipeFrameIfNeeded()
    }

    private fun endSwipe(isCancelled: Boolean) {
        isSwiping = false
        parent?.requestDisallowInterceptTouchEvent(false)
        val shouldAnimate = WGlobalStorage.getAreAnimationsActive()
        val translation = -(lastX - downX) * swipeSign / resources.displayMetrics.density
        val isCommitted = motion.end(
            translation.toDouble(),
            computeCurrentVelocity(),
            isCancelled,
            shouldAnimate
        )
        if (isCommitted) {
            // A full swipe runs Delete, which asks for confirmation, while the row slides back
            motion.settle(0.0, motion.body.velocity, shouldAnimate)
            onDelete?.invoke()
        }
        renderSwipe()
        scheduleSwipeFrameIfNeeded()
    }

    private var lastX = 0f

    private fun trackVelocity(event: MotionEvent) {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) recycleVelocityTracker()
        val tracker = velocityTracker ?: VelocityTracker.obtain().also { velocityTracker = it }
        tracker.addMovement(event)
        lastX = event.x
    }

    // The velocity toward the leading edge, in dp per second
    private fun computeCurrentVelocity(): Double {
        val tracker = velocityTracker ?: return 0.0
        tracker.computeCurrentVelocity(1000)
        return (-tracker.xVelocity * swipeSign / resources.displayMetrics.density).toDouble()
    }

    private fun recycleVelocityTracker() {
        velocityTracker?.recycle()
        velocityTracker = null
    }

    private fun computeEdgeZoneWidth(): Int {
        val windowWidth = rootView?.width?.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels
        return min(EDGE_ZONE_MAX.dp, max(EDGE_ZONE_MIN.dp, windowWidth / 6))
    }

    private fun scheduleSwipeFrameIfNeeded() {
        if (motion.isAtRest || isFrameScheduled) {
            if (motion.isAtRest) lastFrameNanos = 0L
            return
        }
        isFrameScheduled = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private fun renderSwipe() {
        val density = resources.displayMetrics.density
        val distance = (motion.body.value * density).toFloat()
        rowView.translationX = -distance * swipeSign
        rowView.surface = motion.surface.value.toFloat().coerceIn(0f, 1f)
        actionsLayer.layoutButtons(
            motion,
            listOf(deleteButton, pinButton, renameButton),
            distance,
            density
        )
    }

    override fun updateTheme() {
        rowView.updateTheme()
        renameButton.setColors(WColor.Tint.color, WColor.TextOnTint.color)
        pinButton.setColors(SWIPE_PIN_COLOR, WColor.White.color)
        deleteButton.setColors(SWIPE_DELETE_COLOR, WColor.White.color)
    }

    private companion object {
        const val SWIPE_DIRECTION_RATIO = 1.2f
        const val EDGE_ZONE_MIN = 22
        const val EDGE_ZONE_MAX = 80
        const val MAX_FRAME_SECONDS = 1.0 / 30
        const val ACTION_RENAME = 0
        const val ACTION_PIN = 1
        const val ACTION_DELETE = 2
        val SWIPE_PIN_COLOR = 0xFFFFCA00.toInt()
        val SWIPE_DELETE_COLOR = 0xFFFF5148.toInt()
    }
}

/** A row of the Agent list, drawn as a card while it is swiped over the actions it uncovers */
internal class AgentThreadRowView(context: Context, private val avatarView: View) :
    ViewGroup(context) {
    private val titleLabel = WLabel(context).apply {
        id = UIComponentsR.id.agent_thread_title
        setStyle(16f, WFont.Medium)
        setLineHeight(24f)
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
        useCustomEmoji = true
        textAlignment = TEXT_ALIGNMENT_VIEW_START
    }
    private val previewLabel = WLabel(context).apply {
        setStyle(14f)
        setLineHeight(20f)
        maxLines = 2
        ellipsize = TextUtils.TruncateAt.END
        useCustomEmoji = true
        textAlignment = TEXT_ALIGNMENT_VIEW_START
    }
    private val timeLabel = WLabel(context).apply {
        setStyle(13f)
        setLineHeight(18f)
        isSingleLine = true
    }
    private val pinIcon = ImageView(context).apply {
        id = generateViewId()
        setImageResource(R.drawable.ic_pin_solid_14_20)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val previewThumbnail = WCustomImageView(context).apply {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private var previewImageUrl: String? = null
    private var preview: String? = null
    private var supportLabel: AgentSupportLabelStyle? = null
    private val unreadDot = AgentUnreadDotView(context)
    private val unreadBadge = WLabel(context).apply {
        setStyle(AgentThreadRowMetrics.UNREAD_BADGE_TEXT_SIZE, WFont.Bold)
        gravity = Gravity.CENTER
        isSingleLine = true
        includeFontPadding = false
        val padding = AgentThreadRowMetrics.UNREAD_BADGE_PADDING.dp
        setPadding(padding, 0, padding, 0)
        background = AgentUnreadBadgeDrawable()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private var activityLine: ActivityLine? = null
    private val fadingLines = mutableListOf<ActivityLine>()
    private val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val cardRect = RectF()
    private val ripple = WRippleDrawable.create(0f)

    var surface = 0f
        set(value) {
            if (field == value) return
            field = value
            invalidate()
        }

    var isPinned = false
        set(value) {
            field = value
            pinIcon.isVisible = value
        }

    var isUnread = false
        set(value) {
            field = value
            updateUnreadDot()
        }

    var unreadCountText: String? = null
        set(value) {
            if (field == value) return
            field = value
            unreadBadge.text = value
            updateUnreadDot()
            requestLayout()
        }

    /** Keeps the row pressed after the touch ends, as while the chat it opens slides in */
    var shouldHoldHighlight = false
        set(value) {
            if (field == value) return
            field = value
            isPressed = value
        }

    val isUnreadDotShown: Boolean get() = unreadDot.isVisible || unreadBadge.isVisible
    val titleText: String get() = titleLabel.text?.toString().orEmpty()
    val previewText: String get() = preview.orEmpty()
    val hasSupportLabel: Boolean get() = supportLabel != null
    val timeText: String get() = timeLabel.text?.toString().orEmpty()
    val activityText: String? get() = activityLine?.text

    init {
        id = UIComponentsR.id.agent_thread_row
        setWillNotDraw(false)
        isClickable = true
        isLongClickable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        background = ripple
        addView(avatarView)
        addView(pinIcon)
        addView(titleLabel)
        addView(timeLabel)
        addView(previewLabel)
        addView(previewThumbnail)
        addView(unreadDot)
        addView(unreadBadge)
        listOf(titleLabel, previewLabel, timeLabel).forEach {
            it.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        pinIcon.isVisible = false
        previewThumbnail.isVisible = false
        unreadDot.isVisible = false
        unreadBadge.isVisible = false
    }

    /** [supportLabel]: a chat with support carries its label before the preview */
    fun setTexts(
        title: String,
        preview: String?,
        time: String,
        previewImageUrl: String? = null,
        supportLabel: AgentSupportLabelStyle? = null
    ) {
        titleLabel.text = title
        timeLabel.text = time
        this.preview = preview
        this.supportLabel = supportLabel
        val imageUrl = previewImageUrl?.takeIf { preview != null }
        if (imageUrl != this.previewImageUrl) {
            this.previewImageUrl = imageUrl
            if (imageUrl == null) {
                previewThumbnail.clear()
            } else {
                previewThumbnail.set(
                    Content(
                        Content.Image.Url(imageUrl),
                        rounding = Content.Rounding.Radius(
                            AgentThreadRowMetrics.PREVIEW_THUMBNAIL_RADIUS.dp
                        ),
                        placeholder = Content.Placeholder.Color(WColor.Transparent),
                        decodeSize = AgentThreadRowMetrics.PREVIEW_THUMBNAIL.dp
                    )
                )
            }
        }
        previewThumbnail.isVisible = imageUrl != null
        previewLabel.text = if (imageUrl == null && supportLabel == null) {
            preview
        } else {
            SpannableStringBuilder().apply {
                // Keeps its place while loading, so the text doesn't move
                if (imageUrl != null) {
                    append(
                        " ",
                        ThumbnailSpace(AgentThreadRowMetrics.PREVIEW_THUMBNAIL_SPACE.dp),
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
                if (supportLabel != null) {
                    append(
                        " ",
                        AgentSupportLabelSpan(context, supportLabel),
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
                if (preview != null) append(preview)
            }
        }
    }

    fun setActivity(text: String?, isAnimated: Boolean) {
        val shouldAnimate =
            isAnimated && isAttachedToWindow && WGlobalStorage.getAreAnimationsActive()
        // A rebind settles any crossfade still running from the row's last item
        if (!shouldAnimate) finishCrossfades()
        val line = activityLine
        if (text == null) {
            if (line == null) {
                if (!shouldAnimate) setPreviewAlpha(1f)
                return
            }
            activityLine = null
            if (!shouldAnimate) {
                removeView(line)
                setPreviewAlpha(1f)
            } else {
                fadingLines.add(line)
                line.animate().alpha(0f).setDuration(CROSSFADE_MS)
                    .withEndAction {
                        fadingLines.remove(line)
                        removeView(line)
                    }
                fadePreview(1f)
            }
            updateUnreadDot()
            return
        }
        if (line != null) {
            line.setText(text, shouldAnimate)
            if (!shouldAnimate) setPreviewAlpha(0f)
            return
        }
        // The line and its spinning top join the row only while it is active, so idle rows don't animate
        val newLine = ActivityLine(context).apply { setText(text, isAnimated = false) }
        activityLine = newLine
        addView(newLine)
        if (shouldAnimate) {
            newLine.alpha = 0f
            newLine.animate().alpha(1f).setDuration(CROSSFADE_MS).start()
            fadePreview(0f)
        } else {
            setPreviewAlpha(0f)
        }
        updateUnreadDot()
    }

    private fun setPreviewAlpha(alpha: Float) {
        previewLabel.alpha = alpha
        previewThumbnail.alpha = alpha
    }

    private fun fadePreview(alpha: Float) {
        previewLabel.animate().alpha(alpha).setDuration(CROSSFADE_MS).start()
        previewThumbnail.animate().alpha(alpha).setDuration(CROSSFADE_MS).start()
    }

    private fun finishCrossfades() {
        previewLabel.animate().cancel()
        previewThumbnail.animate().cancel()
        activityLine?.let {
            it.animate().cancel()
            it.alpha = 1f
        }
        fadingLines.forEach {
            it.animate().cancel()
            removeView(it)
        }
        fadingLines.clear()
    }

    // The dot marks an unseen answer once the Agent has finished; while it answers, the status takes the row
    private fun updateUnreadDot() {
        val isMarked = isUnread && activityLine == null
        unreadDot.isVisible = isMarked && unreadCountText == null
        unreadBadge.isVisible = isMarked && unreadCountText != null
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val metrics = AgentThreadRowMetrics
        val contentStart = metrics.contentStart
        val contentWidth = (width - contentStart - metrics.HORIZONTAL_PADDING.dp).coerceAtLeast(0)
        val avatarSpec = MeasureSpec.makeMeasureSpec(metrics.AVATAR.dp, MeasureSpec.EXACTLY)
        avatarView.measure(avatarSpec, avatarSpec)
        pinIcon.measure(
            MeasureSpec.makeMeasureSpec(metrics.PIN_WIDTH.dp, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(metrics.PIN_HEIGHT.dp, MeasureSpec.EXACTLY)
        )
        timeLabel.measure(makeUnspecifiedSpec(), makeUnspecifiedSpec())
        val pinSpace = if (isPinned) (metrics.PIN_WIDTH + metrics.PIN_GAP).dp else 0
        val titleWidth = contentWidth - timeLabel.measuredWidth - metrics.TIME_GAP.dp - pinSpace
        titleLabel.measure(makeAtMostSpec(titleWidth), makeUnspecifiedSpec())
        val dotSpec = makeExactSpec(metrics.UNREAD_DOT.dp)
        unreadDot.measure(dotSpec, dotSpec)
        measureUnreadBadge()
        val dotSpace = when {
            unreadDot.isVisible -> (metrics.UNREAD_DOT + metrics.UNREAD_GAP).dp
            unreadBadge.isVisible -> unreadBadge.measuredWidth + metrics.UNREAD_GAP.dp
            else -> 0
        }
        previewLabel.measure(makeExactSpec(contentWidth - dotSpace), makeUnspecifiedSpec())
        val thumbnailSpec = makeExactSpec(metrics.PREVIEW_THUMBNAIL.dp)
        previewThumbnail.measure(thumbnailSpec, thumbnailSpec)
        activityLine?.measure(
            makeExactSpec(contentWidth + metrics.ACTIVITY_TOP_INSET.dp),
            makeExactSpec(metrics.ACTIVITY_TOP.dp)
        )
        val titleRow = max(metrics.TITLE_LINE.dp, titleLabel.measuredHeight)
        val previewBox = max(metrics.PREVIEW_BOX.dp, previewLabel.measuredHeight)
        val height = max(
            metrics.MIN_HEIGHT.dp,
            2 * metrics.VERTICAL_PADDING.dp + titleRow + previewBox
        )
        setMeasuredDimension(width, height)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val metrics = AgentThreadRowMetrics
        val width = right - left
        val height = bottom - top
        val isRtl = LocaleController.isRTL
        fun place(view: View, x: Int, y: Int) {
            val start = if (isRtl) width - x - view.measuredWidth else x
            view.layout(start, y, start + view.measuredWidth, y + view.measuredHeight)
        }
        place(avatarView, metrics.HORIZONTAL_PADDING.dp, (height - avatarView.measuredHeight) / 2)
        val contentStart = metrics.contentStart
        val contentEnd = width - metrics.HORIZONTAL_PADDING.dp
        val titleRow = max(metrics.TITLE_LINE.dp, titleLabel.measuredHeight)
        val previewBox = max(metrics.PREVIEW_BOX.dp, previewLabel.measuredHeight)
        val titleTop = (height - titleRow - previewBox) / 2
        var titleStart = contentStart
        if (isPinned) {
            place(pinIcon, contentStart, titleTop + (titleRow - pinIcon.measuredHeight) / 2)
            titleStart += (metrics.PIN_WIDTH + metrics.PIN_GAP).dp
        }
        place(titleLabel, titleStart, titleTop + (titleRow - titleLabel.measuredHeight) / 2)
        place(
            timeLabel,
            contentEnd - timeLabel.measuredWidth,
            titleTop + (titleRow - timeLabel.measuredHeight) / 2
        )
        val previewTop = titleTop + titleRow
        place(previewLabel, contentStart, previewTop)
        if (previewThumbnail.isVisible) layoutPreviewThumbnail()
        place(
            unreadDot,
            contentEnd - unreadDot.measuredWidth,
            previewTop + (previewBox - unreadDot.measuredHeight) / 2
        )
        place(
            unreadBadge,
            contentEnd - unreadBadge.measuredWidth,
            previewTop + (previewBox - unreadBadge.measuredHeight) / 2
        )
        activityLine?.let { place(it, contentStart - metrics.ACTIVITY_TOP_INSET.dp, previewTop) }
    }

    private fun layoutPreviewThumbnail() {
        val layout = previewLabel.layout ?: return
        val size = previewThumbnail.measuredWidth
        val spaceStart = layout.getPrimaryHorizontal(0)
        val spaceEnd = layout.getPrimaryHorizontal(1)
        val left = if (layout.getParagraphDirection(0) == Layout.DIR_RIGHT_TO_LEFT) {
            max(spaceStart, spaceEnd).roundToInt() - size
        } else {
            min(spaceStart, spaceEnd).roundToInt()
        }
        val metrics = previewLabel.paint.fontMetricsInt
        val textCenter = layout.getLineBaseline(0) + (metrics.ascent + metrics.descent) / 2
        val x = previewLabel.left + previewLabel.totalPaddingLeft + left
        val y = previewLabel.top + previewLabel.totalPaddingTop + textCenter - size / 2
        previewThumbnail.layout(x, y, x + size, y + size)
    }

    override fun dispatchDraw(canvas: Canvas) {
        if (surface > 0f) {
            cardRect.set(0f, 0f, width.toFloat(), height.toFloat())
            val radius = AgentThreadRowMetrics.CARD_RADIUS.dp * surface
            cardPaint.color = getSwipeCardColor()
            cardPaint.alpha = (cardPaint.alpha * surface).roundToInt()
            canvas.drawRoundRect(cardRect, radius, radius, cardPaint)
        }
        super.dispatchDraw(canvas)
    }

    override fun setPressed(pressed: Boolean) {
        super.setPressed(pressed || shouldHoldHighlight)
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = Button::class.java.name
    }

    fun updateTheme() {
        ripple.rippleColor = WColor.SecondaryBackground.color
        titleLabel.setTextColor(WColor.PrimaryText)
        previewLabel.setTextColor(WColor.SecondaryText)
        timeLabel.setTextColor(WColor.SecondaryText)
        pinIcon.setColorFilter(WColor.SecondaryText.color)
        unreadBadge.setTextColor(WColor.White)
        invalidate()
    }

    private fun measureUnreadBadge() {
        val height = AgentThreadRowMetrics.UNREAD_BADGE_HEIGHT.dp
        val heightSpec = makeExactSpec(height)
        unreadBadge.measure(makeUnspecifiedSpec(), heightSpec)
        unreadBadge.measure(makeExactSpec(max(height, unreadBadge.measuredWidth)), heightSpec)
    }

    // The swiped row's card: the page color in light mode, a light wash in dark mode
    private fun getSwipeCardColor(): Int = if (ThemeManager.isDark) {
        ColorUtils.setAlphaComponent(WColor.White.color, DARK_CARD_ALPHA)
    } else {
        WColor.SecondaryBackground.color
    }

    private fun makeUnspecifiedSpec() = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
    private fun makeExactSpec(size: Int) =
        MeasureSpec.makeMeasureSpec(size.coerceAtLeast(0), MeasureSpec.EXACTLY)

    private fun makeAtMostSpec(size: Int) =
        MeasureSpec.makeMeasureSpec(size.coerceAtLeast(0), MeasureSpec.AT_MOST)

    /** What the Agent is doing: its spinning top, then the step in the Agent gradient */
    private class ActivityLine(context: Context) : FrameLayout(context) {
        private val spinningTop = AgentSpinningTopView(context, isOnChatBackground = false)
        private val status = AgentStatusTextView(context, 14f, WFont.Medium, 20f)

        val text: String? get() = status.text?.toString()

        init {
            id = generateViewId()
            clipChildren = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            val metrics = AgentThreadRowMetrics
            addView(
                spinningTop,
                LayoutParams(metrics.ACTIVITY_TOP.dp, metrics.ACTIVITY_TOP.dp).apply {
                    gravity = Gravity.START or Gravity.CENTER_VERTICAL
                    marginStart = (metrics.ACTIVITY_TOP_BOX_WIDTH - metrics.ACTIVITY_TOP).dp / 2
                }
            )
            addView(
                status,
                LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    gravity = Gravity.CENTER_VERTICAL
                    marginStart = metrics.ACTIVITY_TOP_BOX_WIDTH.dp
                }
            )
        }

        fun setText(text: String, isAnimated: Boolean) = status.setText(text, isAnimated)
    }

    private companion object {
        const val CROSSFADE_MS = 150L
        const val DARK_CARD_ALPHA = 20
    }
}

/**
 * A swipe action: a circle in its color with an icon, which stretches into a pill for an armed
 * Delete
 */
@SuppressLint("ViewConstructor")
private class SwipeActionButton(context: Context, viewId: Int) : FrameLayout(context) {
    private val circle = GradientDrawable().apply { cornerRadius = BUTTON_SIZE.dp / 2f }
    private val icon = ImageView(context).apply {
        id = generateViewId()
        scaleType = ImageView.ScaleType.FIT_CENTER
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private var iconSize = 30.dp

    var iconOffset = 0f
        set(value) {
            field = value
            icon.translationX = value
        }

    init {
        id = viewId
        background = circle
        isClickable = true
        isFocusable = true
        addView(icon, LayoutParams(iconSize, iconSize, Gravity.CENTER))
    }

    fun configure(iconResource: Int, sizeDp: Int) {
        icon.setImageResource(iconResource)
        iconSize = sizeDp.dp
        icon.layoutParams = LayoutParams(iconSize, iconSize, Gravity.CENTER)
    }

    fun setColors(color: Int, iconColor: Int) {
        circle.setColor(color)
        icon.setColorFilter(iconColor)
    }

    override fun setPressed(pressed: Boolean) {
        super.setPressed(pressed)
        // Pressed, an action's brightness drops to 90%
        foreground = if (pressed) {
            GradientDrawable().apply {
                cornerRadius = BUTTON_SIZE.dp / 2f
                setColor(PRESSED_SHADE)
            }
        } else {
            null
        }
    }

    companion object {
        const val BUTTON_SIZE = 48
        const val PRESSED_SHADE = 0x1A000000
    }
}

/** Lays the actions out from the reveal geometry each frame, without a layout pass of the list */
private class SwipeActionsLayer(context: Context) : FrameLayout(context) {
    private companion object {
        const val MIN_SCALE = 0.0001f
    }

    private val buttons = mutableListOf<SwipeActionButton>()

    init {
        id = generateViewId()
        clipChildren = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        // Buttons are placed by `layoutButtons`
    }

    fun layoutButtons(
        motion: AgentThreadSwipeMotion,
        ordered: List<SwipeActionButton>,
        revealed: Float,
        density: Float
    ) {
        buttons.clear()
        buttons.addAll(ordered)
        val isRtl = LocaleController.isRTL
        val size = SwipeActionButton.BUTTON_SIZE.dp
        val geometry = motion.buttonGeometry
        isVisible = revealed > 0.5f
        // Geometry counts from the outer edge: Delete, then Pin, then Rename
        ordered.forEachIndexed { index, button ->
            val item = geometry.getOrNull(index) ?: return@forEachIndexed
            val buttonWidth = max(size, (item.width * density).roundToInt())
            val centerFromTrailing = (item.center * density).toFloat()
            val centerX = if (isRtl) centerFromTrailing else width - centerFromTrailing
            val buttonLeft = (centerX - buttonWidth / 2f).roundToInt()
            val buttonTop = (height - size) / 2
            button.measure(
                MeasureSpec.makeMeasureSpec(buttonWidth, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(size, MeasureSpec.EXACTLY)
            )
            button.layout(buttonLeft, buttonTop, buttonLeft + buttonWidth, buttonTop + size)
            val scale = (motion.scales.getOrNull(index)?.value?.toFloat() ?: 1f)
                .coerceAtLeast(MIN_SCALE)
            val opacity = (motion.opacities.getOrNull(index)?.value?.toFloat() ?: 1f)
                .coerceIn(0f, 1f)
            button.scaleX = scale
            button.scaleY = scale
            button.alpha = opacity
            button.isEnabled = opacity > 0.1f && scale > 0.3f
            if (index == 0) {
                // Once armed, the icon moves to the end of the stretched action that follows the finger
                val expansion = motion.expansion.value.toFloat().coerceIn(0f, 1f)
                val travel = (buttonWidth - size) / 2f * expansion
                button.iconOffset = if (isRtl) travel else -travel
            }
        }
    }

    fun isOnVisibleButton(x: Float, y: Float): Boolean = isVisible && buttons.any { button ->
        button.isEnabled && x >= button.left && x <= button.right && y >= button.top &&
            y <= button.bottom
    }
}

/** The strip at the trailing edge that tells the tab pager a swipe there belongs to the row */
private class SwipeHandleView(context: Context) : View(context) {
    init {
        id = generateViewId()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun canScrollHorizontally(direction: Int): Boolean {
        val opensTowardLeading = if (LocaleController.isRTL) direction < 0 else direction > 0
        return opensTowardLeading && (parent as? View)?.isEnabled != false
    }
}

private class ThumbnailSpace(private val width: Int) : ReplacementSpan() {
    override fun getSize(
        paint: Paint,
        text: CharSequence?,
        start: Int,
        end: Int,
        fontMetrics: Paint.FontMetricsInt?
    ): Int = width

    override fun draw(
        canvas: Canvas,
        text: CharSequence?,
        start: Int,
        end: Int,
        x: Float,
        top: Int,
        y: Int,
        bottom: Int,
        paint: Paint
    ) = Unit
}
