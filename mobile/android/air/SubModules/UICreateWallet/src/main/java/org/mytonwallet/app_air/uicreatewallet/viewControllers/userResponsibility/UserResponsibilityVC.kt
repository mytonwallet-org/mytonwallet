package org.mytonwallet.app_air.uicreatewallet.viewControllers.userResponsibility

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsItemCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import java.lang.ref.WeakReference
import kotlin.math.max

class UserResponsibilityVC(context: Context) : WViewController(context) {

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = true

    private val animationView = WAnimationView(context).apply {
        alpha = 0f
        play(
            org.mytonwallet.app_air.uicomponents.R.raw.animation_snitch,
            true,
            onStart = {
                fadeIn()
            })
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(28f, WFont.Medium)
        text = LocaleController.getString("Use Responsibly")
    }

    @SuppressLint("SetTextI18n")
    private val descriptionLabel = WLabel(context).apply {
        setPaddingDp(24, 16, 24, 16)
        setStyle(16f)
        text = ("${LocaleController.getString("\$auth_responsibly_description1")}\n" +
            "${LocaleController.getString("\$auth_responsibly_description2")}\n" +
            "${LocaleController.getString("\$auth_responsibly_description3")}\n" +
            LocaleController.getString("\$auth_responsibly_description4"))
            .trim()
            .replace("%app_name%", "MyTonWallet")
            .toProcessedSpannableStringBuilder()
    }

    private val termsOfUseRow = SettingsItemCell(context).apply {
        val title = LocaleController.getString("Terms of Use")
        configure(
            SettingsItem(
                identifier = SettingsItem.Identifier.TERMS,
                icon = org.mytonwallet.app_air.uicreatewallet.R.drawable.ic_responsibility_terms,
                title = title,
                value = null,
                hasTintColor = false
            ),
            value = null,
            isFirst = true,
            isLast = false,
            onTap = {
                openLink("https://mytonwallet.io/terms-of-use", title)
            }
        )
        setSeparator(toEnd = 0f)
    }

    private val privacyPolicyRow = SettingsItemCell(context).apply {
        val title = LocaleController.getString("Privacy Policy")
        configure(
            SettingsItem(
                identifier = SettingsItem.Identifier.NONE,
                icon = org.mytonwallet.app_air.uicreatewallet.R.drawable.ic_responsibility_policy,
                title = title,
                value = null,
                hasTintColor = false
            ),
            value = null,
            isFirst = false,
            isLast = true,
            onTap = {
                openLink("https://mytonwallet.io/privacy-policy", title)
            }
        )
        setSeparator(toEnd = 0f)
    }

    private val scrollingContentView: WView by lazy {
        val v = WView(context)
        v.layoutDirection = View.LAYOUT_DIRECTION_LTR
        v.setPaddingDp(ViewConstants.HORIZONTAL_PADDINGS, 0, ViewConstants.HORIZONTAL_PADDINGS, 0)
        v.addView(animationView, ViewGroup.LayoutParams(90.dp, 90.dp))
        v.addView(titleLabel, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(descriptionLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(termsOfUseRow, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(privacyPolicyRow, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints {
            toTopPx(
                animationView,
                (navigationController?.getSystemBars()?.top ?: 0) + 45.dp
            )
            toCenterX(animationView)
            topToBottom(titleLabel, animationView, 26f)
            toCenterX(titleLabel)
            topToBottom(descriptionLabel, titleLabel, 32f)
            topToBottom(termsOfUseRow, descriptionLabel, 16f)
            topToBottom(privacyPolicyRow, termsOfUseRow)
            toBottomPx(
                privacyPolicyRow,
                48.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
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
                privacyPolicyRow,
                48.dp +
                    max(
                        (navigationController?.getSystemBars()?.bottom ?: 0),
                        (window?.imeInsets?.bottom ?: 0)
                    )
            )
        }
    }

    override fun updateTheme() {
        scrollView.setBackgroundColor(WColor.SecondaryBackground.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
        descriptionLabel.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BIG_RADIUS.dp
        )
        descriptionLabel.setTextColor(WColor.PrimaryText.color)
    }

    private fun openLink(link: String, title: String) {
        val nav = WNavigationController(window!!)
        nav.setRoot(
            InAppBrowserVC(
                context,
                null,
                InAppBrowserConfig(
                    link,
                    injectTonConnectBridge = false,
                    injectDarkModeStyles = true,
                    title = title
                )
            )
        )
        window?.present(nav)
    }

}
