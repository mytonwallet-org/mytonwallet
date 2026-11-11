package org.mytonwallet.app_air.uisettings.viewControllers.appInfo

import android.annotation.SuppressLint
import android.content.Context
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.pm.PackageInfoCompat
import androidx.core.view.isGone
import java.lang.ref.WeakReference
import kotlin.math.max
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.diamond.WBlueDiamondView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.particles.WelcomeParticleView
import org.mytonwallet.app_air.uicomponents.widgets.scaleIn
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsItemCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig

class AppInfoVC(context: Context) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "AppInfo"

    override val isContentWidthCapped = true

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = navigationController?.tabBarController == null

    private val isGramApp = ApplicationContextHolder.isGramApp

    val tonParticlesView = WelcomeParticleView(context).apply {
        id = View.generateViewId()
    }

    val diamondAnimationView: WBlueDiamondView? = if (isGramApp) {
        WBlueDiamondView(
            view.context,
            maxGrow = 1.15f,
            hoverSpeed = 2f,
            shouldRotateOnTap = true,
            restingCanvasSize = 146.dp
        ).apply {
            id = View.generateViewId()
            onParticleInteraction = { pressed, hovered ->
                tonParticlesView.setInteraction(pressed, hovered)
            }
        }
    } else {
        null
    }

    private val diamondContainer = diamondAnimationView?.let { diamond ->
        WView(context).apply {
            translationZ = 1.dp.toFloat()
            clipChildren = false
            clipToPadding = false
            addView(diamond, FrameLayout.LayoutParams(146.dp, 146.dp))
            setConstraints {
                toCenterX(diamond)
                toCenterY(diamond)
            }
        }
    }

    val logoImageView = AppCompatImageView(view.context).apply {
        id = View.generateViewId()
        if (isGramApp) {
            isGone = true
        } else {
            setImageDrawable(view.context.getDrawableCompat(R.drawable.img_logo))
            setOnTouchListener { v, event ->
                if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                    Haptics.play(v, HapticType.LIGHT_TAP)
                    v.animate().cancel()
                    v.scaleIn(AnimationConstants.QUICK_ANIMATION, 0.96f, WInterpolator.smooth)
                    tonParticlesView.setInteraction(true, v.isHovered)
                } else if (event.actionMasked == MotionEvent.ACTION_UP ||
                    event.actionMasked == MotionEvent.ACTION_CANCEL
                ) {
                    v.animate().cancel()
                    v.scaleIn(
                        AnimationConstants.VERY_QUICK_ANIMATION,
                        interpolator = WInterpolator.smooth
                    )
                    tonParticlesView.setInteraction(false, v.isHovered)
                }
                false
            }
            setOnHoverListener { v, event ->
                tonParticlesView.setInteraction(
                    v.isPressed,
                    event.action != MotionEvent.ACTION_HOVER_EXIT
                )
                false
            }
            setOnClickListener {
                tonParticlesView.boost()
            }
        }
    }

    private val titleLabel = WLabel(context).apply {
        id = R.id.about_title
        setStyle(20f, WFont.Medium)
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val versionName = packageInfo.versionName ?: ""
        val versionCode = PackageInfoCompat.getLongVersionCode(packageInfo).toString()
        text = LocaleController.getFormattedString(
            "${context.getString(BaseR.string.app_locale_name_key)} v%1$@ (%2$@)",
            listOf(versionName, versionCode)
        )
    }

    private val subtitleLabel = WLabel(context).apply {
        setStyle(14f)
        val websiteUrl = context.getString(BaseR.string.app_website_url)
        text = websiteUrl.removePrefix("https://")
        setPadding(16.dp, 0, 16.dp, 0)
        setOnClickListener {
            openLink(websiteUrl)
        }
    }

    @SuppressLint("SetTextI18n")
    private val descriptionLabel = WLabel(context).apply {
        setPaddingDp(24, 16, 24, 16)
        setStyle(adaptiveFontSize())
        text = (
            LocaleController.getString("\$about_description1") +
                "\n\n" +
                LocaleController.getString("\$about_description2")
            ).toProcessedSpannableStringBuilder()
    }

    private val resourcesLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        text = LocaleController.getStringWithKeyValues(
            "%app_name% Resources",
            listOf(
                "%app_name%" to context.getString(BaseR.string.app_locale_name_key)
            )
        )
        setTextColor(WColor.Tint)
        isTinted = true
        setPaddingDp(20, 14, 20, 5)
    }

    private val watchVideosRow =
        SettingsItemCell(context, baseContentHeight = SettingsItemCell.SIMPLE_ROW_HEIGHT).apply {
            configure(
                SettingsItem(
                    identifier = SettingsItem.Identifier.NONE,
                    icon = org.mytonwallet.app_air.icons.R.drawable.ic_about_video,
                    title = LocaleController.getString("Watch Video about Features"),
                    value = null,
                    hasTintColor = false
                ),
                subtitle = null,
                isFirst = false,
                isLast = false,
                isEnabled = true,
                onTap = {
                    val username = context.getString(BaseR.string.app_tips_telegram_username_en)
                    if (username.isNotEmpty()) openLink("https://t.me/$username")
                }
            )
        }

    private val readBlogRow =
        SettingsItemCell(context, baseContentHeight = SettingsItemCell.SIMPLE_ROW_HEIGHT).apply {
            configure(
                SettingsItem(
                    identifier = SettingsItem.Identifier.NONE,
                    icon = org.mytonwallet.app_air.icons.R.drawable.ic_about_blog,
                    title = LocaleController.getString("Enjoy Monthly Updates in Blog"),
                    value = null,
                    hasTintColor = false
                ),
                subtitle = null,
                isFirst = false,
                isLast = false,
                isEnabled = true,
                onTap = {
                    openLink(context.getString(BaseR.string.app_blog_url))
                }
            )
        }

    private val helpRow =
        SettingsItemCell(context, baseContentHeight = SettingsItemCell.SIMPLE_ROW_HEIGHT).apply {
            configure(
                SettingsItem(
                    identifier = SettingsItem.Identifier.NONE,
                    icon = org.mytonwallet.app_air.icons.R.drawable.ic_about_help,
                    title = LocaleController.getString("Learn New Things in Help Center"),
                    value = null,
                    hasTintColor = false
                ),
                subtitle = null,
                isFirst = false,
                isLast = true,
                isEnabled = true,
                onTap = {
                    val url = context.getString(BaseR.string.app_help_url)
                    if (url.isNotEmpty()) openLink(url)
                }
            )
        }

    private val showWatchVideosRow: Boolean
        get() = context.getString(BaseR.string.app_tips_telegram_username_en).isNotEmpty()

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.layoutDirection = View.LAYOUT_DIRECTION_LTR
        v.clipChildren = false
        v.clipToPadding = false
        v.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        v.addView(tonParticlesView, FrameLayout.LayoutParams(386.dp, 268.dp))
        v.addView(logoImageView, FrameLayout.LayoutParams(96.dp, 96.dp))
        diamondContainer?.let { dv ->
            v.addView(dv, FrameLayout.LayoutParams(96.dp, 96.dp))
        }
        v.addView(titleLabel, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(subtitleLabel, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(descriptionLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(resourcesLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        if (showWatchVideosRow) {
            v.addView(watchVideosRow, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        v.addView(readBlogRow, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(helpRow, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints {
            toTop(tonParticlesView, -30f)
            toCenterX(tonParticlesView)
            toTop(logoImageView, 66f)
            toCenterX(logoImageView)
            diamondContainer?.let {
                toTop(it, 66f)
                toCenterX(it)
                topToBottom(titleLabel, it, 17f)
            } ?: run {
                topToBottom(titleLabel, logoImageView, 17f)
            }
            toCenterX(titleLabel)
            topToBottom(subtitleLabel, titleLabel, 4f)
            toCenterX(subtitleLabel)
            topToBottom(descriptionLabel, subtitleLabel, 25f)
            topToBottom(resourcesLabel, descriptionLabel, 16f)
            if (showWatchVideosRow) {
                topToBottom(watchVideosRow, resourcesLabel)
                topToBottom(readBlogRow, watchVideosRow)
            } else {
                topToBottom(readBlogRow, resourcesLabel)
            }
            topToBottom(helpRow, readBlogRow)
            toBottomPx(
                helpRow,
                navigationController?.bottomInset ?: 0
            )
        }
        v
    }

    private val scrollView: WScrollView by lazy {
        val sv = WScrollView(WeakReference(this))
        sv.addView(scrollingContentView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        sv
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle("")
        setupNavBar(true)

        view.addView(
            scrollView,
            ConstraintLayout.LayoutParams(0, 0).apply {
                matchConstraintMaxWidth = WWindow.WIDE_LAYOUT_INNER_WIDTH_DP.dp
            }
        )
        view.setConstraints {
            allEdges(scrollView)
        }

        scrollView.onScrollChange = { y ->
            setTopBlur(y > 0, animated = true)
        }
        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollingContentView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            0
        )
        scrollingContentView.setConstraints {
            toBottomPx(
                helpRow,
                max(
                    (navigationController?.bottomInset ?: 0),
                    (navigationController?.imeInsetBottom ?: 0)
                )
            )
        }
    }

    override val isTinted = true
    override fun updateTheme() {
        val backgroundColor = WColor.SecondaryBackground.color
        view.setBackgroundColor(backgroundColor)
        tonParticlesView.particleColor = WColor.Tint.color
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.Tint.color)
        subtitleLabel.addRippleEffect(WColor.TintRipple.color, 10f.dp)
        resourcesLabel.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f
        )
        descriptionLabel.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
        descriptionLabel.setTextColor(WColor.PrimaryText.color)
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        diamondAnimationView?.isRenderingEnabled = true
        tonParticlesView.isRenderingEnabled = true
    }

    override fun onDestroy() {
        super.onDestroy()
        diamondAnimationView?.isRenderingEnabled = false
        tonParticlesView.isRenderingEnabled = false
    }

    private fun openLink(link: String) {
        val window = window ?: return
        val nav = WNavigationController(window)
        nav.setRoot(
            InAppBrowserVC(
                context,
                InAppBrowserConfig(
                    link,
                    injectDappConnect = false,
                    injectDarkModeStyles = true
                )
            )
        )
        window.present(nav)
    }
}
