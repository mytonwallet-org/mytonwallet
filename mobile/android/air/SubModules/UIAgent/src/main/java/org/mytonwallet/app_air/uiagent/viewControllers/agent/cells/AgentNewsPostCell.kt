package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Outline
import android.graphics.Rect
import android.os.Bundle
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.core.animation.doOnEnd
import androidx.core.graphics.createBitmap
import androidx.core.view.AccessibilityDelegateCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.RecyclerView
import java.net.URI
import java.util.Date
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentIncomingBubbleColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentNewsPostBodyText
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_BUBBLE_RADIUS
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_BUBBLE_TAIL_WIDTH
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_TAIL_REVEAL_DAMPING
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_TAIL_REVEAL_DELAY_MS
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_TAIL_REVEAL_DURATION_MS
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBubbleDrawable
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentImagePinchZoom
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsDiscussStrip
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsIconView
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsTextBlock
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.MediaViewerVC
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.Vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard

/** A WRecyclerView takes multi-finger touches from its rows, so the list must leave this pinch to the row. */
internal fun isAgentPicturePinchStart(list: RecyclerView, event: MotionEvent): Boolean {
    if (event.actionMasked != MotionEvent.ACTION_POINTER_DOWN || event.pointerCount != 2) {
        return false
    }
    val row = list.findChildViewUnder(event.getX(0), event.getY(0)) as? AgentNewsPostCell
    return row?.canStartPictureZoom(list, event) == true
}

