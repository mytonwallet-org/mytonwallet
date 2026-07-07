package org.mytonwallet.app_air.uisettings.viewControllers.mfa

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.commonViews.TelegramAvatarView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.AccountMfa
import org.mytonwallet.app_air.walletcore.models.MAccount

@SuppressLint("ViewConstructor")
class MfaConfirmHeaderView(
    context: Context,
    titleText: String,
    user: AccountMfa.User,
    account: MAccount?,
) : WView(context), WThemedView {

    companion object {
        private const val AVATAR_SIZE = 80
        private const val AVATAR_OVERLAP = 28
    }

    private val walletAvatar =
        AccountIconView(context, AccountIconView.Usage.ViewItem(28f.dp)).apply {
            id = generateViewId()
            if (account != null) config(account, useTelegramAvatar = true)
        }

    private val telegramAvatar = TelegramAvatarView(context, user).apply {
        id = generateViewId()
    }

    private val userImage = WCustomImageView(context).apply {
        id = generateViewId()
        defaultRounding = Content.Rounding.Round
        defaultPlaceholder = Content.Placeholder.Color(WColor.Transparent)
        val rasterUrl = user.avatarUrl
        if (rasterUrl != null) set(Content.ofUrl(rasterUrl))
    }

    private val userAvatar = FrameLayout(context).apply {
        id = generateViewId()
        addView(
            telegramAvatar,
            FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT),
        )
        addView(
            userImage,
            FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT),
        )
    }

    private val avatarsRow = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        val walletParams = LinearLayout.LayoutParams(AVATAR_SIZE.dp, AVATAR_SIZE.dp).apply {
            marginEnd = -AVATAR_OVERLAP.dp
        }
        addView(walletAvatar, walletParams)
        addView(userAvatar, LinearLayout.LayoutParams(AVATAR_SIZE.dp, AVATAR_SIZE.dp))
        clipChildren = false
    }

    private val titleLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(28f, WFont.Medium)
        gravity = Gravity.CENTER
        text = titleText
    }

    private val userIcon = AppCompatImageView(context).apply {
        id = generateViewId()
        setImageDrawable(
            context.getDrawableCompat(
                org.mytonwallet.app_air.uicomponents.R.drawable.ic_tg_inline,
            )
        )
    }

    private val userLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(17f, WFont.Medium)
        text = userDisplay(user)
    }

    private val userChip = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(10.dp, 6.dp, 14.dp, 6.dp)
        val iconParams = LinearLayout.LayoutParams(20.dp, 20.dp).apply {
            marginEnd = 4.dp
        }
        addView(userIcon, iconParams)
        addView(userLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }

    init {
        clipChildren = false
        addView(avatarsRow, LayoutParams(WRAP_CONTENT, AVATAR_SIZE.dp))
        addView(titleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(userChip, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toTop(avatarsRow, 24f)
            toCenterX(avatarsRow)
            topToBottom(titleLabel, avatarsRow, 26f)
            toCenterX(titleLabel, 8f)
            topToBottom(userChip, titleLabel, 22f)
            toCenterX(userChip)
            toBottom(userChip, 24f)
        }
        updateTheme()
    }

    private fun userDisplay(user: AccountMfa.User): String {
        val u = user.username?.takeIf { it.isNotEmpty() }
        return if (u != null) "${user.name} · @$u" else user.name
    }

    override fun updateTheme() {
        walletAvatar.updateTheme()
        titleLabel.setTextColor(WColor.PrimaryText.color)
        userLabel.setTextColor(WColor.Tint.color)
        userIcon.setColorFilter(WColor.Tint.color)
        userChip.setBackgroundColor(WColor.Tint.color.colorWithAlpha(26), 100f.dp)
    }
}
