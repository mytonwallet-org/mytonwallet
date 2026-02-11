package org.mytonwallet.app_air.uibrowser.viewControllers.search.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
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
    WCell(context, LayoutParams(MATCH_PARENT, 60.dp)), WThemedView {

    private val openButtonRipple = WRippleDrawable.create(16f.dp)
    private val ripple = WRippleDrawable.create(0f)
    private val rippleLastItem = WRippleDrawable.create(0f, 0f, ViewConstants.BLOCK_RADIUS.dp, ViewConstants.BLOCK_RADIUS.dp)

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
        background = openButtonRipple
        setOnClickListener {
            site?.let {
                onTap(it)
            }
        }
    }

    override fun setupViews() {
        super.setupViews()
        addView(dappImageView, LayoutParams(24.dp, 24.dp))
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(subtitleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(openButton, LayoutParams(WRAP_CONTENT, 28.dp))
        setConstraints {
            toStart(dappImageView, 18f)
            toCenterY(dappImageView)
            constrainedWidth(titleLabel.id, true)
            setHorizontalBias(titleLabel.id, 0f)
            toStart(titleLabel, 56f)
            toTop(titleLabel, 9.5f)
            endToStart(titleLabel, openButton, 10f)
            toStart(subtitleLabel, 56f)
            topToBottom(subtitleLabel, titleLabel, 1f)
            endToStart(subtitleLabel, openButton, 10f)
            toEnd(openButton, 12f)
            toCenterY(openButton)
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

        updateTheme()
    }

    override fun updateTheme() {
        openButtonRipple.backgroundColor = WColor.SecondaryBackground.color
        openButtonRipple.rippleColor = WColor.BackgroundRipple.color
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
        val currentRipple = if (isLastItem) rippleLastItem else ripple
        background = currentRipple
        currentRipple.backgroundColor = WColor.Background.color
        currentRipple.rippleColor = WColor.BackgroundRipple.color
    }

}
