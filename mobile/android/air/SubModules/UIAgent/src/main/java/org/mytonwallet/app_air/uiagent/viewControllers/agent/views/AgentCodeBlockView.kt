package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import kotlin.math.abs
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentCodeBlockColors
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentCodeColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.setMessageMenuTapListener
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager

private const val CORNER_RADIUS = 5f
private const val BAR_WIDTH = 3
private const val HEADER_HEIGHT = 20
private const val HEADER_TEXT_SIZE = 12f
private const val COPY_ICON_SIZE = 14
private const val LEADING_PADDING = 10
private const val TRAILING_PADDING = 6
private const val VERTICAL_PADDING = 2

/**
 * A fenced code block as Telegram draws one in a message: a rounded rect in the accent's tint with the accent's bar on
 * its leading edge, and over the code a strip with the fence's language, or Copy, and a copy icon. A tap on the strip
 * copies the code, and one on the code opens the message's menu. Its lines don't wrap: the code scrolls sideways, as a
 * table does.
 */
@SuppressLint("ViewConstructor")
internal class AgentCodeBlockView(context: Context) : LinearLayout(context) {
    var onCopy: ((String) -> Unit)? = null

    private var code = ""
    private val barPaint = Paint()
    private val titleLabel = WLabel(context).apply {
        setStyle(HEADER_TEXT_SIZE, WFont.Medium)
        isSingleLine = true
        gravity = Gravity.CENTER_VERTICAL
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val copyIcon = ImageView(context).apply {
        setImageResource(R.drawable.ic_copy_30)
        scaleType = ImageView.ScaleType.FIT_CENTER
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val header = FrameLayout(context).apply {
        setPaddingRelative((BAR_WIDTH + LEADING_PADDING).dp, 0, TRAILING_PADDING.dp, 0)
        addView(titleLabel, FrameLayout.LayoutParams(WRAP_CONTENT, MATCH_PARENT, Gravity.START))
        addView(
            copyIcon,
            FrameLayout.LayoutParams(
                COPY_ICON_SIZE.dp,
                COPY_ICON_SIZE.dp,
                Gravity.END or Gravity.CENTER_VERTICAL
            )
        )
        isClickable = true
        isFocusable = true
        contentDescription = LocaleController.getString("Copy")
        accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(
                host: View,
                info: AccessibilityNodeInfo
            ) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = Button::class.java.name
            }
        }
        setOnClickListener { onCopy?.invoke(code) }
    }
    private val codeLabel = WLabel(context).apply {
        typeface = Typeface.MONOSPACE
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        ellipsize = null
        setPaddingRelative(
            (BAR_WIDTH + LEADING_PADDING).dp,
            VERTICAL_PADDING.dp,
            TRAILING_PADDING.dp,
            VERTICAL_PADDING.dp
        )
    }
    private val codeScroll = CodeScrollView(context).apply {
        isHorizontalScrollBarEnabled = false
        isFillViewport = true
        overScrollMode = OVER_SCROLL_IF_CONTENT_SCROLLS
        addView(codeLabel, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }

    init {
        orientation = VERTICAL
        clipToOutline = true
        addView(header, LayoutParams(MATCH_PARENT, HEADER_HEIGHT.dp))
        addView(codeScroll, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    /**
     * Shows [block] at the size code blocks take under a body of [bodyTextSize] pixels; a tap or a long press on the code
     * goes to [onClickListener] or [onLongClickListener], the message's own
     */
    fun configure(
        block: MarkdownParser.Block.Code,
        bodyTextSize: Float,
        onLongClickListener: OnLongClickListener,
        onClickListener: OnClickListener
    ) {
        code = block.text
        titleLabel.text = block.language ?: LocaleController.getString("Copy")
        val size = MarkdownParser.codeBlockTextSize(bodyTextSize, MarkdownParser.getSpSize())
        codeLabel.setTextSize(TypedValue.COMPLEX_UNIT_PX, size)
        codeLabel.setLineHeight(
            TypedValue.COMPLEX_UNIT_PX,
            MarkdownParser.codeBlockLineHeight(size).toFloat()
        )
        codeLabel.text = block.text
        // The scroll view takes the touch on its way down: the code under it opens the menu, as the text's labels do
        listOf(codeScroll, codeLabel).forEach {
            it.setOnLongClickListener(onLongClickListener)
            it.setMessageMenuTapListener(onClickListener)
        }
        updateTheme()
    }

    fun updateTheme() {
        val colors = AgentCodeBlockColors.make(agentCodeColor, ThemeManager.isDark)
        background = GradientDrawable().apply {
            setColor(colors.background)
            cornerRadius = CORNER_RADIUS.dp
        }
        barPaint.color = colors.bar
        header.setBackgroundColor(colors.header)
        titleLabel.setTextColor(colors.title)
        copyIcon.setColorFilter(colors.copyIcon)
        codeLabel.setTextColor(colors.code)
        invalidate()
    }

    // A code block spans the text's full width, whatever its lines' lengths
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val widthSpec = if (MeasureSpec.getMode(widthMeasureSpec) == MeasureSpec.AT_MOST) {
            MeasureSpec.makeMeasureSpec(MeasureSpec.getSize(widthMeasureSpec), MeasureSpec.EXACTLY)
        } else {
            widthMeasureSpec
        }
        super.onMeasure(widthSpec, heightMeasureSpec)
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        val barWidth = BAR_WIDTH.dp.toFloat()
        val start = if (layoutDirection == LAYOUT_DIRECTION_RTL) width - barWidth else 0f
        canvas.drawRect(start, 0f, start + barWidth, height.toFloat(), barPaint)
    }

    /** Takes a sideways drag when the code overflows, and leaves a vertical one to the chat */
    private class CodeScrollView(context: Context) : HorizontalScrollView(context) {
        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var handlesOverflowGesture = false
        private var horizontalDragStarted = false

        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x
                    downY = event.y
                    horizontalDragStarted = false
                    handlesOverflowGesture =
                        canScrollHorizontally(-1) || canScrollHorizontally(1)
                    if (handlesOverflowGesture) parent?.requestDisallowInterceptTouchEvent(true)
                }

                MotionEvent.ACTION_MOVE -> {
                    if (handlesOverflowGesture && !horizontalDragStarted) {
                        val dx = abs(event.x - downX)
                        val dy = abs(event.y - downY)
                        if (dx > touchSlop && dx >= dy) {
                            horizontalDragStarted = true
                        } else if (dy > touchSlop && dy > dx) {
                            handlesOverflowGesture = false
                            parent?.requestDisallowInterceptTouchEvent(false)
                        }
                    }
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    handlesOverflowGesture = false
                    parent?.requestDisallowInterceptTouchEvent(false)
                }
            }
            return super.dispatchTouchEvent(event)
        }
    }
}
