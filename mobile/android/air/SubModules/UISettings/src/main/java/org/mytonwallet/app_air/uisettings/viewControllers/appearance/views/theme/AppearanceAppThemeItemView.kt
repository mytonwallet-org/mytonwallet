package org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.theme

import android.annotation.SuppressLint
import android.content.Context
import android.widget.ImageView
import androidx.core.content.ContextCompat
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.R
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class AppearanceAppThemeItemView(
    context: Context,
    val identifier: String
) : WView(context), WThemedView {

    var isActive: Boolean = false

    private val imageView: WImageView by lazy {
        val imageView = WImageView(context)
        val image = when (identifier) {
            ThemeManager.THEME_SYSTEM -> {
                R.drawable.img_theme_system
            }

            ThemeManager.THEME_LIGHT -> {
                R.drawable.img_theme_light
            }

            ThemeManager.THEME_DARK -> {
                R.drawable.img_theme_dark
            }

            else -> {
                throw Error()
            }
        }
        imageView.setImageDrawable(ContextCompat.getDrawable(context, image))
        imageView.scaleType = ImageView.ScaleType.FIT_XY
        imageView
    }

    private val nameLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(14f, WFont.DemiBold)
        lbl.text = when (identifier) {
            ThemeManager.THEME_SYSTEM -> {
                LocaleController.getString("System")
            }

            ThemeManager.THEME_LIGHT -> {
                LocaleController.getString("Light")
            }

            ThemeManager.THEME_DARK -> {
                LocaleController.getString("Dark")
            }

            else -> {
                ""
            }
        }
        lbl
    }

    override fun setupViews() {
        super.setupViews()

        addView(imageView, LayoutParams(72.dp, 124.dp))
        addView(nameLabel)
        setConstraints {
            toTop(imageView)
            toCenterX(imageView)
            topToBottom(nameLabel, imageView, 12f)
            toCenterX(nameLabel)
            toBottom(nameLabel)
        }

        setOnClickListener {
            Logger.d(Logger.LogTag.SETTINGS, "themeChanged: theme=$identifier")
            WGlobalStorage.setActiveTheme(identifier)
            WalletContextManager.delegate?.themeChanged()
        }

        updateTheme()
    }

    override val isTinted = true
    override fun updateTheme() {
        val borderPadding = if (isActive) 3 else 1
        imageView.setBackgroundColor(
            (if (isActive) WColor.Tint else WColor.SecondaryBackground).color,
            13f.dp
        )
        imageView.setPadding(borderPadding)
        nameLabel.setTextColor((if (isActive) WColor.Tint else WColor.SecondaryText).color)
    }

}
