package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AGENT_OPERATOR_INITIAL_COLOR
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentSupportBadgeColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentSupportBadgeTextColor
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2OperatorAuthor

// In dp
private const val AVATAR_SIZE = 28
private const val AUTHOR_BOTTOM_GAP = 6

/** The author row's height with the gap under it, in dp */
internal const val AGENT_MESSAGE_AUTHOR_HEIGHT = AVATAR_SIZE + AUTHOR_BOTTOM_GAP
private const val MARK_SIZE = 16
private const val NAME_GAP = 8
private const val BADGE_RADIUS = 6f
private const val BADGE_HORIZONTAL_PADDING = 7
private const val BADGE_VERTICAL_PADDING = 1

/**
 * The author over an answer once an operator has joined the chat: the operator's photo, name and support badge, or the
 * agent's mark and name, so that the user tells the two apart
 */
@SuppressLint("ViewConstructor")
internal class AgentMessageAuthorView(context: Context) : LinearLayout(context) {
    private val avatarBackground = GradientDrawable().apply { shape = GradientDrawable.OVAL }
    private val initialLabel = WLabel(context).apply {
        setStyle(13f, WFont.Bold)
        gravity = Gravity.CENTER
        isSingleLine = true
        setTextColor(WHITE)
    }
    private val agentMark = ImageView(context).apply {
        setImageDrawable(AgentMarkDrawable(WHITE))
    }

    // Without a photo that loads, the operator's initial shows
    private var failedAvatarUrl: String? = null
    private var avatarUrl: String? = null
    private val photo = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Round
        onFailure = {
            failedAvatarUrl = avatarUrl
            isVisible = false
        }
    }
    private val avatar = FrameLayout(context).apply {
        background = avatarBackground
        addView(initialLabel, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(agentMark, FrameLayout.LayoutParams(MARK_SIZE.dp, MARK_SIZE.dp, Gravity.CENTER))
        addView(photo, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }
    private val nameLabel = WLabel(context).apply {
        setStyle(14f, WFont.Bold)
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END
    }
    private val badgeLabel = WLabel(context).apply {
        setStyle(12f, WFont.Bold)
        isSingleLine = true
        setPadding(
            BADGE_HORIZONTAL_PADDING.dp,
            BADGE_VERTICAL_PADDING.dp,
            BADGE_HORIZONTAL_PADDING.dp,
            BADGE_VERTICAL_PADDING.dp
        )
    }
    private var operator: AgentV2OperatorAuthor? = null

    init {
        id = generateViewId()
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(0, 0, 0, AUTHOR_BOTTOM_GAP.dp)
        avatar.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        addView(avatar, LayoutParams(AVATAR_SIZE.dp, AVATAR_SIZE.dp))
        addView(
            nameLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT, 1f).apply { marginStart = NAME_GAP.dp }
        )
        addView(
            badgeLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginStart = NAME_GAP.dp }
        )
    }

    /** Names the [operator] who wrote the answer; without one, the answer is the agent's */
    fun configure(operator: AgentV2OperatorAuthor?) {
        this.operator = operator
        val avatarUrl = operator?.avatarUrl?.takeIf { it.isNotBlank() }
        this.avatarUrl = avatarUrl
        initialLabel.isVisible = operator != null
        agentMark.isVisible = operator == null
        badgeLabel.isVisible = operator != null
        if (operator == null) {
            nameLabel.text = LocaleController.getString("Agent")
        } else {
            nameLabel.text = operator.name
            initialLabel.text = getInitial(operator.name)
            badgeLabel.text = LocaleController.getStringWithKeyValues(
                "\$agent_support_badge",
                listOf("%app_name%" to context.getString(BaseR.string.app_locale_name_key))
            )
        }
        if (avatarUrl == null) {
            photo.clear()
            photo.isVisible = false
        } else if (avatarUrl == failedAvatarUrl) {
            photo.isVisible = false
        } else {
            photo.isVisible = true
            photo.set(
                Content(
                    Content.Image.Url(avatarUrl),
                    rounding = Content.Rounding.Round,
                    placeholder = Content.Placeholder.Color(WColor.Transparent),
                    decodeSize = AVATAR_SIZE.dp
                )
            )
        }
        updateTheme()
    }

    fun updateTheme() {
        avatarBackground.setColor(
            if (operator == null) WColor.Tint.color else AGENT_OPERATOR_INITIAL_COLOR
        )
        nameLabel.setTextColor(WColor.PrimaryText.color)
        badgeLabel.setTextColor(agentSupportBadgeTextColor)
        badgeLabel.setBackgroundColor(agentSupportBadgeColor, BADGE_RADIUS.dp)
    }

    private companion object {
        const val WHITE = 0xFFFFFFFF.toInt()

        fun getInitial(name: String): String {
            val trimmed = name.trim()
            if (trimmed.isEmpty()) return ""
            val end = trimmed.offsetByCodePoints(0, 1)
            return trimmed.substring(0, end).uppercase()
        }
    }
}
