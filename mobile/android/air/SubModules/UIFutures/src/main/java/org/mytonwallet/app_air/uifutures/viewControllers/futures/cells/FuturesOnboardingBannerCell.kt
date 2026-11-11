package org.mytonwallet.app_air.uifutures.viewControllers.futures.cells

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.graphics.drawable.RippleDrawable
import android.util.TypedValue
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.ViewCompat
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import org.mytonwallet.app_air.icons.R as IconsR
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.stories.StoriesPresentationSource
import org.mytonwallet.app_air.uifutures.R
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
class FuturesOnboardingBannerCell(
    context: Context,
    private val onOpen: (StoriesPresentationSource) -> Unit,
    private val onDismiss: () -> Unit
) : WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)) {

    private val cardView = BannerCardView(context)

    init {
        addView(cardView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            allEdges(cardView)
        }
        cardView.button.setOnClickListener { open() }
        cardView.closeButton.setOnClickListener { onDismiss() }
        cardView.onTap = ::open
    }

    fun configure() {
        setCardPadding(ViewConstants.GAP.dp)
    }

    private fun open() {
        onOpen(
            StoriesPresentationSource(
                cardView,
                cardView.button,
                buttonTitle = LocaleController.getString("PerpsOnboardingOpen"),
                buttonColor = BUTTON_COLOR,
                buttonTextColor = BUTTON_TEXT_COLOR,
                buttonTextSize = TypedValue.applyDimension(
                    TypedValue.COMPLEX_UNIT_SP,
                    BUTTON_TEXT_SIZE,
                    resources.displayMetrics
                ),
                cornerRadius = cardView.cornerRadius,
                prepareForPresentation = cardView::resetPress,
                isValid = { cardView.isAttachedToWindow }
            )
        )
    }

    private companion object {
        val BUTTON_COLOR = Color.WHITE
        val BUTTON_TEXT_COLOR = Color.rgb(11, 31, 68)
        const val BUTTON_TEXT_SIZE = 16f
    }

    private class BannerCardView(context: Context) : FrameLayout(context) {
        var onTap: (() -> Unit)? = null
        var cornerRadius = PHONE_RADIUS.dp.toFloat()
            private set
        private var isWide: Boolean? = null

        private val gradientPaint = Paint()
        private var gradientHeight = 0

        private val artworkView = FadingImageView(context).apply {
            scaleType = ImageView.ScaleType.FIT_XY
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        private val illustrationView = AppCompatImageView(context).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageResource(R.drawable.futures_onboarding_illustration)
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        private val titleLabel = WLabel(context).apply {
            setTextColor(Color.WHITE)
            ViewCompat.setAccessibilityHeading(this, true)
        }
        private val descriptionLabel = WLabel(context).apply {
            setStyle(14f, WFont.Medium)
            setLineHeight(20f)
            setTextColor(Color.WHITE)
        }
        val button = WButton(context, WButton.Type.PRIMARY).apply {
            customTint = BUTTON_COLOR
            customTextColor = BUTTON_TEXT_COLOR
            setText(LocaleController.getString("PerpsOnboardingOpen"), false)
        }
        val closeButton = AppCompatImageView(context).apply {
            setImageResource(IconsR.drawable.ic_close)
            imageTintList = ColorStateList.valueOf(Color.WHITE)
            scaleType = ImageView.ScaleType.FIT_CENTER
            background = InsetDrawable(
                GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.argb((0.18f * 255).toInt(), 255, 255, 255))
                },
                (CLOSE_TOUCH_SIZE - CLOSE_BACKGROUND_SIZE).dp / 2
            )
            foreground = RippleDrawable(
                ColorStateList.valueOf(Color.argb(0x33, 255, 255, 255)),
                null,
                InsetDrawable(
                    GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(Color.WHITE)
                    },
                    (CLOSE_TOUCH_SIZE - CLOSE_BACKGROUND_SIZE).dp / 2
                )
            )
            // The background's inset would replace earlier padding
            val inset = (CLOSE_TOUCH_SIZE - CLOSE_ICON_SIZE).dp / 2
            setPadding(inset, inset, inset, inset)
            contentDescription = LocaleController.getString("Close")
            isClickable = true
        }

        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var isTracking = false
        private var isPressed = false
        private val pressRunnable = Runnable { setPressedScale(true) }

        init {
            id = generateViewId()
            setWillNotDraw(false)
            clipToOutline = true
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, 0, view.width, view.height, cornerRadius)
                }
            }
            for (child in listOf(
                artworkView,
                illustrationView,
                titleLabel,
                descriptionLabel,
                button,
                closeButton
            )) {
                addView(child, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            }
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        private fun configureLayout(wide: Boolean) {
            if (isWide == wide) return
            isWide = wide
            cornerRadius = (if (wide) WIDE_RADIUS else PHONE_RADIUS).dp.toFloat()
            invalidateOutline()
            titleLabel.setStyle(26f, WFont.Bold)
            titleLabel.setLineHeight(32f)
            val title = LocaleController.getStringWithKeyValues(
                "PerpsOnboardingTitle",
                listOf("%app_name%" to context.getString(BaseR.string.app_locale_name_key))
            )
            val description = LocaleController.getString("PerpsOnboardingDescription")
            titleLabel.text = if (wide) title.replace("\n", " ") else title
            descriptionLabel.text = if (wide) description.replace("\n", " ") else description
            artworkView.setImageResource(
                if (wide) {
                    R.drawable.futures_onboarding_artwork_wide
                } else {
                    R.drawable.futures_onboarding_artwork
                }
            )
            button.buttonHeight = (if (wide) 40 else 50).dp
        }

        private fun textWidth(width: Int): Int = if (width >= WIDE_WIDTH.dp) {
            min(300.dp, width - 303.dp)
        } else {
            min(160.dp, max(1, width - 210.dp))
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val width = MeasureSpec.getSize(widthMeasureSpec)
            val wide = width >= WIDE_WIDTH.dp
            configureLayout(wide)
            val textWidth = textWidth(width)
            val textSpec = MeasureSpec.makeMeasureSpec(textWidth, MeasureSpec.EXACTLY)
            val unspecified = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
            titleLabel.measure(textSpec, unspecified)
            descriptionLabel.measure(textSpec, unspecified)
            val textHeight =
                titleLabel.measuredHeight + (if (wide) 3 else 7).dp +
                    descriptionLabel.measuredHeight
            val height = if (wide) {
                max(140.dp, 36.dp + textHeight + 12.dp + 40.dp)
            } else {
                max(
                    width * PHONE_ASPECT_HEIGHT / PHONE_ASPECT_WIDTH,
                    43.dp + textHeight + 16.dp + 50.dp + 24.dp
                )
            }
            val buttonWidth = if (wide) {
                min(
                    textWidth,
                    button.measureText(LocaleController.getString("PerpsOnboardingOpen")).toInt() +
                        48.dp
                )
            } else {
                width - 48.dp
            }
            button.measure(exactly(buttonWidth), exactly(button.buttonHeight))
            val imageWidth = (if (wide) 230 else 196).dp
            val imageHeight = (if (wide) 134 else 114).dp
            illustrationView.measure(exactly(imageWidth), exactly(imageHeight))
            artworkView.measure(exactly((if (wide) 603 else 370).dp), exactly(height))
            closeButton.measure(exactly(CLOSE_TOUCH_SIZE.dp), exactly(CLOSE_TOUCH_SIZE.dp))
            setMeasuredDimension(width, height)
        }

        override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
            val width = right - left
            val height = bottom - top
            val wide = width >= WIDE_WIDTH.dp
            val isRTL = layoutDirection == LAYOUT_DIRECTION_RTL
            val textWidth = textWidth(width)
            val gap = (if (wide) 3 else 7).dp
            val textHeight = titleLabel.measuredHeight + gap + descriptionLabel.measuredHeight
            val textX = if (isRTL) width - 24.dp - textWidth else 24.dp
            val textY = if (wide) (height - textHeight - 52.dp) / 2 else 43.dp
            titleLabel.place(textX, textY)
            descriptionLabel.place(textX, titleLabel.bottom + gap)
            val imageInset = (if (wide) 43 else 12).dp
            illustrationView.place(
                if (isRTL) imageInset else width - imageInset - illustrationView.measuredWidth,
                if (wide) (height - illustrationView.measuredHeight) / 2 else 46.dp
            )
            button.place(
                if (isRTL) width - 24.dp - button.measuredWidth else 24.dp,
                if (wide) descriptionLabel.bottom + 12.dp else height - 74.dp
            )
            val closeOffset = (CLOSE_MARGIN - (CLOSE_TOUCH_SIZE - CLOSE_BACKGROUND_SIZE) / 2).dp
            closeButton.place(
                if (isRTL) closeOffset else width - closeOffset - CLOSE_TOUCH_SIZE.dp,
                closeOffset
            )
            val artworkWidth = artworkView.measuredWidth
            artworkView.place(if (isRTL) 0 else width - artworkWidth, 0)
            artworkView.fadeWidth = if (width > artworkWidth) ARTWORK_FADE.dp else 0
            artworkView.isFadeRTL = isRTL
            if (gradientHeight != height) {
                gradientHeight = height
                gradientPaint.shader = LinearGradient(
                    0f,
                    0f,
                    0f,
                    height.toFloat(),
                    intArrayOf(
                        Color.rgb(45, 189, 255),
                        Color.rgb(21, 144, 255),
                        Color.rgb(10, 108, 240)
                    ),
                    floatArrayOf(0f, 0.55f, 1f),
                    Shader.TileMode.CLAMP
                )
            }
        }

        override fun onDraw(canvas: Canvas) {
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), gradientPaint)
        }

        override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
            trackPress(event)
            return false
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            trackPress(event)
            return true
        }

        private fun trackPress(event: MotionEvent) {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    isTracking = !button.contains(event) && !closeButton.contains(event)
                    if (!isTracking) return
                    downX = event.x
                    downY = event.y
                    postDelayed(pressRunnable, PRESS_DELAY)
                }

                MotionEvent.ACTION_MOVE -> {
                    if (isTracking && (
                            hypot(event.x - downX, event.y - downY) >
                                max(touchSlop, PRESS_MOVEMENT.dp) ||
                                event.x < 0 || event.y < 0 || event.x > width || event.y > height
                            )
                    ) {
                        cancelTracking()
                    }
                }

                MotionEvent.ACTION_UP -> {
                    if (!isTracking) return
                    cancelTracking()
                    onTap?.invoke()
                }

                MotionEvent.ACTION_CANCEL -> cancelTracking()
            }
        }

        private fun cancelTracking() {
            isTracking = false
            removeCallbacks(pressRunnable)
            if (isPressed) setPressedScale(false)
        }

        fun resetPress() {
            cancelTracking()
            animate().cancel()
            scaleX = 1f
            scaleY = 1f
        }

        private fun setPressedScale(pressed: Boolean) {
            isPressed = pressed
            val scale = if (pressed && WGlobalStorage.getAreAnimationsActive()) {
                max(PRESS_MINIMUM_SCALE, (width - PRESS_SCALE_INSET.dp) / max(1f, width.toFloat()))
            } else {
                1f
            }
            animate().cancel()
            if (!WGlobalStorage.getAreAnimationsActive()) {
                scaleX = scale
                scaleY = scale
                return
            }
            animate().scaleX(scale).scaleY(scale).setDuration(PRESS_DURATION).start()
        }

        private fun View.contains(event: MotionEvent) =
            event.x >= left && event.x < right && event.y >= top && event.y < bottom

        private fun View.place(x: Int, y: Int) {
            layout(x, y, x + measuredWidth, y + measuredHeight)
        }

        private fun exactly(size: Int) = MeasureSpec.makeMeasureSpec(size, MeasureSpec.EXACTLY)

        private companion object {
            const val WIDE_WIDTH = 560
            const val PHONE_RADIUS = 26
            const val WIDE_RADIUS = 24
            const val PHONE_ASPECT_WIDTH = 392
            const val PHONE_ASPECT_HEIGHT = 272
            const val CLOSE_TOUCH_SIZE = 44
            const val CLOSE_BACKGROUND_SIZE = 28

            // `ic_close` draws its X in 14 of 24 units
            const val CLOSE_ICON_SIZE = 18
            const val CLOSE_MARGIN = 12
            const val ARTWORK_FADE = 40
            const val PRESS_DELAY = 120L
            const val PRESS_DURATION = 200L
            const val PRESS_MOVEMENT = 10
            const val PRESS_SCALE_INSET = 15
            const val PRESS_MINIMUM_SCALE = 0.7f
        }
    }

    private class FadingImageView(context: Context) : AppCompatImageView(context) {
        var fadeWidth = 0
            set(value) {
                if (field == value) return
                field = value
                shader = null
                invalidate()
            }
        var isFadeRTL = false
            set(value) {
                if (field == value) return
                field = value
                shader = null
                invalidate()
            }
        private var shader: LinearGradient? = null
        private val maskPaint = Paint().apply {
            xfermode =
                PorterDuffXfermode(PorterDuff.Mode.DST_IN)
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            shader = null
        }

        override fun onDraw(canvas: Canvas) {
            if (fadeWidth <= 0 || width == 0) {
                super.onDraw(canvas)
                return
            }
            val layer = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
            super.onDraw(canvas)
            val mask = shader ?: run {
                val start = if (isFadeRTL) width.toFloat() else 0f
                val end = if (isFadeRTL) width - fadeWidth.toFloat() else fadeWidth.toFloat()
                LinearGradient(
                    start,
                    0f,
                    end,
                    0f,
                    Color.TRANSPARENT,
                    Color.WHITE,
                    Shader.TileMode.CLAMP
                )
            }.also { shader = it }
            maskPaint.shader = mask
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), maskPaint)
            canvas.restoreToCount(layer)
        }
    }
}
