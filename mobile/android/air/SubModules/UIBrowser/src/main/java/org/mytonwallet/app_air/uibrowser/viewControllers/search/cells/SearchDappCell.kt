package org.mytonwallet.app_air.uibrowser.viewControllers.search.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.IDapp

@SuppressLint("ViewConstructor")
class SearchDappCell(context: Context, private val onTap: (site: IDapp) -> Unit) :
    WCell(context, LayoutParams(MATCH_PARENT, 64.dp)), WThemedView {

    private val dappImageView: WCustomImageView by lazy {
        WCustomImageView(context).apply {
            defaultRounding = Content.Rounding.Radius(6f.dp)
        }
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.SemiBold)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            setTextColor(WColor.PrimaryText)
            compoundDrawablePadding = 4.dp
        }
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(12f, WFont.Regular)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            setTextColor(WColor.SecondaryText)
        }
    }

    private val openButton = WLabel(context).apply {
        setStyle(14f, WFont.SemiBold)
        text =
            LocaleController.getString("Open")
        gravity = Gravity.CENTER
        setTextColor(WColor.Tint)
        setPadding(10.dp, 0, 10.dp, 0)
        setOnClickListener {
            site?.let {
                onTap(it)
            }
        }
    }

    private val separatorView: WBaseView by lazy {
        val sw = WBaseView(context)
        sw
    }

    override fun setupViews() {
        super.setupViews()
        addView(dappImageView, LayoutParams(24.dp, 24.dp))
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(subtitleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(openButton, LayoutParams(WRAP_CONTENT, 28.dp))
        addView(separatorView, LayoutParams(0, ViewConstants.SEPARATOR_HEIGHT))
        setConstraints {
            toStart(dappImageView, 18f)
            toCenterY(dappImageView)
            constrainedWidth(titleLabel.id, true)
            setHorizontalBias(titleLabel.id, 0f)
            toStart(titleLabel, 56f)
            toTop(titleLabel, 11.5f)
            endToStart(titleLabel, openButton, 10f)
            toStart(subtitleLabel, 56f)
            topToBottom(subtitleLabel, titleLabel, 1f)
            endToStart(subtitleLabel, openButton, 10f)
            toEnd(openButton, 12f)
            toCenterY(openButton)
            toBottom(separatorView)
            toEnd(separatorView, 0f)
            toStart(separatorView, 56f)
        }

        setOnClickListener {
            site?.let {
                onTap(it)
            }
        }
    }

    var site: IDapp? = null
    var isLastItem = false
    fun configure(site: IDapp, isLastItem: Boolean) {
        this.site = site
        this.isLastItem = isLastItem
        dappImageView.set(Content.ofUrl(site.iconUrl ?: ""))
        titleLabel.text = site.name
        titleLabel.isSelected = false
        subtitleLabel.text = when (site) {
            is MExploreSite -> {
                site.description
            }

            is ApiDapp -> {
                LocaleController.getString("Connected Dapp")
            }

            else -> {
                ""
            }
        }
        separatorView.isGone = isLastItem

        updateTheme()
    }

    override fun updateTheme() {
        openButton.setBackgroundColor(WColor.SecondaryBackground.color, 16f.dp)
        openButton.addRippleEffect(WColor.BackgroundRipple.color, 16f.dp)
        if ((site as? MExploreSite)?.isTelegram == true) {
            val telegramIcon = ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_telegram
            )
            telegramIcon?.let { drawable ->
                drawable.setTint(WColor.PrimaryText.color.colorWithAlpha(50))
                drawable.setBounds(0, 0, drawable.intrinsicWidth, drawable.intrinsicHeight)
                titleLabel.setCompoundDrawablesRelativeWithIntrinsicBounds(
                    null, null, drawable, null
                )
            }
        } else {
            titleLabel.setCompoundDrawablesRelativeWithIntrinsicBounds(
                null, null, null, null
            )
        }
        setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isLastItem) ViewConstants.STANDARD_ROUNDS.dp else 0f
        )
        addRippleEffect(
            WColor.BackgroundRipple.color,
            0f,
            if (isLastItem) ViewConstants.STANDARD_ROUNDS.dp else 0f
        )
        separatorView.setBackgroundColor(WColor.Separator.color)
    }

}
