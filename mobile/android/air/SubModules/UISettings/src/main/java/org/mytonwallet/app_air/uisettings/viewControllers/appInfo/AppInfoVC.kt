package org.mytonwallet.app_air.uisettings.viewControllers.appInfo

import android.annotation.SuppressLint
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.pm.PackageInfoCompat
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WSpeedingDiamondView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.particles.ParticleConfig
import org.mytonwallet.app_air.uicomponents.widgets.particles.ParticleView
import org.mytonwallet.app_air.uicomponents.widgets.pulseView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsItemCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import java.lang.ref.WeakReference
import kotlin.math.max

class AppInfoVC(context: Context) : WViewController(context) {
    override val TAG = "AppInfo"

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = navigationController?.tabBarController == null

    private val isGramApp = ApplicationContextHolder.isGramApp

    private val particleParams: ParticleConfig? = if (isGramApp) ParticleConfig(
        particleCount = 35,
        centerShift = floatArrayOf(0f, -28f),
        distanceLimit = 0.45f,
        colorPair = ParticleConfig.Companion.PARTICLE_COLORS.PURPLE_GRADIENT,
        useStarShape = true
    ) else null

    var particlesCleaner: (() -> Unit)? = null
    val tonParticlesView = ParticleView(context).apply {
        id = View.generateViewId()
        isGone = true
    }

    val diamondAnimationView: WSpeedingDiamondView? = if (isGramApp) {
        WSpeedingDiamondView(view.context).apply {
            id = View.generateViewId()
            bindParticleHost(tonParticlesView, centerShift = floatArrayOf(0f, -28f))
        }
    } else null

    val logoImageView = AppCompatImageView(view.context).apply {
        id = View.generateViewId()
        if (isGramApp) {
            isGone = true
        } else {
            setImageDrawable(view.context.getDrawableCompat(R.drawable.img_logo))
            setOnClickListener {
                pulseView(0.98f, AnimationConstants.VERY_VERY_QUICK_ANIMATION)
                tonParticlesView.addParticleSystem(
                    ParticleConfig.particleBurstParams(
                        ParticleConfig.Companion.PARTICLE_COLORS.TON
                    )
                )
            }
        }
    }

    private val titleLabel = WLabel(context).apply {
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
        setStyle(14f, WFont.DemiBold)
        text =
            LocaleController.getString("MyTonWallet Resources")
        setTextColor(WColor.Tint)
        isTinted = true
        setPaddingDp(20, 14, 20, 5)
    }

    private val watchVideosRow =
        SettingsItemCell(context, baseContentHeight = SettingsItemCell.SIMPLE_ROW_HEIGHT).apply {
            configure(
                SettingsItem(
                    identifier = SettingsItem.Identifier.NONE,
                    icon = org.mytonwallet.app_air.uisettings.R.drawable.ic_about_video,
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
                    icon = org.mytonwallet.app_air.uisettings.R.drawable.ic_about_blog,
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
                    icon = org.mytonwallet.app_air.uisettings.R.drawable.ic_about_help,
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
        v.setPaddingDp(ViewConstants.HORIZONTAL_PADDINGS, 0, ViewConstants.HORIZONTAL_PADDINGS, 0)
        v.addView(tonParticlesView, FrameLayout.LayoutParams(0, WRAP_CONTENT))
        v.addView(logoImageView, FrameLayout.LayoutParams(96.dp, 96.dp))
        diamondAnimationView?.let { dv ->
            v.addView(dv, FrameLayout.LayoutParams(96.dp, 96.dp))
            dv.start()
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
            toTop(tonParticlesView, -11f)
            toCenterX(tonParticlesView)
            toTop(logoImageView, 66f)
            toCenterX(logoImageView)
            diamondAnimationView?.let {
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

        view.addView(scrollView, ViewGroup.LayoutParams(0, 0))
        view.setConstraints {
            allEdges(scrollView)
        }

        scrollView.onScrollChange = { y ->
            if (y > 0) {
                topReversedCornerView?.resumeBlurring()
            } else {
                topReversedCornerView?.pauseBlurring(false)
            }
            setTopBlur(y > 0, animated = true)
        }
        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollingContentView.setConstraints {
            toBottomPx(
                helpRow,
                max(
                    (navigationController?.bottomInset ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }
    }

    override val isTinted = true
    override fun updateTheme() {
        val backgroundColor = WColor.SecondaryBackground.color
        view.setBackgroundColor(backgroundColor)
        tonParticlesView.setParticleBackgroundColor(backgroundColor)
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

    override fun viewDidAppear() {
        super.viewDidAppear()

        if (particleParams != null && particlesCleaner == null) {
            particlesCleaner = tonParticlesView.addParticleSystem(particleParams)
        }
        tonParticlesView.isGone = false
        tonParticlesView.fadeIn(AnimationConstants.VERY_VERY_QUICK_ANIMATION)
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        tonParticlesView.fadeOut(AnimationConstants.VERY_VERY_QUICK_ANIMATION) {
            particlesCleaner?.invoke()
            particlesCleaner = null
            tonParticlesView.isGone = true
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        particlesCleaner?.invoke()
    }

    private fun openLink(link: String) {
        val nav = WNavigationController(window!!)
        nav.setRoot(
            InAppBrowserVC(
                context,
                null,
                InAppBrowserConfig(
                    link,
                    injectDappConnect = false,
                    injectDarkModeStyles = true
                )
            )
        )
        window?.present(nav)
    }

}
