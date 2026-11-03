package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.graphics.Path
import android.graphics.RectF
import android.text.Spanned
import android.text.TextPaint
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.view.children
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.atMost
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.IPopup
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.cancelAncestorTouches
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopupViewItem
import org.mytonwallet.app_air.uicomponents.widgets.menu.WPopupHost
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.Vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/** The selected link expands into its full address above a separate action menu */
internal class AgentLinkMenu private constructor(
    private val source: TextView,
    private val url: String,
    private val span: WClickableSpan,
    private val sourceBounds: RectF,
    private val host: WPopupHost,
    private val bubbleColor: () -> Int,
    private val isStillShown: () -> Boolean,
    private val onVisibilityChanged: (Boolean) -> Unit
) : IPopup {
    private val sourceWasEnabled = source.isEnabled
    private var progress = 0f
    private var animator: ValueAnimator? = null
    private var isClosing = false
    private var isFinished = false
    private var previewStartScale = 1f
    private var previewStartX = 0f
    private var previewStartY = 0f
    private val dim = View(source.context)
    private val previewText = TextView(source.context).apply {
        id = View.generateViewId()
        text = url
        setTextSize(TypedValue.COMPLEX_UNIT_PX, source.textSize)
        typeface = source.typeface
        letterSpacing = source.letterSpacing
        includeFontPadding = source.includeFontPadding
        setLineSpacing(source.lineSpacingExtra, source.lineSpacingMultiplier)
        textDirection = View.TEXT_DIRECTION_LTR
        setPadding(8.dp, 5.dp, 8.dp, 5.dp)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
    }
    private val preview = ScrollView(source.context).apply {
        id = View.generateViewId()
        isVerticalScrollBarEnabled = false
        isClickable = true
        elevation = 2f.dp
        addView(previewText, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }
    private val menu = LinearLayout(source.context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
        minimumWidth = 196.dp
        setPadding(0, 4.dp, 0, 4.dp)
        elevation = 2f.dp
    }
    private val overlay = object : WFrameLayout(source.context), WThemedView {
        override fun updateTheme() {
            dim.setBackgroundColor(WColor.PopupWindow.color)
            preview.setBackgroundColor(bubbleColor(), 5f.dp, clipToBounds = true)
            menu.setBackgroundColor(WColor.Background.color, 12f.dp, clipToBounds = true)
            val paint = TextPaint(source.paint).also(span::updateDrawState)
            previewText.setTextColor(paint.color)
            previewText.paint.isUnderlineText = paint.isUnderlineText
            menu.children.filterIsInstance<WThemedView>().forEach { it.updateTheme() }
        }
    }.apply {
        clipChildren = false
        addView(dim, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(preview, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(menu, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setOnClickListener { dismiss() }
    }
    private val detachListener = object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(view: View) = Unit
        override fun onViewDetachedFromWindow(view: View) = finish()
    }
    private val preDrawListener = ViewTreeObserver.OnPreDrawListener {
        if (!isStillShown() || ((source.text as? Spanned)?.getSpanStart(span) ?: -1) < 0) finish()
        true
    }

    private fun show(items: List<WMenuPopup.Item>) {
        val actionPaint = TextPaint().apply {
            textSize = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP,
                adaptiveFontSize(),
                source.resources.displayMetrics
            )
            typeface = WFont.Regular.typeface
        }
        menu.minimumWidth = max(
            menu.minimumWidth,
            items.maxOf {
                ceil(actionPaint.measureText(it.getTitle()?.toString().orEmpty())).toInt() +
                    74.dp
            }
        )
        items.forEach { item ->
            menu.addView(
                WMenuPopupViewItem(source.context, item).apply {
                    setOnClickListener {
                        if (isClosing || isFinished || !isStillShown()) return@setOnClickListener
                        dismiss()
                        item.onTap?.invoke()
                    }
                },
                LinearLayout.LayoutParams(WRAP_CONTENT, 48.dp)
            )
        }
        source.cancelAncestorTouches()
        source.isEnabled = false
        source.addOnAttachStateChangeListener(detachListener)
        overlay.addOnAttachStateChangeListener(detachListener)
        host.addView(overlay, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        overlay.updateTheme()
        overlay.viewTreeObserver.addOnPreDrawListener(preDrawListener)
        PopupHelpers.popupShown(this)
        onVisibilityChanged(true)
        setProgress(0f)
        overlay.post {
            if (isFinished || isClosing) return@post
            place()
            if (!isFinished) animateTo(1f)
        }
    }

    private fun place() {
        val origin = overlay.getLocationInWindow()
        val area = getAgentPopupArea().apply { offset(-origin.x, -origin.y) }
        if (area.isEmpty) {
            finish()
            return
        }
        val bounds = RectF(sourceBounds).apply { offset(-origin.x.toFloat(), -origin.y.toFloat()) }
        val availableWidth = area.width().coerceAtLeast(1)
        val menuWidth = menu.minimumWidth.coerceAtMost(availableWidth)
        menu.children.forEach { it.layoutParams.width = MATCH_PARENT }
        menu.measure(menuWidth.exactly, 0.unspecified)
        val menuHeight = menu.measuredHeight
        if (area.height() <= menuHeight + 8.dp) {
            finish()
            return
        }
        val textWidth = (source.width - source.totalPaddingLeft - source.totalPaddingRight)
            .coerceAtLeast(1)
        val maxPreviewWidth = (textWidth + 16.dp).coerceAtMost(availableWidth)
        previewText.measure(maxPreviewWidth.atMost, 0.unspecified)
        val previewWidth = previewText.measuredWidth.coerceAtLeast(1)
        val previewHeight = previewText.measuredHeight.coerceAtMost(
            (area.height() - menuHeight - 8.dp).coerceAtLeast(1)
        )
        val previewX = (bounds.left - 8.dp).coerceIn(
            area.left.toFloat(),
            (area.right - previewWidth).toFloat()
        )
        var previewY = (bounds.top - 5.dp).coerceIn(
            area.top.toFloat(),
            (area.bottom - previewHeight).toFloat()
        )
        var menuY = previewY + previewHeight + 8.dp
        if (menuY + menuHeight > area.bottom) {
            previewY = max(previewY, (area.top + menuHeight + 8.dp).toFloat())
            menuY = previewY - menuHeight - 8.dp
        }
        val menuX = (previewX + previewWidth - menuWidth)
            .coerceIn(area.left.toFloat(), (area.right - menuWidth).toFloat())
        preview.layoutParams = FrameLayout.LayoutParams(previewWidth, previewHeight).apply {
            leftMargin = previewX.roundToInt()
            topMargin = previewY.roundToInt()
        }
        menu.layoutParams = FrameLayout.LayoutParams(menuWidth, menuHeight).apply {
            leftMargin = menuX.roundToInt()
            topMargin = menuY.roundToInt()
        }
        menu.pivotX = (bounds.centerX() - menuX).coerceIn(0f, menuWidth.toFloat())
        menu.pivotY = if (menuY > previewY) 0f else menuHeight.toFloat()
        preview.pivotX = 8f.dp
        preview.pivotY = 5f.dp
        previewStartX = bounds.left - previewX - 8.dp
        previewStartY = bounds.top - previewY - 5.dp
        val scaleX = bounds.width() / (previewWidth - 16.dp).coerceAtLeast(1)
        val scaleY = bounds.height() / (previewHeight - 10.dp).coerceAtLeast(1)
        previewStartScale =
            (min(scaleX, scaleY) * 0.25f + max(scaleX, scaleY) * 0.75f).coerceIn(0.2f, 1f)
        setProgress(progress)
    }

    private fun setProgress(value: Float) {
        progress = value
        dim.alpha = value
        menu.alpha = value
        menu.scaleX = 0.8f + 0.2f * value
        menu.scaleY = menu.scaleX
        preview.alpha = value
        preview.scaleX = previewStartScale + (1f - previewStartScale) * value
        preview.scaleY = preview.scaleX
        preview.translationX = previewStartX * (1f - value)
        preview.translationY = previewStartY * (1f - value)
    }

    private fun animateTo(target: Float) {
        val running = animator
        animator = null
        running?.cancel()
        if (target == progress || !WGlobalStorage.getAreAnimationsActive() ||
            !ValueAnimator.areAnimatorsEnabled()
        ) {
            setProgress(target)
            if (target == 0f) finish()
            return
        }
        val animation = ValueAnimator.ofFloat(progress, target).apply {
            duration = 350
            interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
            addUpdateListener { setProgress(it.animatedValue as Float) }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    if (animator !== animation) return
                    animator = null
                    if (target == 0f) finish()
                }
            })
        }
        animator = animation
        animation.start()
    }

    override fun onBackPressed() = dismiss()

    override fun dismiss() {
        if (isClosing || isFinished) return
        isClosing = true
        animateTo(0f)
    }

    private fun finish() {
        if (isFinished) return
        isFinished = true
        val running = animator
        animator = null
        running?.cancel()
        source.removeOnAttachStateChangeListener(detachListener)
        overlay.removeOnAttachStateChangeListener(detachListener)
        if (overlay.viewTreeObserver.isAlive) {
            overlay.viewTreeObserver.removeOnPreDrawListener(
                preDrawListener
            )
        }
        (overlay.parent as? ViewGroup)?.removeView(overlay)
        source.isEnabled = sourceWasEnabled
        PopupHelpers.popupDismissed(this)
        onVisibilityChanged(false)
    }

    companion object {
        fun present(
            source: TextView,
            url: String,
            touch: Vec2i?,
            items: List<WMenuPopup.Item>,
            bubbleColor: () -> Int,
            isStillShown: () -> Boolean,
            onVisibilityChanged: (Boolean) -> Unit
        ) {
            if (!source.isAttachedToWindow || !source.isShown || !isStillShown()) return
            val host = PopupHelpers.popupHost ?: return
            val text = source.text as? Spanned ?: return
            val layout = source.layout ?: return
            val origin = source.getLocationInWindow()
            val links = text.getSpans(0, text.length, WClickableSpan::class.java)
                .filter { it.url == url }
                .map { span ->
                    val path = Path()
                    layout.getSelectionPath(text.getSpanStart(span), text.getSpanEnd(span), path)
                    val bounds = RectF().also { path.computeBounds(it, true) }.apply {
                        offset(
                            (origin.x + source.totalPaddingLeft - source.scrollX).toFloat(),
                            (origin.y + source.totalPaddingTop - source.scrollY).toFloat()
                        )
                    }
                    span to bounds
                }
                .filterNot { (_, bounds) -> bounds.isEmpty }
            val (span, bounds) = links.firstOrNull { (_, bounds) ->
                touch != null && bounds.contains(touch.x.toFloat(), touch.y.toFloat())
            } ?: links.firstOrNull() ?: return
            AgentLinkMenu(
                source,
                url,
                span,
                bounds,
                host,
                bubbleColor,
                isStillShown,
                onVisibilityChanged
            ).show(items)
        }
    }
}
