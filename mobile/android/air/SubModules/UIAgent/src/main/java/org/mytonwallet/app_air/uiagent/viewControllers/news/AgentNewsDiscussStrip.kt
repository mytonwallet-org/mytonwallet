package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.isGone
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentMarkDrawable
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadAvatarView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem

@SuppressLint("ViewConstructor")
internal class AgentNewsDiscussStrip(context: Context) :
    LinearLayout(context),
    WThemedView {
    private val separator = View(context).apply { id = generateViewId() }
    private val button = WView(context).apply {
        minimumHeight = MIN_HEIGHT.dp
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        isFocusable = true
        isClickable = true
    }
    private val content = WView(context).apply {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
    }
    private val icon = FrameLayout(context).apply { id = generateViewId() }
    private val markDrawable = AgentMarkDrawable(WColor.Tint.color)
    private val markView = ImageView(context).apply {
        id = generateViewId()
        setImageDrawable(markDrawable)
        scaleType = ImageView.ScaleType.FIT_CENTER
    }
    private val avatarView = AgentThreadAvatarView(context, ICON.dp)
    private val label = WLabel(context).apply {
        setStyle(TEXT_SIZE, WFont.Regular)
        isSingleLine = false
        maxLines = Int.MAX_VALUE
    }
    private val chevron = ImageView(context).apply {
        id = generateViewId()
        setImageResource(R.drawable.ic_menu_arrow_right)
        scaleType = ImageView.ScaleType.CENTER
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    var onClick: (() -> Unit)? = null

    init {
        id = generateViewId()
        orientation = VERTICAL
        addView(separator, LayoutParams(MATCH_PARENT, 1))
        icon.addView(
            markView,
            FrameLayout.LayoutParams(MARK.dp.roundToInt(), MARK.dp.roundToInt(), Gravity.CENTER)
        )
        icon.addView(avatarView, FrameLayout.LayoutParams(ICON.dp, ICON.dp))
        content.addView(icon, ConstraintLayout.LayoutParams(ICON.dp, ICON.dp))
        content.addView(label, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        content.addView(chevron, ConstraintLayout.LayoutParams(CHEVRON_BOX.dp, CHEVRON_BOX.dp))
        content.setConstraints {
            toStart(icon, ICON_START.toFloat())
            toCenterY(icon)
            startToEnd(label, icon, LABEL_GAP.toFloat())
            endToStart(label, chevron, 1f)
            toTop(label)
            toBottom(label)
            toEnd(chevron, CHEVRON_END.toFloat())
            toCenterY(chevron)
        }
        button.addView(content, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        button.setConstraints {
            toStart(content)
            toEnd(content)
            toTop(content, VERTICAL_INSET.toFloat())
            toBottom(content, (VERTICAL_INSET + RAISE).toFloat())
        }
        addView(button, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        button.setOnClickListener { onClick?.invoke() }
        button.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    content.animate().cancel()
                    content.alpha = PRESSED_ALPHA
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                    content.animate().alpha(1f).setDuration(PRESS_RELEASE_MS).start()
            }
            false
        }
        updateTheme()
    }

    fun configure(item: AgentV2NewsFeedItem, isDiscussionStarted: Boolean) {
        val discussion = item.discussion?.takeIf { isDiscussionStarted }
        if (discussion == null) {
            configureDiscuss(item.headline)
            return
        }
        configure(
            LocaleController.getString("\$agent_news_continue_discussion"),
            LocaleController.getString("\$agent_news_continue_discussion_accessibility")
                .replace("%headline%", item.headline),
            discussion
        )
    }

    /** Discuss what [subject] names, with the Agent's mark: a news item's headline, or a digest's title */
    fun configureDiscuss(subject: String) = configure(
        LocaleController.getString("\$agent_news_discuss"),
        "${LocaleController.getString("\$agent_news_discuss")}, $subject",
        discussion = null
    )

    // A discussion the user has written in shows its thread's avatar, the same as in the thread list
    private fun configure(
        title: String,
        contentDescription: String,
        discussion: AgentV2NewsFeedItem.Discussion?
    ) {
        label.text = title
        button.contentDescription = contentDescription
        markView.isGone = discussion != null
        avatarView.isGone = discussion == null
        discussion?.let { avatarView.configure(it.threadId, it.icon?.takeIf(String::isNotBlank)) }
    }

    override fun updateTheme() {
        separator.setBackgroundColor(WColor.Separator.color)
        label.setTextColor(WColor.Tint)
        chevron.setColorFilter(WColor.Tint.color)
        markView.setColorFilter(WColor.Tint.color)
    }

    private companion object {
        const val MIN_HEIGHT = 46
        const val VERTICAL_INSET = 7
        const val RAISE = 2
        const val ICON = 30
        const val MARK = 23.4f
        const val ICON_START = 13
        const val LABEL_GAP = 11
        const val TEXT_SIZE = 17f
        const val CHEVRON_BOX = 24
        const val CHEVRON_END = 9
        const val PRESSED_ALPHA = 0.4f
        const val PRESS_RELEASE_MS = 200L
    }
}
