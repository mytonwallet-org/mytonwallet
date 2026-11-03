package org.mytonwallet.app_air.uibrowser.viewControllers.search.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.Drawable
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.appcompat.content.res.AppCompatResources
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.isGone
import org.mytonwallet.app_air.uiagent.search.AgentThreadSearchResult
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class SearchRecentChatCell(
    context: Context,
    private val onTap: (AgentThreadSearchResult) -> Unit,
    private val onStart: () -> Unit
) : WCell(context, LayoutParams(MATCH_PARENT, 60.dp)),
    WThemedView {

    private val iconDrawable: Drawable? = AppCompatResources.getDrawable(
        context,
        org.mytonwallet.app_air.icons.R.drawable.ic_agent_search
    )

    private val iconView = AppCompatImageView(context).apply {
        id = generateViewId()
        setImageDrawable(iconDrawable)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val emojiLabel = WLabel(context).apply {
        useCustomEmoji = true
        setStyle(18f)
        gravity = Gravity.CENTER
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(adaptiveFontSize(), WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        setTextColor(WColor.PrimaryText)
    }

    private val subtitleLabel = WLabel(context).apply {
        setStyle(12f, WFont.Regular)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        setTextColor(WColor.SecondaryText)
    }

    private val textContainer = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_VERTICAL
        addView(titleLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(subtitleLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    private val ripple = WRippleDrawable.create(0f)
    private val lastItemRipple = WRippleDrawable.create(
        0f,
        0f,
        ViewConstants.BLOCK_RADIUS.dp,
        ViewConstants.BLOCK_RADIUS.dp
    )
    private var hint: AgentThreadSearchResult? = null
    private var isStartRow = false
    private var isLastItem = false

    override fun setupViews() {
        super.setupViews()
        addView(iconView, LayoutParams(24.dp, 24.dp))
        addView(emojiLabel, LayoutParams(24.dp, 24.dp))
        addView(textContainer, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(iconView, 18f)
            toCenterY(iconView)
            toStart(emojiLabel, 18f)
            toCenterY(emojiLabel)
            setHorizontalBias(textContainer.id, 0f)
            toStart(textContainer, 56f)
            toEnd(textContainer, 12f)
            toCenterY(textContainer)
        }
        setOnClickListener {
            if (isStartRow) onStart() else hint?.let(onTap)
        }
        updateTheme()
    }

    fun configure(hint: AgentThreadSearchResult, isLastItem: Boolean) {
        this.hint = hint
        isStartRow = false
        this.isLastItem = isLastItem
        val emoji = hint.icon?.takeIf { it.isNotBlank() }
        emojiLabel.text = emoji
        emojiLabel.isGone = emoji == null
        iconView.isGone = emoji != null
        titleLabel.text = hint.title
        subtitleLabel.text = hint.subtitle
        subtitleLabel.isGone = hint.subtitle.isEmpty()
        updateTheme()
    }

    fun configureStart(isLastItem: Boolean) {
        hint = null
        isStartRow = true
        this.isLastItem = isLastItem
        emojiLabel.text = null
        emojiLabel.isGone = true
        iconView.isGone = false
        titleLabel.text = LocaleController.getString("Ask Agent")
        subtitleLabel.text = LocaleController.getString("\$universal_search_start_conversation")
        subtitleLabel.isGone = false
        updateTheme()
    }

    override fun updateTheme() {
        iconDrawable?.setTint(WColor.PrimaryText.color)
        val currentRipple = if (isLastItem) lastItemRipple else ripple
        background = currentRipple
        currentRipple.backgroundColor = WColor.Transparent.color
        currentRipple.rippleColor = WColor.SecondaryBackground.color
    }
}
