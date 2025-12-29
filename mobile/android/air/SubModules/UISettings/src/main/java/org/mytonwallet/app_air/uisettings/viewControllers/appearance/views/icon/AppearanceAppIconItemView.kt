/*package org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.icon

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.core.content.ContextCompat
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.helpers.LauncherIconController
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class AppearanceAppIconItemView(
    val applicationContext: Context,
    val launcherIcon: LauncherIconController.LauncherIcon,
    val onIconChanged: () -> Unit
) : WView(applicationContext), WThemedView {

    private val imageViewContainer: WView by lazy {
        val v = WView(context)
        v
    }

    private val imageView: WImageView by lazy {
        val imageView = WImageView(context)
        imageView.setImageDrawable(ContextCompat.getDrawable(context, launcherIcon.icon))
        imageView.clipToOutline = true
        imageView
    }

    private val nameLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.text = LocaleController.getString(launcherIcon.title)
        lbl
    }

    override fun setupViews() {
        super.setupViews()

        addView(imageViewContainer, LayoutParams(72.dp, 72.dp))
        imageViewContainer.addView(imageView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(nameLabel)
        setConstraints {
            toTop(imageViewContainer)
            toCenterX(imageViewContainer)
            topToBottom(nameLabel, imageViewContainer, 12f)
            toCenterX(nameLabel)
            toBottom(nameLabel)
        }

        setOnClickListener {
            LauncherIconController.setIcon(applicationContext, launcherIcon)
            onIconChanged()
        }

        updateTheme()
    }

    override fun updateTheme() {
        val isActive = LauncherIconController.isEnabled(applicationContext, launcherIcon)
        val borderPadding = if (isActive) 4 else 4
        imageViewContainer.setPadding(borderPadding)
        imageViewContainer.setBackgroundColor(
            (if (isActive) WColor.Tint else WColor.SecondaryText).color,
            36f.dp
        )
        imageView.setBackgroundColor(Color.TRANSPARENT, 36f.dp)
        nameLabel.setTextColor((if (isActive) WColor.Tint else WColor.SecondaryText).color)
        nameLabel.setStyle(16f, if (isActive) WFont.Medium else WFont.Regular)
    }

}
*/
