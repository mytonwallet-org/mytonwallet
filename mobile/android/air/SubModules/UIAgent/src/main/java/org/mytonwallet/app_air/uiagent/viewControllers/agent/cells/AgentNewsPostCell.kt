package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
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
import java.util.Date
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsFlightSource
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsPostContent
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentIncomingBubbleColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.makeAgentBubbleFlightSnapshot
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_BUBBLE_RADIUS
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_BUBBLE_TAIL_WIDTH
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBubbleDrawable
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentTailMorph
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentImagePinchZoom
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsDigestPictures
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsDiscussStrip
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsIconView
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsTextBlock
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.extensions.dp
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
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline

/** A WRecyclerView takes multi-finger touches from its rows, so the list must leave this pinch to the row. */
internal fun isAgentPicturePinchStart(list: RecyclerView, event: MotionEvent): Boolean {
    if (event.actionMasked != MotionEvent.ACTION_POINTER_DOWN || event.pointerCount != 2) {
        return false
    }
    val row = list.findChildViewUnder(event.getX(0), event.getY(0)) as? AgentNewsPostCell
    return row?.canStartPictureZoom(list, event) == true
}

/** A news or digest post in a chat, or a News feed card ([Style.FEED_CARD]). */
@SuppressLint("ViewConstructor")
internal class AgentNewsPostCell(
    context: Context,
    textCache: AgentMessageTextCache,
    style: Style = Style.DISCUSSION_POST
) : WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView,
    AgentNewsFlightSource {
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
        isSingleLine = false
        maxLines = Int.MAX_VALUE
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
        } else {
            // The post shows its picture as soon as it has it, as on iOS, so a card flying in from the feed never
            // crosses a picture that fades in from its placeholder
            hierarchy.fadeDuration = 0
        }
    }
    private val imageSpacer = View(context).apply { id = generateViewId() }
    private val textBlock = AgentNewsTextBlock(context).apply {
        setVerticalPadding(top = 0, bottom = META_BOTTOM.dp)
        this.textCache = textCache
    }
    private var postId: String? = null
    private var postDate: Date? = null
    private var post: AgentNewsPostContent? = null
    private var imageUrl: String? = null

    // The colour the picture's placeholder was set with
    private var picturePlaceholderColor: Int? = null
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

    /** A tap on a digest's headline, which opens its news item's discussion */
    var onDigestHeadlineClick: ((AgentV2NewsDigestHeadline) -> Unit)? = null
    private var digestHeadlineActions = emptyList<Int>()
    private var digestPictureActions = emptyList<Int>()

    /** A tap on a digest's headline picture, which opens the digest's pictures in the media viewer */
    var onDigestPictureClick: ((AgentNewsDigestPictures) -> Unit)?
        get() = textBlock.digestHeadlines.onPictureClick
        set(value) {
            textBlock.digestHeadlines.onPictureClick = value
        }
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
        // A tap or a long press opens the post's menu, as in Telegram; the picture keeps its own
        bubble.setOnLongClickListener {
            requestMenu(menuTouch.take(bubble))
            true
        }
        textBlock.digestHeadlines.onHeadlineClick = { onDigestHeadlineClick?.invoke(it) }
        textBlock.digestHeadlines.onPicturesChanged = ::updateDigestPictureActions
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
        post: AgentNewsPostContent,
        recyclerWidth: Int,
        animate: Boolean = false,
        hasFollowupsBelow: Boolean = false
    ) {
        val previousHeight = height
        val isSameMessage = postId == id
        tailMorph.update(bubbleDrawable, hasTail = !hasFollowupsBelow, canAnimate = isSameMessage)
        val availableWidth = recyclerWidth.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels
        val nextBubbleWidth = (availableWidth - (LEADING_INSET + TRAILING_INSET).dp.roundToInt())
            .coerceAtLeast(1)
        val imageWidth = nextBubbleWidth - (AGENT_BUBBLE_TAIL_WIDTH + 2 * IMAGE_INSET).dp
        val imageHeight = (imageWidth * IMAGE_ASPECT_RATIO).roundToInt().coerceAtLeast(0)
        val preservesHeight = isSameMessage &&
            (this.post != post || bubbleWidth != nextBubbleWidth)
        if (!isSameMessage) {
            finishInsertAnimation()
            insertAnimationTargetHeight = 0
        }
        postId = id
        postDate = date
        this.post = post
        bubbleWidth = nextBubbleWidth
        imageContainer.updateLayoutParams { height = imageHeight }
        val publishedDate = parseAgentV2Timestamp(post.publishedAt)
        // A feed's post shows only its time, under its day's capsule
        val timeText = publishedDate?.let {
            if (isFeedCard) {
                formatAgentChatTime(context, it)
            } else {
                AgentNewsTextBlock.formatPostTime(context, it)
            }
        }.orEmpty()
        // A digest's post is headed by News too
        header.text = LocaleController.getString("News")
        textBlock.configure(id, post.headline, post.body, timeText)
        textBlock.configureDigest(post.digestHeadlines, post.digestRemainder)
        bubble.contentDescription =
            listOf(
                header.text.toString().takeUnless { isFeedCard },
                post.headline,
                textBlock.bodyText.toString(),
                post.digestHeadlines.joinToString(", ") { it.headline },
                post.digestRemainder,
                timeText
            )
                .filter { !it.isNullOrEmpty() }
                .joinToString(", ")
        updateOpenSourceAction()
        updateDigestHeadlineActions(post.digestHeadlines)
        val nextImageUrl = post.imageUrl?.takeIf { it.isNotBlank() }
        // The same picture binds without loading again, so a post rebound under the card flying in keeps it
        if (nextImageUrl != imageUrl) {
            imageFailed = false
            imageAspectRatio = null
            imageZoom.cancel()
            if (nextImageUrl == null) {
                image.clear()
            } else {
                image.set(
                    Content(
                        Content.Image.Url(nextImageUrl),
                        rounding = Content.Rounding.Radius(0f),
                        placeholder = Content.Placeholder.Color(PICTURE_PLACEHOLDER)
                    )
                )
            }
            picturePlaceholderColor = PICTURE_PLACEHOLDER.color
        }
        imageUrl = nextImageUrl
        setImageHidden(nextImageUrl == null || imageFailed)
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

    fun makeDigestPictureSource(headline: AgentV2NewsDigestHeadline): MediaViewerVC.Source? =
        textBlock.digestHeadlines.makePictureSource(headline, menuRows())

    override fun updateTheme() {
        bubbleDrawable.setBubbleColor(agentIncomingBubbleColor)
        header.setTextColor(WColor.Tint)
        image.setBackgroundColor(agentIncomingBubbleColor)
        icon.updateTheme()
        updatePicturePlaceholder()
        textBlock.updateTheme()
    }

    // Setting the placeholder's colour loads the picture again, so only a theme that changed it sets it
    private fun updatePicturePlaceholder() {
        val color = PICTURE_PLACEHOLDER.color
        if (color == picturePlaceholderColor) return
        picturePlaceholderColor = color
        image.updateTheme()
    }

    private fun setImageHidden(isHidden: Boolean) {
        imageContainer.isGone = isHidden
        imageSpacer.isGone = isHidden
        if (isFeedCard) {
            textBlock.setVerticalPadding(
                top = if (isHidden) HEADER_TOP.dp else 0,
                bottom = META_BOTTOM.dp
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

    // TalkBack reads a digest's headlines as the bubble's text, so each opens from an action of the bubble
    private fun updateDigestHeadlineActions(headlines: List<AgentV2NewsDigestHeadline>) {
        digestHeadlineActions.forEach { ViewCompat.removeAccessibilityAction(bubble, it) }
        digestHeadlineActions = headlines.map { headline ->
            ViewCompat.addAccessibilityAction(bubble, headline.headline) { _, _ ->
                onDigestHeadlineClick?.invoke(headline)
                true
            }
        }
        updateDigestPictureActions()
    }

    // Each picture that shows opens from an action of the bubble too, as its headline does
    private fun updateDigestPictureActions() {
        digestPictureActions.forEach { ViewCompat.removeAccessibilityAction(bubble, it) }
        digestPictureActions = textBlock.digestHeadlines.buildPictureActions().map { action ->
            ViewCompat.addAccessibilityAction(bubble, action.label) { _, _ ->
                action.open()
                true
            }
        }
    }

    private fun sourceUrl(): String? = post?.let(::agentNewsSourceUrl)

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

    private val tailMorph = AgentTailMorph(this)

    /** Suggestions came to hang from the post, or went */
    fun setHasFollowupsBelow(hasFollowupsBelow: Boolean) =
        tailMorph.update(bubbleDrawable, hasTail = !hasFollowupsBelow, canAnimate = true)

    /** Opens the post's menu from the finger at [touch], a window point, as Telegram does; null opens it at the post */
    private fun showMenu(touch: Vec2i?) {
        val post = post ?: return
        val actions = listOf(buildAgentMessageMenuHeader(context, postDate ?: Date())) +
            buildAgentNewsMenuItems(this, post, onOpenSource, onCopied)
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

    override fun makeFlightSnapshot(): Pair<Bitmap, Rect>? = makeAgentBubbleFlightSnapshot(bubble)

    override fun setFlightSourceHidden(isHidden: Boolean) {
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
        private val PICTURE_PLACEHOLDER = WColor.BackgroundRipple
    }
}