/** A news post in a chat, or a News feed card ([Style.FEED_CARD]). */
@SuppressLint("ViewConstructor")
internal class AgentNewsPostCell(
    context: Context,
    textCache: AgentMessageTextCache,
    style: Style = Style.DISCUSSION_POST
) : WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {
    enum class Style { DISCUSSION_POST, FEED_CARD }

    private val isFeedCard = style == Style.FEED_CARD
    private val bubbleDrawable = AgentBubbleDrawable(isOutgoing = false)
    private val bubble = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        background = bubbleDrawable
        setPaddingRelative(AGENT_BUBBLE_TAIL_WIDTH.dp, 0, 0, 0)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        isFocusable = true
    }
    private val icon = AgentNewsIconView(context)
    private val header = WLabel(context).apply {
        setStyle(15f, WFont.Medium)
        text = LocaleController.getString("News")
    }
    private val imageContainer = FrameLayout(context).apply {
        id = generateViewId()
        // A point inside the bubble's sides, so a picture as dark or as light as the bubble never merges with it
        setPadding(IMAGE_INSET.dp, 0, IMAGE_INSET.dp, 0)
    }
    private val image = WCustomImageView(context).apply {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        contentDescription = LocaleController.getString("Picture")
        if (isFeedCard) {
            outlineProvider = TopRoundedOutline(PICTURE_CORNER_RADIUS.dp)
            clipToOutline = true
        }
    }
    private val imageSpacer = View(context).apply { id = generateViewId() }
    private val textBlock = AgentNewsTextBlock(context).apply {
        setPaddingRelative(HORIZONTAL_PADDING.dp, 0, HORIZONTAL_PADDING.dp, META_BOTTOM.dp)
        this.textCache = textCache
    }
    private var postId: String? = null
    private var postDate: Date? = null
    private var news: AgentV2ThreadNewsCard? = null
    private var imageUrl: String? = null
    private var imageFailed = false
    private var bubbleWidth = 0
    private var insertAnimation: SpringAnimation? = null
    private var insertAnimationOnFinished: (() -> Unit)? = null
    private var isInsertAnimationPending = false
    private var insertAnimationTargetHeight = 0
    private var isRenderingEnabled = true

    private val menuTouch = AgentMenuTouch()
    private val pictureCornerRadius = if (isFeedCard) PICTURE_CORNER_RADIUS.dp else 0f
    private val imageZoom = AgentImagePinchZoom(image, pictureCornerRadius)
    private var imageAspectRatio: Float? = null

    val discussStrip: AgentNewsDiscussStrip? =
        if (isFeedCard) AgentNewsDiscussStrip(context) else null

    /** Whether a tap may open the menu now; the chat says no to a tap that stops its scroll */
    var canOpenMenuOnTap: () -> Boolean = { true }

    /** How the chat opens the menu, which may wait for the keyboard to go */
    var menuPresenter: AgentMenuPresenter? = null

    /** Rows where the menu leaves the bubble undimmed */
    var menuRows: AgentMenuRows = { getAgentListRows(this) }
    private var openSourceAction: Int? = null

    var onOpenSource: ((url: String) -> Unit)? = null
    var onPopupVisibilityChanged: ((visible: Boolean) -> Unit)? = null

    var onCopied: (() -> Unit)? = null

    var onPictureTap: (() -> Unit)? = null
    var onSizeTransitionFrame: ((previousHeight: Int) -> Unit)? = null
    var onInsertAnimationStarted: ((targetHeight: Int) -> Unit)? = null
    var onInsertAnimationFinished: (() -> Unit)? = null
    internal val layoutTargetHeight: Int
        get() = insertAnimationTargetHeight.takeIf { it > 0 } ?: height

    /** The post's bubble without its tail, where a news card flown in from the feed lands */
    internal val postView: View get() = bubble

    val shownPostId: String? get() = postId

    init {
        id = UIComponentsR.id.agent_message_assistant
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        val headerRow = LinearLayout(context).apply {
            id = generateViewId()
            isGone = isFeedCard
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPaddingRelative(
                HORIZONTAL_PADDING.dp,
                HEADER_TOP.dp,
                HORIZONTAL_PADDING.dp,
                HEADER_BOTTOM.dp
            )
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            addView(icon, LinearLayout.LayoutParams(HEADER_ICON.dp, HEADER_ICON.dp))
            addView(
                header,
                LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    marginStart = HEADER_ICON_GAP.dp
                }
            )
        }
        imageContainer.addView(image, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        bubble.addView(headerRow, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        bubble.addView(
            imageContainer,
            LinearLayout.LayoutParams(MATCH_PARENT, 0).apply {
                if (isFeedCard) topMargin = IMAGE_INSET.dp
            }
        )
        bubble.addView(imageSpacer, LinearLayout.LayoutParams(MATCH_PARENT, IMAGE_GAP.dp))
        bubble.addView(textBlock, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        discussStrip?.let {
            bubble.addView(it, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        // A tap or a long press opens the post's menu, as in Telegram; the picture and the source keep their own
        bubble.setOnLongClickListener {
            requestMenu(menuTouch.take(bubble))
            true
        }
        bubble.setMessageMenuTapListener {
            if (!menuTouch.isOn(imageContainer)) {
                if (canOpenMenuOnTap()) requestMenu(menuTouch.take(bubble))
            } else if (image.isImageShown) {
                onPictureTap?.invoke()
            }
        }
        // TalkBack opens the picture from itself; touches still go to the bubble
        ViewCompat.setAccessibilityDelegate(
            image,
            object : AccessibilityDelegateCompat() {
                override fun onInitializeAccessibilityNodeInfo(
                    host: View,
                    info: AccessibilityNodeInfoCompat
                ) {
                    super.onInitializeAccessibilityNodeInfo(host, info)
                    info.isClickable = true
                    info.addAction(
                        AccessibilityNodeInfoCompat.AccessibilityActionCompat(
                            AccessibilityNodeInfoCompat.ACTION_CLICK,
                            LocaleController.getString("Open")
                        )
                    )
                }

                override fun performAccessibilityAction(
                    host: View,
                    action: Int,
                    args: Bundle?
                ): Boolean {
                    if (action != AccessibilityNodeInfoCompat.ACTION_CLICK) {
                        return super.performAccessibilityAction(host, action, args)
                    }
                    if (image.isImageShown) onPictureTap?.invoke()
                    return true
                }
            }
        )
        // TalkBack offers the post's menu as "More actions"
        ViewCompat.replaceAccessibilityAction(
            bubble,
            AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_LONG_CLICK,
            LocaleController.getString("More actions")
        ) { _, _ ->
            requestMenu(touch = null)
            true
        }
        addView(bubble, LayoutParams(0, WRAP_CONTENT))
        // The bubble's body takes the place of the feed's card, so the card lands on it
        setConstraints {
            toTop(bubble, ROW_MARGIN)
            toBottom(bubble, ROW_MARGIN)
            toStart(bubble, LEADING_INSET)
            toEnd(bubble, TRAILING_INSET)
        }
        image.onFinalImageSet = { info ->
            imageAspectRatio = info?.takeIf { it.width > 0 && it.height > 0 }
                ?.let { it.width.toFloat() / it.height }
        }
        image.onFailure = {
            if (!imageContainer.isGone) {
                val previousHeight = height
                imageFailed = true
                setImageHidden(true)
                finishInsertAnimation()
                onSizeTransitionFrame?.invoke(previousHeight)
            }
        }
        updateTheme()
    }

    /** [hasFollowupsBelow]: suggestions hang from the post, which then has no tail. */
    fun configure(
        id: String,
        date: Date,
        news: AgentV2ThreadNewsCard,
        recyclerWidth: Int,
        animate: Boolean = false,
        hasFollowupsBelow: Boolean = false
    ) {
        val previousHeight = height
        val isSameMessage = postId == id
        updateTail(hasTail = !hasFollowupsBelow, isSameMessage = isSameMessage)
        val availableWidth = recyclerWidth.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels
        val nextBubbleWidth = (availableWidth - (LEADING_INSET + TRAILING_INSET).dp.roundToInt())
            .coerceAtLeast(1)
        val imageWidth = nextBubbleWidth - (AGENT_BUBBLE_TAIL_WIDTH + 2 * IMAGE_INSET).dp
        val imageHeight = (imageWidth * IMAGE_ASPECT_RATIO).roundToInt().coerceAtLeast(0)
        val preservesHeight = isSameMessage &&
            (this.news != news || bubbleWidth != nextBubbleWidth)
        if (!isSameMessage) {
            finishInsertAnimation()
            insertAnimationTargetHeight = 0
        }
        postId = id
        postDate = date
        this.news = news
        bubbleWidth = nextBubbleWidth
        imageContainer.updateLayoutParams { height = imageHeight }
        val timeText = parseAgentV2Timestamp(news.publishedAt)
            ?.let { AgentNewsTextBlock.formatPostTime(context, it) }
            .orEmpty()
        val sourceName = sourceName(news)
        textBlock.configure(
            id,
            news.headline,
            agentNewsPostBodyText(news),
            sourceName,
            timeText
        )
        textBlock.onSourceClick = sourceUrl()?.let { url -> { onOpenSource?.invoke(url) } }
        bubble.contentDescription =
            listOf(
                LocaleController.getString("News").takeUnless { isFeedCard },
                news.headline,
                textBlock.bodyText.toString(),
                sourceName,
                timeText
            )
                .filter { !it.isNullOrEmpty() }
                .joinToString(", ")
        updateOpenSourceAction()
        val nextImageUrl = news.imageUrl?.takeIf { it.isNotBlank() }
        if (nextImageUrl != imageUrl) {
            imageFailed = false
            imageAspectRatio = null
            imageZoom.cancel()
        }
        imageUrl = nextImageUrl
        setImageHidden(nextImageUrl == null || imageFailed)
        if (nextImageUrl == null) {
            image.clear()
        } else {
            image.set(
                Content(Content.Image.Url(nextImageUrl), rounding = Content.Rounding.Radius(0f))
            )
        }
        updateTheme()
        val shouldAnimate = animate && WGlobalStorage.getAreAnimationsActive()
        isInsertAnimationPending = shouldAnimate
        if (shouldAnimate) {
            setInsertAppearance(alpha = 0f, scale = 0.8f)
            updateLayoutParams { height = 1 }
            scheduleInsertAnimation()
        } else {
            finishInsertAnimation()
            setInsertAppearance(alpha = 1f, scale = 1f)
            updateLayoutParams { height = WRAP_CONTENT }
            if (onInsertAnimationStarted != null) {
                notifyInsertAnimationStarted(measureExpandedHeight())
            }
            notifyInsertAnimationFinished()
        }
        if (preservesHeight) onSizeTransitionFrame?.invoke(previousHeight)
    }

    fun makePhotoSource(): MediaViewerVC.Source? {
        if (imageContainer.isGone || !image.isImageShown) return null
        return MediaViewerVC.Source(image, pictureCornerRadius, imageAspectRatio, menuRows())
    }

    override fun updateTheme() {
        bubbleDrawable.setBubbleColor(agentIncomingBubbleColor)
        header.setTextColor(WColor.Tint)
        image.setBackgroundColor(agentIncomingBubbleColor)
        icon.updateTheme()
        image.updateTheme()
        textBlock.updateTheme()
    }

    private fun setImageHidden(isHidden: Boolean) {
        imageContainer.isGone = isHidden
        imageSpacer.isGone = isHidden
        if (isFeedCard) {
            textBlock.setPaddingRelative(
                HORIZONTAL_PADDING.dp,
                if (isHidden) HEADER_TOP.dp else 0,
                HORIZONTAL_PADDING.dp,
                META_BOTTOM.dp
            )
        }
    }

    // TalkBack opens the source from the post itself
    private fun updateOpenSourceAction() {
        openSourceAction?.let { ViewCompat.removeAccessibilityAction(bubble, it) }
        openSourceAction = sourceUrl()?.let { url ->
            ViewCompat.addAccessibilityAction(
                bubble,
                LocaleController.getString("\$agent_news_open_source")
            ) { _, _ ->
                onOpenSource?.invoke(url)
                true
            }
        }
    }

    private fun sourceUrl(): String? = news?.let(::agentNewsSourceUrl)

    fun canStartPictureZoom(origin: View, event: MotionEvent): Boolean =
        imageZoom.canStart(origin, event)

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (imageZoom.onTouchEvent(this, event) { super.dispatchTouchEvent(it) }) return true
        menuTouch.track(this, event)
        return super.dispatchTouchEvent(event)
    }

    private fun requestMenu(touch: Vec2i?) {
        val shownId = postId ?: return
        presentAgentMenu(
            menuPresenter,
            bubble,
            touch,
            isStillShown = { isAttachedToWindow && postId == shownId },
            open = ::showMenu
        )
    }

    private var tailAnimator: ValueAnimator? = null

    /** Suggestions came to hang from the post, or went */
    fun setHasFollowupsBelow(hasFollowupsBelow: Boolean) =
        updateTail(hasTail = !hasFollowupsBelow, isSameMessage = true)

    // The tail goes at once as suggestions come, and grows back out of the corner when they go
    private fun updateTail(hasTail: Boolean, isSameMessage: Boolean) {
        val target = if (hasTail) 1f else 0f
        if (bubbleDrawable.tailProgress == target && tailAnimator == null) return
        tailAnimator?.cancel()
        tailAnimator = null
        if (!hasTail || !isSameMessage || !isAttachedToWindow ||
            !WGlobalStorage.getAreAnimationsActive()
        ) {
            bubbleDrawable.tailProgress = target
            return
        }
        tailAnimator = ValueAnimator.ofFloat(bubbleDrawable.tailProgress, 1f).apply {
            duration = AGENT_TAIL_REVEAL_DURATION_MS
            startDelay = AGENT_TAIL_REVEAL_DELAY_MS
            interpolator = WInterpolator.spring(dampingRatio = AGENT_TAIL_REVEAL_DAMPING)
            addUpdateListener { bubbleDrawable.tailProgress = it.animatedValue as Float }
            doOnEnd { if (tailAnimator === this) tailAnimator = null }
            start()
        }
    }

    /** Opens the post's menu from the finger at [touch], a window point, as Telegram does; null opens it at the post */
    private fun showMenu(touch: Vec2i?) {
        val news = news ?: return
        val actions = listOf(buildAgentMessageMenuHeader(context, postDate ?: Date())) +
            buildAgentNewsMenuItems(this, news, onOpenSource, onCopied)
        onPopupVisibilityChanged?.invoke(true)
        WMenuPopup.present(
            bubble,
            actions,
            positioning = WMenuPopup.Positioning.BELOW,
            backdropStyle = WMenuPopup.BackdropStyle.Dimmed,
            windowBackgroundStyle = buildAgentMenuBackdrop(
                bubbleDrawable.buildCutoutPath(bubble),
                menuRows()
            ),
            onWillDismiss = { onPopupVisibilityChanged?.invoke(false) },
            placement = buildAgentMenuPlacement(this, bubble, touch)
        )
    }

    fun makeFlightSnapshot(): Pair<Bitmap, Rect>? {
        val width = bubble.width - bubble.paddingLeft - bubble.paddingRight
        if (width <= 0 || bubble.height <= 0) return null
        val bitmap = createBitmap(width, bubble.height)
        val canvas = Canvas(bitmap)
        canvas.translate(-bubble.paddingLeft.toFloat(), 0f)
        bubble.draw(canvas)
        val location = bubble.getLocationInWindow()
        val left = location.x + bubble.paddingLeft
        return bitmap to Rect(left, location.y, left + width, location.y + bubble.height)
    }

    fun setFlightSourceHidden(isHidden: Boolean) {
        bubble.alpha = if (isHidden) 0f else 1f
    }

    fun setRenderingActive(active: Boolean) {
        isRenderingEnabled = active
        updateRenderingAnimations()
    }

    private fun updateRenderingAnimations() {
        if (isRenderingEnabled && isAttachedToWindow) {
            insertAnimation?.start()
            scheduleInsertAnimation()
        } else {
            insertAnimation?.cancel()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updateRenderingAnimations()
    }

    override fun onDetachedFromWindow() {
        imageZoom.cancel()
        super.onDetachedFromWindow()
        isInsertAnimationPending = false
        finishInsertAnimation()
        setInsertAppearance(alpha = 1f, scale = 1f)
        updateLayoutParams { height = WRAP_CONTENT }
    }

    private fun setInsertAppearance(alpha: Float, scale: Float) {
        bubble.alpha = alpha
        bubble.scaleX = scale
        bubble.scaleY = scale
    }

    private fun notifyInsertAnimationStarted(targetHeight: Int) {
        val callback = onInsertAnimationStarted
        onInsertAnimationStarted = null
        callback?.invoke(targetHeight)
    }

    private fun notifyInsertAnimationFinished() {
        val callback = onInsertAnimationFinished
        onInsertAnimationFinished = null
        callback?.invoke()
    }

    private fun scheduleInsertAnimation() {
        if (!isInsertAnimationPending || !isRenderingEnabled || !isAttachedToWindow) return
        doOnPreDraw {
            if (isInsertAnimationPending && isRenderingEnabled) startInsertAnimation()
        }
    }

    private fun startInsertAnimation() {
        isInsertAnimationPending = false
        finishInsertAnimation()
        val targetHeight = measureExpandedHeight()
        insertAnimationTargetHeight = targetHeight
        notifyInsertAnimationStarted(targetHeight)
        insertAnimationOnFinished = onInsertAnimationFinished
        onInsertAnimationFinished = null
        val startHeight = (targetHeight * 0.3f).toInt().coerceAtLeast(1)
        updateLayoutParams { height = startHeight }
        insertAnimation = SpringAnimation(FloatValueHolder(startHeight.toFloat())).apply {
            setStartValue(startHeight.toFloat())
            spring = SpringForce(targetHeight.toFloat()).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                val previousHeight = height
                updateLayoutParams { height = value.toInt() }
                val appearStart = targetHeight * 0.7f
                val fraction = ((value - appearStart) / (targetHeight - appearStart))
                    .coerceIn(0f, 1f)
                setInsertAppearance(fraction, 0.8f + 0.2f * fraction)
                onSizeTransitionFrame?.invoke(previousHeight)
            }
            addEndListener { _, canceled, _, _ ->
                if (!canceled) finishInsertAnimation()
            }
            start()
        }
    }

    private fun finishInsertAnimation() {
        val animation = insertAnimation ?: return
        insertAnimation = null
        animation.cancel()
        setInsertAppearance(alpha = 1f, scale = 1f)
        updateLayoutParams { height = WRAP_CONTENT }
        insertAnimationTargetHeight = 0
        val onFinished = insertAnimationOnFinished
        insertAnimationOnFinished = null
        onFinished?.invoke()
    }

    private fun measureExpandedHeight(): Int {
        measure(
            MeasureSpec.makeMeasureSpec((parent as? View)?.width ?: width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        return measuredHeight
    }

    private class TopRoundedOutline(private val radius: Float) : ViewOutlineProvider() {
        override fun getOutline(view: View, outline: Outline) {
            outline.setRoundRect(0, 0, view.width, view.height + radius.toInt(), radius)
        }
    }

    companion object {

        // In dp: as the feed's cards, whose bubbles start 10 from the side and their bodies 16
        private const val LEADING_INSET = 10f
        private const val TRAILING_INSET = 16f
        private const val ROW_MARGIN = 6f
        private const val HORIZONTAL_PADDING = 16
        private const val HEADER_TOP = 10
        private const val HEADER_BOTTOM = 8
        private const val HEADER_ICON = 20
        private const val HEADER_ICON_GAP = 6
        private const val IMAGE_INSET = 1
        private const val IMAGE_GAP = 10
        private const val META_BOTTOM = 7
        private const val IMAGE_ASPECT_RATIO = 9f / 16f
        private const val PICTURE_CORNER_RADIUS = AGENT_BUBBLE_RADIUS - IMAGE_INSET

        /** The first source's name, its host when it has none, or the name a card stored before it kept links */
        fun sourceName(news: AgentV2ThreadNewsCard): String? {
            val first =
                news.sources?.firstOrNull() ?: return news.source?.takeIf { it.isNotBlank() }
            first.name?.takeIf { it.isNotBlank() }?.let { return it }
            val host = runCatching { URI(first.url).host }.getOrNull() ?: return null
            return host.removePrefix("www.").takeIf { it.isNotEmpty() }
        }
    }
}
