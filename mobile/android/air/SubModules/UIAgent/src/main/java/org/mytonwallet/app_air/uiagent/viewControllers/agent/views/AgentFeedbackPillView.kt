package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import org.mytonwallet.app_air.uiagent.R
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentAnswerFeedback
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

private const val BODY_HEIGHT_DP = 56

// The design's 40 dp thumbs at 12 and 56 in the 108 dp body
private const val BODY_PADDING_DP = 10
private const val BUTTON_WIDTH_DP = 44

// The tail: a bump that grows out of the middle of the pill, and a dot below it towards the answer's start
private const val BUMP_SIZE_DP = 16
private const val BUMP_OVERLAP_DP = 10
private const val DOT_SIZE_DP = 8
private const val DOT_GAP_DP = 10
private const val DOT_OFFSET_DP = 9
private const val ELEVATION_DP = 2f

/**
 * The like and dislike buttons shown above an answer while its menu is open, with a thought-bubble tail that points
 * at the answer below. [onSelect] gets the new rating: null when the chosen one is pressed again.
 */
@SuppressLint("ViewConstructor")
class AgentFeedbackPillView(
    context: Context,
    private val feedback: AgentAnswerFeedback?,
    pointsLeft: Boolean,
    private val onSelect: (AgentAnswerFeedback?) -> Unit
) : FrameLayout(context),
    WThemedView {

    val bodyHeight = BODY_HEIGHT_DP.dp
    private val bumpSize = BUMP_SIZE_DP.dp
    private val dotSize = DOT_SIZE_DP.dp
    private val body = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        setPadding(BODY_PADDING_DP.dp, 0, BODY_PADDING_DP.dp, 0)
        elevation = ELEVATION_DP.dp
    }
    private val bump = View(context).apply { elevation = ELEVATION_DP.dp }
    private val dot = View(context).apply { elevation = ELEVATION_DP.dp }
    private val buttons = AgentAnswerFeedback.entries.map { option -> createButton(option) }

    /** The pill without its tail, which the answer's menu places relative to the answer */
    val bodyWidth = (BODY_PADDING_DP * 2 + BUTTON_WIDTH_DP * buttons.size).dp

    /** How far below the pill's top its tail's dot ends */
    val tailBottom = bodyHeight + (DOT_GAP_DP + DOT_SIZE_DP).dp

    init {
        clipChildren = false
        clipToPadding = false
        layoutDirection = LAYOUT_DIRECTION_LTR
        buttons.forEach {
            body.addView(it, LinearLayout.LayoutParams(BUTTON_WIDTH_DP.dp, bodyHeight))
        }
        val dotCenter = bodyWidth / 2 + (if (pointsLeft) -DOT_OFFSET_DP else DOT_OFFSET_DP).dp
        addView(
            dot,
            LayoutParams(dotSize, dotSize, Gravity.TOP or Gravity.LEFT).apply {
                leftMargin = dotCenter - dotSize / 2
                topMargin = bodyHeight + DOT_GAP_DP.dp
            }
        )
        // The body covers the bump's top, so the bump reads as part of the pill
        addView(
            bump,
            LayoutParams(bumpSize, bumpSize, Gravity.TOP or Gravity.LEFT).apply {
                leftMargin = bodyWidth / 2 - bumpSize / 2
                topMargin = bodyHeight - BUMP_OVERLAP_DP.dp
            }
        )
        addView(body, LayoutParams(bodyWidth, bodyHeight, Gravity.TOP or Gravity.LEFT))
        pivotX = bodyWidth / 2f
        pivotY = bodyHeight.toFloat()
        updateTheme()
    }

    /** Follows the menu: 0 while hidden, 1 once it is fully shown */
    fun setDisplayProgress(progress: Float) {
        alpha = progress
        val scale = 0.6f + 0.4f * progress
        scaleX = scale
        scaleY = scale
    }

    override fun updateTheme() {
        val background = WColor.Background.color
        body.setBackgroundColor(background, bodyHeight / 2f, true)
        bump.setBackgroundColor(background, bumpSize / 2f, true)
        dot.setBackgroundColor(background, dotSize / 2f, true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            listOf(body, bump, dot).forEach {
                it.outlineAmbientShadowColor = WColor.PopupAmbientShadow.color
                it.outlineSpotShadowColor = WColor.PopupSpotShadow.color
            }
        }
        // Both thumbs are outlines; the chosen one takes the accent color
        AgentAnswerFeedback.entries.zip(buttons).forEach { (option, button) ->
            val isSelected = option == feedback
            button.setColorFilter(if (isSelected) WColor.Tint.color else WColor.PrimaryText.color)
            button.background = WRippleDrawable.create(bodyHeight / 2f).apply {
                rippleColor = WColor.BackgroundRipple.color
            }
        }
    }

    private fun createButton(option: AgentAnswerFeedback): ImageView {
        val isSelected = option == feedback
        return ImageView(context).apply {
            scaleType = ImageView.ScaleType.CENTER
            setImageResource(
                when (option) {
                    AgentAnswerFeedback.LIKE -> R.drawable.ic_agent_thumb_up_outline
                    AgentAnswerFeedback.DISLIKE -> R.drawable.ic_agent_thumb_down_outline
                }
            )
            contentDescription = LocaleController.getString(
                when (option) {
                    AgentAnswerFeedback.LIKE -> "Like"
                    AgentAnswerFeedback.DISLIKE -> "Dislike"
                }
            )
            this.isSelected = isSelected
            setOnClickListener {
                Haptics.play(context, HapticType.LIGHT_TAP)
                onSelect(if (isSelected) null else option)
            }
        }
    }
}
