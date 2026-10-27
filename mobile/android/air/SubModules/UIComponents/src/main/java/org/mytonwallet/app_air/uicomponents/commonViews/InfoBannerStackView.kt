package org.mytonwallet.app_air.uicomponents.commonViews

import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sign
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.ApiPromotion

class InfoBannerStackView(context: Context) :
    FrameLayout(context),
    WThemedView,
    WProtectedView {
    private data class Card(val promotion: ApiPromotion, val view: BannerView)
    private data class Position(
        val scale: Float,
        val offset: Float,
        val alpha: Float,
        val contentOpacity: Float,
        val height: Int
    )

    private var cards: List<Card> = emptyList()
    private var departingCard: Card? = null
    private var promotions: List<ApiPromotion> = emptyList()
    private var loadingActionId: String? = null
    private var startPositions: Map<BannerView, Position> = emptyMap()
    private var spring: SpringAnimation? = null
    private var progress = 1f
    private var startHeight = 0
    private var targetHeight = 0
    private var pendingAnimation = false
    private var isAppearing = false
    private var measuredWidthForTransition = 0
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var touchCard: Card? = null
    private var downX = 0f
    private var downY = 0f
    private var dragOriginX = 0f
    private var dragCard: Card? = null
    private var swipedOutCard: Card? = null
    private var dragOffset = 0f
    private var dragSpring: SpringAnimation? = null
    private var velocityTracker: VelocityTracker? = null
    private var ignoringTouch = false
    private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK }
    private val shadowClip = Path()
    private val upperOutline = Path()
    private val upperBounds = RectF()
    private val lowerBounds = RectF()
    private val shadowBounds = RectF()
    private val shadowRadius = 6f.dp
    var descriptionFormatter: (String) -> CharSequence = { it.toProcessedSpannableStringBuilder() }
    var bottomSpacing = 0
    var onAction: ((ApiPromotion) -> Unit)? = null
    var onDismiss: ((ApiPromotion) -> Unit)? = null
    var onTransitionFinished: (() -> Unit)? = null

    val isPresenting: Boolean
        get() = cards.isNotEmpty() || departingCard != null || pendingAnimation || spring != null

    init {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false
    }

    fun configure(promotions: List<ApiPromotion>, animated: Boolean = true) {
        val banners = promotions.filter {
            it.infoBanner != null && (it.kind == "infoBanner" || it.kind == "foreignStaking")
        }
            .distinctBy { it.id }
        if (this.promotions == banners) return
        val wasDragging = dragCard != null
        cancelDrag()
        spring?.cancel()
        spring = null
        val oldCards = cards
        val oldFront = oldCards.firstOrNull()
        val wasSwipeDismissal = swipedOutCard != null && swipedOutCard === oldFront
        isAppearing = oldFront == null && banners.isNotEmpty()
        val animate =
            animated && (!wasDragging || wasSwipeDismissal) &&
                (isAppearing || (isAttachedToWindow && width > 0 && measuredHeight > 0)) &&
                animationsEnabled
        startHeight = if (isAppearing) 0 else measuredHeight
        startPositions = oldCards.associate { card ->
            card.view to
                Position(
                    card.view.scaleX,
                    card.view.translationY,
                    card.view.alpha,
                    card.view.contentOpacity,
                    card.view.height
                )
        }
        departingCard?.let { removeView(it.view) }
        departingCard = null
        this.promotions = banners
        cards = banners.take(3).map { promotion ->
            oldCards.firstOrNull { it.promotion == promotion } ?: Card(
                promotion,
                BannerView(
                    context,
                    checkNotNull(promotion.infoBanner),
                    onAction = {
                        if (cards.firstOrNull()?.promotion == promotion) onAction?.invoke(promotion)
                    },
                    onDismiss = {
                        if (cards.firstOrNull()?.promotion ==
                            promotion
                        ) {
                            onDismiss?.invoke(promotion)
                        }
                    }
                ).also { addView(it) }
            )
        }
        if (animate && !wasSwipeDismissal && oldFront != null &&
            cards.none { it.view === oldFront.view }
        ) {
            departingCard = oldFront
        }
        oldCards.filter { old -> cards.none { it.view === old.view } && old !== departingCard }
            .forEach { removeView(it.view) }
        // Preserve drawing order while the departing front card reveals the rendered card below.
        cards.asReversed().forEach { it.view.bringToFront() }
        departingCard?.view?.bringToFront()
        progress = if (animate) 0f else 1f
        alpha = if (isAppearing && animate) 0f else 1f
        pendingAnimation = animate
        cards.forEach { it.view.setActionLoading(it.promotion.id == loadingActionId) }
        setInteractionEnabled(!animate)
        updateTheme()
        requestLayout()
    }

    private fun setInteractionEnabled(enabled: Boolean) {
        cards.forEachIndexed { index, card -> card.view.setInteractive(enabled && index == 0) }
        departingCard?.view?.setInteractive(false)
    }

    fun setActionLoading(promotionId: String, loading: Boolean) {
        if (loading) {
            loadingActionId = promotionId
        } else if (loadingActionId == promotionId) {
            loadingActionId = null
        }
        cards.forEach { it.view.setActionLoading(it.promotion.id == loadingActionId) }
    }

    override fun canScrollHorizontally(direction: Int): Boolean = isPresenting

    fun containsBannerTouch(rawX: Int, rawY: Int): Boolean {
        val cardHeight = cards.firstOrNull()?.view?.height
            ?: departingCard?.view?.height
            ?: (height - bottomSpacing).coerceAtLeast(0)
        val location = IntArray(2)
        getLocationOnScreen(location)
        return rawX >= location[0] && rawX < location[0] + width &&
            rawY >= location[1] && rawY < location[1] + minOf(cardHeight, height)
    }

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                ignoringTouch = false
                downX = event.x
                downY = event.y
                if (!containsBannerTouch(event.rawX.toInt(), event.rawY.toInt())) return false
                if (spring != null || pendingAnimation || dragSpring != null) {
                    ignoringTouch = true
                    parent?.requestDisallowInterceptTouchEvent(true)
                    return true
                }
                touchCard = cards.firstOrNull()?.takeIf { event.y <= it.view.height }
                if (touchCard == null) return false
                velocityTracker?.recycle()
                velocityTracker = VelocityTracker.obtain().apply { addMovement(event) }
                parent?.requestDisallowInterceptTouchEvent(true)
            }

            MotionEvent.ACTION_MOVE -> return trackDrag(event)

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL,
            MotionEvent.ACTION_POINTER_DOWN -> clearTouch()
        }
        return false
    }

    private fun trackDrag(event: MotionEvent): Boolean {
        if (touchCard == null) return false
        val dx = event.x - downX
        val dy = event.y - downY
        if (abs(dx) > touchSlop && abs(dx) > abs(dy)) {
            dragCard = touchCard
            dragOriginX = downX + sign(dx) * touchSlop
            setInteractionEnabled(false)
            return true
        }
        velocityTracker?.addMovement(event)
        if (abs(dy) > touchSlop) clearTouch()
        return false
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (ignoringTouch) {
            when (event.actionMasked) {
                MotionEvent.ACTION_MOVE -> {
                    val dx = abs(event.x - downX)
                    val dy = abs(event.y - downY)
                    if (dy > touchSlop && dy > dx) {
                        parent?.requestDisallowInterceptTouchEvent(false)
                    }
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    ignoringTouch = false
                    clearTouch()
                }
            }
            return true
        }
        if (dragCard == null) {
            val trackingTouch = touchCard != null
            when (event.actionMasked) {
                MotionEvent.ACTION_MOVE -> trackDrag(event)

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL,
                MotionEvent.ACTION_POINTER_DOWN -> clearTouch()
            }
            if (dragCard == null) return trackingTouch || super.onTouchEvent(event)
        }
        velocityTracker?.addMovement(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_MOVE -> {
                dragOffset = event.x - dragOriginX
                requestLayout()
            }

            MotionEvent.ACTION_UP -> {
                velocityTracker?.computeCurrentVelocity(1000)
                val velocity = velocityTracker?.xVelocity ?: 0f
                val dismiss = abs(dragOffset) >= width * 0.35f ||
                    (abs(velocity) >= 600f.dp && sign(velocity) == sign(dragOffset))
                settleDrag(dismiss, velocity)
                clearTouch()
            }

            MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_POINTER_DOWN -> {
                settleDrag(false, 0f)
                clearTouch()
            }
        }
        return true
    }

    private fun clearTouch() {
        touchCard = null
        velocityTracker?.recycle()
        velocityTracker = null
        parent?.requestDisallowInterceptTouchEvent(false)
    }

    private fun cancelDrag() {
        dragSpring?.cancel()
        dragSpring = null
        dragCard = null
        dragOffset = 0f
        clearTouch()
    }

    private fun settleDrag(dismiss: Boolean, velocity: Float) {
        val card = dragCard ?: return
        val target = if (dismiss) {
            val location = IntArray(2)
            getLocationInWindow(location)
            val stackLeft = location[0]
            rootView.getLocationInWindow(location)
            val windowLeft = location[0]
            if (dragOffset > 0f) {
                windowLeft + rootView.width - stackLeft + shadowRadius
            } else {
                windowLeft - stackLeft - card.view.width - shadowRadius
            }
        } else {
            0f
        }
        fun complete() {
            dragSpring = null
            dragOffset = target
            if (dismiss && cards.firstOrNull() === card) {
                swipedOutCard = card
                try {
                    onDismiss?.invoke(card.promotion)
                } finally {
                    swipedOutCard = null
                }
            }
            cancelDrag()
            setInteractionEnabled(spring == null && !pendingAnimation)
            requestLayout()
        }
        if (!animationsEnabled) {
            complete()
            return
        }
        dragSpring = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(dragOffset)
            setStartVelocity(velocity)
            spring = SpringForce(target).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                dragOffset = value
                requestLayout()
            }
            addEndListener { _, canceled, _, _ -> if (!canceled) complete() }
            start()
        }
    }

    private fun finishTransition() {
        progress = 1f
        pendingAnimation = false
        isAppearing = false
        alpha = 1f
        departingCard?.let { removeView(it.view) }
        departingCard = null
        startPositions = emptyMap()
        setInteractionEnabled(true)
        requestLayout()
        onTransitionFinished?.invoke()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        (cards + listOfNotNull(departingCard)).forEach {
            it.view.measure(
                MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
            )
        }
        targetHeight = cards.firstOrNull()?.view?.measuredHeight?.let {
            it + bottomSpacing
        } ?: 0
        if (spring != null && measuredWidthForTransition != width) {
            spring?.cancel()
            spring = null
            finishTransition()
        }
        if (pendingAnimation && isAttachedToWindow) {
            pendingAnimation = false
            measuredWidthForTransition = width
            spring = SpringAnimation(FloatValueHolder()).apply {
                setStartValue(0f)
                setMinimumVisibleChange(0.001f)
                spring = SpringForce(1f).apply {
                    stiffness = 500f
                    dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
                }
                addUpdateListener { _, value, _ ->
                    progress = value.coerceIn(0f, 1f)
                    requestLayout()
                }
                addEndListener { _, canceled, _, _ ->
                    if (!canceled) {
                        this@InfoBannerStackView.spring = null
                        finishTransition()
                    }
                }
                start()
            }
        }
        setMeasuredDimension(
            width,
            if (dragCard != null) {
                val nextHeight = cards.getOrNull(1)?.view?.measuredHeight?.let {
                    it + bottomSpacing
                } ?: 0
                (
                    targetHeight + (
                        maxOf(
                            nextHeight,
                            targetHeight
                        ) - targetHeight
                        ) * dragProgress
                    ).roundToInt()
            } else {
                (startHeight + (targetHeight - startHeight) * progress).roundToInt()
            }
        )
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val width = right - left
        val frontHeight = cards.firstOrNull()?.view?.measuredHeight ?: 0
        alpha = if (isAppearing) ((progress - 0.7f) / 0.3f).coerceIn(0f, 1f) else 1f
        if (dragCard != null) {
            layoutDrag(width, frontHeight)
            return
        }
        cards.forEachIndexed { index, card ->
            val targetScale = (1f - index * 48f.dp / width.coerceAtLeast(1)).coerceAtLeast(0f)
            val targetOffset = index * 6f.dp
            val targetAlpha = if (index < 2) 1f else 0f
            val start =
                startPositions[card.view]
                    ?: Position(targetScale, targetOffset, 0f, 0f, frontHeight)
            card.view.scaleX = start.scale + (targetScale - start.scale) * progress
            card.view.translationX = 0f
            card.view.translationY = start.offset + (targetOffset - start.offset) * progress
            card.view.alpha = start.alpha + (targetAlpha - start.alpha) * progress
            if (isAppearing) card.view.alpha = targetAlpha
            val targetContentOpacity = if (index == 0) 1f else 0f
            card.view.contentOpacity =
                if (isAppearing) {
                    targetContentOpacity
                } else {
                    start.contentOpacity + (targetContentOpacity - start.contentOpacity) * progress
                }
            val height = (start.height + (frontHeight - start.height) * progress).roundToInt()
            card.view.layout(0, 0, width, height)
        }
        departingCard?.view?.let {
            val start = startPositions[it] ?: return@let
            it.alpha = start.alpha * (1f - progress)
            it.translationY = start.offset - 12f.dp * progress
            it.layout(0, 0, width, start.height)
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updateProtectedView()
        if (pendingAnimation) requestLayout()
    }

    override fun onDetachedFromWindow() {
        ignoringTouch = false
        cancelDrag()
        spring?.cancel()
        spring = null
        finishTransition()
        super.onDetachedFromWindow()
    }

    private val dragProgress: Float
        get() = (abs(dragOffset) / width.coerceAtLeast(1)).coerceIn(0f, 1f)

    private fun layoutDrag(width: Int, frontHeight: Int) {
        val fraction = dragProgress
        val nextHeight = cards.getOrNull(1)?.view?.measuredHeight ?: 0
        cards.forEachIndexed { index, card ->
            if (index == 0) {
                card.view.translationX = dragOffset
                card.view.alpha = 1f
                card.view.contentOpacity = 1f
                card.view.layout(0, 0, width, frontHeight)
            } else {
                val position = index - fraction
                card.view.translationX = 0f
                card.view.scaleX =
                    (1f - position * 48f.dp / width.coerceAtLeast(1)).coerceAtLeast(0f)
                card.view.translationY = position * 6f.dp
                card.view.alpha = if (index == 1) 1f else fraction
                card.view.contentOpacity = if (index == 1) fraction else 0f
                val height = (frontHeight + (nextHeight - frontHeight) * fraction).roundToInt()
                card.view.layout(0, 0, width, height)
            }
        }
    }

    override fun updateTheme() {
        cards.forEach { it.view.updateTheme() }
        departingCard?.view?.updateTheme()
    }

    override fun updateProtectedView() {
        cards.forEach { it.view.updateText() }
        departingCard?.view?.updateText()
    }

    override fun dispatchDraw(canvas: Canvas) {
        val saved = canvas.save()
        canvas.clipRect(-width, 0, width * 2, height)
        super.dispatchDraw(canvas)
        canvas.restoreToCount(saved)
    }

    override fun drawChild(canvas: Canvas, child: View, drawingTime: Long): Boolean {
        val index = cards.indexOfFirst { it.view === child }
        val below = if (departingCard?.view === child) {
            cards.firstOrNull()?.view
        } else {
            cards.getOrNull(index + 1)?.view?.takeIf { index >= 0 }
        }
        if (below != null && child.alpha > 0f && below.alpha > 0f) {
            drawStackShadow(canvas, child, below)
        }
        return super.drawChild(canvas, child, drawingTime)
    }

    private fun drawStackShadow(canvas: Canvas, upper: View, lower: View) {
        fun bounds(view: View, rect: RectF) {
            val inset = view.width * (1f - view.scaleX) / 2
            rect.set(
                view.left + view.translationX + inset,
                view.top + view.translationY,
                view.right + view.translationX - inset,
                view.bottom + view.translationY
            )
        }
        bounds(upper, upperBounds)
        bounds(lower, lowerBounds)
        shadowClip.reset()
        shadowClip.addRoundRect(lowerBounds, 26f.dp * lower.scaleX, 26f.dp, Path.Direction.CW)
        upperOutline.reset()
        upperOutline.addRoundRect(upperBounds, 26f.dp * upper.scaleX, 26f.dp, Path.Direction.CW)
        shadowClip.op(upperOutline, Path.Op.DIFFERENCE)
        val saved = canvas.save()
        canvas.clipPath(shadowClip)
        for (step in 8 downTo 0) {
            val spread = shadowRadius * step / 8
            shadowBounds.set(upperBounds)
            shadowBounds.inset(-spread, -spread)
            shadowBounds.offset(0f, 2f.dp)
            shadowPaint.alpha = ((1.75f - step * 0.14f) * upper.alpha * lower.alpha).roundToInt()
            canvas.drawRoundRect(
                shadowBounds,
                26f.dp * upper.scaleX + spread,
                26f.dp + spread,
                shadowPaint
            )
        }
        canvas.restoreToCount(saved)
    }

    private val animationsEnabled: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() && ValueAnimator.areAnimatorsEnabled()

    private fun cardBackground() = GradientDrawable().apply {
        cornerRadius = 26f.dp
        setColor(WColor.Background.color)
    }

    private inner class BannerView(
        context: Context,
        private val banner: ApiPromotion.InfoBanner,
        onAction: () -> Unit,
        onDismiss: () -> Unit
    ) : FrameLayout(context),
        WThemedView {
        private var isInteractive = false
        private var isActionLoading = false
        private val actionClickListener = OnClickListener {
            if (isEnabled && !isActionLoading) onAction()
        }
        private val titleLabel = WLabel(context).apply {
            setStyle(16f, WFont.Medium)
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        private val descriptionLabel = WLabel(context).apply {
            setStyle(13f)
            setLineHeight(18f)
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val actionButton = object : WLabel(context) {
            private val progressDrawable = RoundProgressDrawable(16f, 2f)

            init {
                progressDrawable.callback = this
            }

            override fun verifyDrawable(who: Drawable): Boolean =
                who === progressDrawable || super.verifyDrawable(who)

            override fun onDraw(canvas: Canvas) {
                if (!isActionLoading) {
                    super.onDraw(canvas)
                    return
                }
                val size = 16.dp
                val left = (width - size) / 2
                val top = (height - size) / 2
                progressDrawable.color = WColor.Tint.color
                progressDrawable.setBounds(left, top, left + size, top + size)
                progressDrawable.draw(canvas)
            }

            override fun getAccessibilityClassName(): CharSequence = "android.widget.Button"
        }.apply {
            setStyle(14f, WFont.Medium)
            gravity = Gravity.CENTER
            setPadding(12.dp, 0, 12.dp, 0)
            minimumHeight = 30.dp
            isFocusable = true
            setOnClickListener(actionClickListener)
        }
        val closeButton = WImageButton(context).apply {
            setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_qr_close_12)
            scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(18.dp, 18.dp, 18.dp, 18.dp)
            contentDescription = LocaleController.getString("Close")
            setOnClickListener { onDismiss() }
        }
        private var verticalBody = false
        var contentOpacity = 1f
            set(value) {
                field = value
                titleLabel.alpha = value
                descriptionLabel.alpha = value
                actionButton.alpha = value
                closeButton.alpha = value
            }

        init {
            id = generateViewId()
            minimumHeight = 90.dp
            clipToOutline = true
            isFocusable = true
            setOnClickListener(actionClickListener)
            layoutParams = LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            addView(titleLabel)
            addView(descriptionLabel)
            addView(actionButton)
            addView(closeButton)
            updateTheme()
        }

        fun setInteractive(interactive: Boolean) {
            isInteractive = interactive
            isEnabled = interactive && !isActionLoading
            closeButton.isEnabled = interactive
            actionButton.isEnabled = isEnabled
            importantForAccessibility = if (interactive) {
                IMPORTANT_FOR_ACCESSIBILITY_YES
            } else {
                IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            }
        }

        fun setActionLoading(loading: Boolean) {
            isActionLoading = loading
            isEnabled = isInteractive && !loading
            actionButton.isEnabled = isEnabled
            actionButton.invalidate()
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val width = MeasureSpec.getSize(widthMeasureSpec)
            val bodyWidth = (width - 32.dp).coerceAtLeast(0)
            val unspecified = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
            titleLabel.measure(
                MeasureSpec.makeMeasureSpec(
                    (bodyWidth - 32.dp).coerceAtLeast(0),
                    MeasureSpec.EXACTLY
                ),
                unspecified
            )
            actionButton.measure(
                MeasureSpec.makeMeasureSpec(bodyWidth, MeasureSpec.AT_MOST),
                unspecified
            )
            // Same rule as iOS: the description keeps most of the row, so a wide button moves below it.
            verticalBody = resources.configuration.fontScale >= 1.3f ||
                actionButton.measuredWidth > bodyWidth * 0.4f
            val descriptionWidth = if (verticalBody) {
                bodyWidth
            } else {
                bodyWidth -
                    actionButton.measuredWidth -
                    10.dp
            }
            descriptionLabel.measure(
                MeasureSpec.makeMeasureSpec(descriptionWidth.coerceAtLeast(0), MeasureSpec.EXACTLY),
                unspecified
            )
            closeButton.measure(
                MeasureSpec.makeMeasureSpec(48.dp, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(48.dp, MeasureSpec.EXACTLY)
            )
            val bodyHeight = if (verticalBody) {
                descriptionLabel.measuredHeight + 8.dp +
                    actionButton.measuredHeight
            } else {
                maxOf(descriptionLabel.measuredHeight + 8.dp, actionButton.measuredHeight)
            }
            setMeasuredDimension(
                width,
                maxOf(minimumHeight, 14.dp + titleLabel.measuredHeight + 4.dp + bodyHeight + 6.dp)
            )
        }

        override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
            val width = right - left
            val rtl = layoutDirection == LAYOUT_DIRECTION_RTL
            fun place(child: View, start: Int, y: Int) {
                val x = if (rtl) width - start - child.measuredWidth else start
                child.layout(x, y, x + child.measuredWidth, y + child.measuredHeight)
            }
            place(titleLabel, 16.dp, 13.dp)
            place(closeButton, width - 48.dp, 1.dp)
            val bodyTop = 18.dp + titleLabel.measuredHeight
            val bodyBottom = measuredHeight - 6.dp
            place(descriptionLabel, 16.dp, bodyTop - 1.dp)
            place(
                actionButton,
                width - 14.dp - actionButton.measuredWidth,
                bodyBottom - actionButton.measuredHeight - 7.dp
            )
        }

        override fun updateTheme() {
            val cardBackground = cardBackground()
            background = RippleDrawable(
                ColorStateList.valueOf(WColor.TintRipple.color),
                cardBackground,
                cardBackground.constantState?.newDrawable()
            )
            titleLabel.setTextColor(WColor.PrimaryText.color)
            descriptionLabel.setTextColor(WColor.SecondaryText.color)
            updateText()
            actionButton.setTextColor(WColor.Tint.color)
            val buttonBackground = GradientDrawable().apply {
                cornerRadius = 100f.dp
                setColor((WColor.Tint.color and 0x00FFFFFF) or 0x1A000000)
            }
            actionButton.background = RippleDrawable(
                ColorStateList.valueOf(WColor.TintRipple.color),
                buttonBackground,
                buttonBackground.constantState?.newDrawable()
            )
            closeButton.updateColors(WColor.SecondaryText)
        }

        fun updateText() {
            val isSensitiveDataHidden = WGlobalStorage.getIsSensitiveDataProtectionOn()
            val textValues = banner.textValues.map { (key, value) ->
                key to if (isSensitiveDataHidden && key == "%amount%") "***" else value
            }
            titleLabel.text = LocaleController.getStringWithKeyValues(banner.title, textValues)
            descriptionLabel.text = descriptionFormatter(
                LocaleController.getStringWithKeyValues(banner.description, textValues)
            )
            actionButton.text =
                LocaleController.getStringWithKeyValues(banner.actionButton.title, textValues)
            contentDescription = "${titleLabel.text}. ${descriptionLabel.text}"
        }
    }
}
