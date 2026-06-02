package org.mytonwallet.app_air.uisettings.viewControllers.mfa

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import org.mytonwallet.app_air.uicomponents.commonViews.TelegramAvatarView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.models.AccountMfa

@SuppressLint("ViewConstructor")
class MfaLinkedAccountView(context: Context) : WView(context), WThemedView {

    companion object {
        private const val AVATAR_SIZE = 40
    }

    private val avatarSlot = FrameLayout(context).apply {
        id = generateViewId()
    }

    private val imageAvatar = WCustomImageView(context).apply {
        id = generateViewId()
        defaultRounding = Content.Rounding.Round
        defaultPlaceholder = Content.Placeholder.Color(WColor.Transparent)
    }
    private var initialsAvatar: TelegramAvatarView? = null

    private val nameLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(adaptiveFontSize(), WFont.Medium)
    }

    private val usernameLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(13f)
    }

    private val textColumn = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        addView(nameLabel)
        addView(usernameLabel)
    }

    init {
        avatarSlot.addView(
            imageAvatar,
            FrameLayout.LayoutParams(AVATAR_SIZE.dp, AVATAR_SIZE.dp),
        )
        addView(avatarSlot, LayoutParams(AVATAR_SIZE.dp, AVATAR_SIZE.dp))
        addView(textColumn, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(avatarSlot, 12f)
            toCenterY(avatarSlot, 10f)
            startToEnd(textColumn, avatarSlot, 12f)
            toCenterY(textColumn)
            toEnd(textColumn, 16f)
        }
        updateTheme()
    }

    fun bind(user: AccountMfa.User) {
        nameLabel.text = user.name
        val handle = user.username?.takeIf { it.isNotEmpty() }
        usernameLabel.text = handle?.let { "@$it" }
        usernameLabel.visibility = if (handle != null) VISIBLE else GONE

        initialsAvatar?.let { avatarSlot.removeView(it) }
        val tg = TelegramAvatarView(context, user).apply {
            id = generateViewId()
        }
        avatarSlot.addView(
            tg,
            0,
            FrameLayout.LayoutParams(AVATAR_SIZE.dp, AVATAR_SIZE.dp),
        )
        initialsAvatar = tg

        val rasterUrl = user.avatarUrl
        if (rasterUrl != null) imageAvatar.set(Content.ofUrl(rasterUrl)) else imageAvatar.clear()
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color, 0f, ViewConstants.BLOCK_RADIUS.dp)
        nameLabel.setTextColor(WColor.PrimaryText.color)
        usernameLabel.setTextColor(WColor.SecondaryText.color)
    }
}
