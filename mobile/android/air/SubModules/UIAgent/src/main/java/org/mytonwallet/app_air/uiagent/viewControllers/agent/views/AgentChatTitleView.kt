package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Rect
import android.graphics.drawable.BitmapDrawable
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.core.animation.doOnEnd
import androidx.core.view.ViewCompat
import androidx.core.view.isGone
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uiagent.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * A chat's title in its header: the thread's emoji, then its title, centered and cut short at the end, and under it the
 * line that tells that support has the chat, with its headset
 */
internal class AgentChatTitleView(context: Context) :
    FrameLayout(context),
    WThemedView {
    private val iconLabel = WLabel(context).apply {
        setStyle(EMOJI_SIZE, WFont.Medium)
        setSingleLine()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val textLabel = WLabel(context).apply {
        setStyle(TITLE_SIZE, WFont.Medium)
        setLineHeight(TITLE_LINE_HEIGHT)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val subtitleIcon = ImageView(context).apply {
        setImageResource(R.drawable.ic_agent_support)
    }
    private val subtitleLabel = WLabel(context).apply {
        setStyle(SUBTITLE_SIZE, WFont.Medium)
        setLineHeight(SUBTITLE_LINE_HEIGHT)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }
    private val subtitleRow = LinearLayout(context).apply {
        id = generateViewId()
        gravity = Gravity.CENTER_VERTICAL
        isVisible = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        addView(
            subtitleIcon,
            LinearLayout.LayoutParams(SUBTITLE_ICON_SIZE.dp, SUBTITLE_ICON_SIZE.dp).apply {
                marginEnd = SUBTITLE_ICON_GAP.dp
            }
        )
        addView(subtitleLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }
    private var currentTitle: String? = null
    private var currentSubtitle: String? = null
    private var currentIcon: String? = null
    private var hasDrawnTitle = false
    private var renameAnimator: ValueAnimator? = null

    init {
        id = generateViewId()
        minimumHeight = 44.dp
        setPadding(0, TITLE_PADDING.dp, 0, TITLE_PADDING.dp)
        clipChildren = true
        clipToPadding = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        ViewCompat.setAccessibilityHeading(this, true)
        addView(
            LinearLayout(context).apply {
                id = generateViewId()
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                clipChildren = false
                addView(
                    LinearLayout(context).apply {
                        id = generateViewId()
                        gravity = Gravity.CENTER_VERTICAL
                        clipChildren = false
                        addView(
                            iconLabel,
                            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                                marginEnd = EMOJI_GAP.dp
                            }
                        )
                        addView(
                            textLabel,
                            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
                        )
                    },
                    LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
                )
                addView(subtitleRow, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            },
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER)
        )
        updateTheme()
    }

    override fun updateTheme() {
        textLabel.setTextColor(WColor.PrimaryText.color)
        iconLabel.setTextColor(WColor.PrimaryText.color)
        subtitleIcon.setColorFilter(WColor.Tint.color)
        subtitleLabel.setTextColor(WColor.Tint.color)
    }

    /** Shows the line under the title, or hides it with null */
    fun setSubtitle(subtitle: String?) {
        if (currentSubtitle == subtitle) return
        currentSubtitle = subtitle
        subtitleLabel.text = subtitle
        subtitleRow.isVisible = subtitle != null
        // The title and its line fit the bar's height together
        val verticalPadding = if (subtitle == null) TITLE_PADDING else SUBTITLE_TITLE_PADDING
        setPadding(0, verticalPadding.dp, 0, verticalPadding.dp)
        updateDescription()
    }

    private fun updateDescription() {
        val title = currentTitle ?: return
        contentDescription = listOfNotNull(
            if (currentIcon == null) title else "$currentIcon $title",
            currentSubtitle
        ).joinToString(", ")
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        hasDrawnTitle = true
    }

    fun setTitle(title: String, icon: String?) {
        if (currentTitle == title && currentIcon == icon) return
        val iconChanged = currentIcon != icon
        val shouldAnimate = currentTitle != null && hasDrawnTitle && isShown &&
            isLaidOut && width > 0 && height > 0 && WGlobalStorage.getAreAnimationsActive() &&
            Settings.Global.getFloat(
                context.contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f
            ) > 0f
        // Capture the visible composition, including any interrupted transition, before cancelling it.
        val bitmap = if (shouldAnimate) captureTitle(keepIcon = !iconChanged) else null
        cancelAnimation()
        currentTitle = title
        currentIcon = icon
        textLabel.text = title
        iconLabel.text = icon
        iconLabel.isGone = icon == null
        updateDescription()
        if (bitmap == null) return

        val snapshot = BitmapDrawable(resources, bitmap).apply {
            bounds = Rect(0, 0, bitmap.width, bitmap.height)
        }
        overlay.add(snapshot)
        val distance = 7.dp.toFloat()
        textLabel.alpha = 0f
        textLabel.translationY = distance
        if (iconChanged && icon != null) {
            iconLabel.alpha = 0f
            iconLabel.scaleX = 0.6f
            iconLabel.scaleY = 0.6f
        }
        val outgoing = AccelerateInterpolator()
        val incoming = DecelerateInterpolator()
        val overshoot = OvershootInterpolator(1.5f)
        val animation = ValueAnimator.ofFloat(0f, 270f).apply {
            duration = 270L
            interpolator = LinearInterpolator()
            addUpdateListener {
                val elapsed = it.animatedValue as Float
                val oldProgress = outgoing.getInterpolation((elapsed / 150f).coerceIn(0f, 1f))
                val offset = (-distance * oldProgress).toInt()
                // A longer title changes the layout width. Preserve the outgoing glyphs' size.
                val left = (width - bitmap.width) / 2
                snapshot.setBounds(left, offset, left + bitmap.width, bitmap.height + offset)
                snapshot.alpha = ((1f - oldProgress) * 255).toInt()
                val progress = incoming.getInterpolation(
                    ((elapsed - 30f) / 220f).coerceIn(0f, 1f)
                )
                textLabel.alpha = progress
                textLabel.translationY = distance * (1f - progress)
                if (iconChanged && icon != null) {
                    val iconProgress = ((elapsed - 100f) / 170f).coerceIn(0f, 1f)
                    val scale = 0.6f + 0.4f * overshoot.getInterpolation(iconProgress)
                    iconLabel.scaleX = scale
                    iconLabel.scaleY = scale
                    iconLabel.alpha = incoming.getInterpolation(iconProgress)
                }
            }
        }
        renameAnimator = animation
        animation.doOnEnd {
            overlay.remove(snapshot)
            if (renameAnimator === animation) {
                renameAnimator = null
                resetPresentation()
            }
        }
        animation.start()
    }

    private fun captureTitle(keepIcon: Boolean): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        if (keepIcon && !iconLabel.isGone) {
            val iconBounds = Rect(0, 0, iconLabel.width, iconLabel.height)
            offsetDescendantRectToMyCoords(iconLabel, iconBounds)
            val clip = Path().apply {
                fillType = Path.FillType.EVEN_ODD
                addRect(0f, 0f, width.toFloat(), height.toFloat(), Path.Direction.CW)
                addRect(
                    iconBounds.left.toFloat(),
                    0f,
                    iconBounds.right.toFloat(),
                    height.toFloat(),
                    Path.Direction.CW
                )
            }
            canvas.clipPath(clip)
        }
        // The line under the title stays in place as the title changes
        subtitleRow.alpha = 0f
        draw(canvas)
        subtitleRow.alpha = 1f
        return bitmap
    }

    fun cancelAnimation() {
        renameAnimator?.cancel()
        resetPresentation()
    }

    private fun resetPresentation() {
        textLabel.alpha = 1f
        textLabel.translationY = 0f
        iconLabel.alpha = 1f
        iconLabel.scaleX = 1f
        iconLabel.scaleY = 1f
    }

    override fun onDetachedFromWindow() {
        cancelAnimation()
        super.onDetachedFromWindow()
    }

    private companion object {
        const val TITLE_SIZE = 20f
        const val TITLE_LINE_HEIGHT = 28f
        const val TITLE_PADDING = 8
        const val SUBTITLE_TITLE_PADDING = 0
        const val SUBTITLE_SIZE = 13f
        const val SUBTITLE_LINE_HEIGHT = 16f
        const val SUBTITLE_ICON_SIZE = 12
        const val SUBTITLE_ICON_GAP = 4

        // Draws the design's 24 dp emoji
        const val EMOJI_SIZE = 23f
        const val EMOJI_GAP = 8
    }
}
