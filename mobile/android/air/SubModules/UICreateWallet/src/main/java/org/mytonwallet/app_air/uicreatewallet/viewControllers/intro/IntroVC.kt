package org.mytonwallet.app_air.uicreatewallet.viewControllers.intro

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.Spannable
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.method.LinkMovementMethod
import android.text.style.ClickableSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.View.MeasureSpec
import android.view.View.TEXT_ALIGNMENT_CENTER
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ScrollView
import androidx.appcompat.content.res.AppCompatResources
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.isGone
import kotlin.math.max
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.diamond.WBlueDiamondView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.particles.WelcomeParticleView
import org.mytonwallet.app_air.uicomponents.widgets.scaleIn
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicreatewallet.viewControllers.addAccountOptions.AddAccountOptionsVC
import org.mytonwallet.app_air.uicreatewallet.viewControllers.backup.BackupVC
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uisettings.viewControllers.appInfo.AppInfoVC
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.requireDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.SpanHelpers
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig

private const val TITLE_TEXT_SIZE = 32f

@SuppressLint("ViewConstructor")
class IntroVC(context: Context, private val network: MBlockchainNetwork) :
    WViewController(context),
    IntroVM.Delegate {
    @Suppress("PropertyName")
    override val TAG = "Intro"

    private val introVM by lazy {
        IntroVM(this)
    }

    override val shouldDisplayTopBar = false

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
            restingCanvasSize = 190.dp
        ).apply {
            id = View.generateViewId()
            onParticleInteraction =
                { pressed, hovered -> tonParticlesView.setInteraction(pressed, hovered) }
        }
    } else {
        null
    }

    private val diamondContainer = diamondAnimationView?.let { diamond ->
        WView(context).apply {
            translationZ = 1.dp.toFloat()
            clipChildren = false
            clipToPadding = false
            addView(diamond, FrameLayout.LayoutParams(190.dp, 190.dp))
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
            setImageDrawable(
                AppCompatResources.getDrawable(
                    view.context,
                    org.mytonwallet.app_air.uicomponents.R.drawable.img_logo
                )
            )
            setOnTouchListener { v, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        Haptics.play(v, HapticType.LIGHT_TAP)
                        v.animate().cancel()
                        v.scaleIn(AnimationConstants.QUICK_ANIMATION, 0.96f, WInterpolator.smooth)
                        tonParticlesView.setInteraction(true, v.isHovered)
                    }

                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        v.animate().cancel()
                        v.scaleIn(
                            AnimationConstants.VERY_QUICK_ANIMATION,
                            interpolator = WInterpolator.smooth
                        )
                        tonParticlesView.setInteraction(false, v.isHovered)
                    }
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

    private val titleImageView = AppCompatImageView(view.context).apply {
        id = View.generateViewId()
        setImageResource(BaseR.drawable.img_welcome_title)
        scaleType = ImageView.ScaleType.FIT_CENTER
        contentDescription =
            LocaleController.getString(context.getString(BaseR.string.app_locale_name_key))
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
    }

    val subtitleLabel = WLabel(view.context).apply {
        text = LocaleController.getString("\$auth_intro")
            .replace("\n", " ")
            .toProcessedSpannableStringBuilder()
        gravity = Gravity.CENTER
        setStyle(17f, WFont.Regular)
        setLineHeight(26f)
        setTextColor(WColor.PrimaryText)
    }

    val moreInfoButton: WLabel by lazy {
        val btn = WLabel(context)
        btn.textAlignment = TEXT_ALIGNMENT_CENTER
        btn.setStyle(16f)
        btn.setTextColor(WColor.SecondaryText)
        btn.setLineHeight(24f)
        btn.gravity = Gravity.CENTER
        btn.setPaddingDp(24, 0, 24, 0)
        btn.setOnClickListener {
            push(AppInfoVC(context))
        }
        btn
    }

    val termsView: WLabel by lazy {
        val btn = WLabel(context)
        btn.id = UIComponentsR.id.intro_terms
        btn.textAlignment = TEXT_ALIGNMENT_CENTER
        btn.setStyle(13f, WFont.Regular)
        btn.setLineHeight(18f)
        btn.setTextColor(WColor.SecondaryText)
        btn.movementMethod = LinkMovementMethod.getInstance()
        btn
    }

    val createNewWalletButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.PRIMARY)
        btn.id = UIComponentsR.id.intro_create_wallet
        btn.text = LocaleController.getString("Create New Wallet")
        btn.setOnClickListener {
            view.lockView()
            createNewWalletButton.isLoading = true
            introVM.createWallet()
        }
        btn
    }

    val importExistingWalletButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.SECONDARY)
        btn.id = UIComponentsR.id.intro_import_wallet
        btn.text = LocaleController.getString("Import Existing Wallet")
        btn.setOnClickListener {
            val window = window ?: return@setOnClickListener
            val nav = WNavigationController(
                window,
                WNavigationController.PresentationConfig(
                    style = WNavigationController.PresentationStyle.BottomSheet
                )
            )
            nav.setRoot(AddAccountOptionsVC(context, network = network, isOnIntro = true))
            window.present(nav)
        }
        btn
    }

    private val contentView = WView(context).apply {
        addView(tonParticlesView, FrameLayout.LayoutParams(386.dp, 268.dp))
        addView(logoImageView, FrameLayout.LayoutParams(124.dp, 124.dp))
        clipChildren = false
        diamondContainer?.let { addView(it, FrameLayout.LayoutParams(124.dp, 124.dp)) }
        val titleScale = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            TITLE_TEXT_SIZE,
            resources.displayMetrics
        ) / (TITLE_TEXT_SIZE * resources.displayMetrics.density)
        addView(
            titleImageView,
            FrameLayout.LayoutParams(
                0,
                (titleImageView.drawable.intrinsicHeight * titleScale).roundToInt()
            )
        )
        addView(subtitleLabel, FrameLayout.LayoutParams(0, WRAP_CONTENT))
        addView(moreInfoButton, FrameLayout.LayoutParams(0, 50.dp))
        addView(
            termsView,
            ConstraintLayout.LayoutParams(0, WRAP_CONTENT).apply {
                matchConstraintMaxWidth = 370.dp
            }
        )
        addView(createNewWalletButton, FrameLayout.LayoutParams(0, WRAP_CONTENT))
        addView(importExistingWalletButton, FrameLayout.LayoutParams(0, WRAP_CONTENT))
    }

    private val scrollView = ScrollView(context).apply {
        id = View.generateViewId()
        addView(contentView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    private fun applyContentConstraints() {
        val screenHeight =
            (window?.windowView?.height ?: 0) -
                (navigationController?.getSystemBars()?.top ?: 0) -
                (navigationController?.getSystemBars()?.bottom ?: 0)
        val desiredHeight = 657.dp

        val logoTopMargin = if (screenHeight < desiredHeight) 40 else 80
        val titleTopMargin = if (screenHeight < desiredHeight) 20f else 32f
        val subtitleTopMargin = if (screenHeight < desiredHeight) 12f else 20f
        val moreInfoTopMargin = if (screenHeight < desiredHeight) 22f else 32f

        contentView.setConstraints {
            toTopPx(
                tonParticlesView,
                (
                    navigationController?.getSystemBars()?.top
                        ?: 0
                    ) + (logoTopMargin - 82).dp
            )
            toCenterX(tonParticlesView)
            toTopPx(
                logoImageView,
                (navigationController?.getSystemBars()?.top ?: 0) + logoTopMargin.dp
            )
            toCenterX(logoImageView)
            diamondContainer?.let {
                toTopPx(
                    it,
                    (navigationController?.getSystemBars()?.top ?: 0) + logoTopMargin.dp
                )
                toCenterX(it)
                topToBottom(titleImageView, it, titleTopMargin)
            } ?: run {
                topToBottom(titleImageView, logoImageView, titleTopMargin)
            }
            toCenterX(titleImageView, 32f)
            topToBottom(subtitleLabel, titleImageView, subtitleTopMargin)
            toCenterX(subtitleLabel, 24f)
            topToBottom(moreInfoButton, subtitleLabel, moreInfoTopMargin)
            toCenterX(moreInfoButton)

            toBottomPx(
                termsView,
                8.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
            toCenterX(termsView, 16f)
            bottomToTop(importExistingWalletButton, termsView, 24f)
            toCenterX(importExistingWalletButton, 32f)
            bottomToTop(createNewWalletButton, importExistingWalletButton, 16f)
            toCenterX(createNewWalletButton, 32f)
        }

        val minRequiredHeight = 580.dp + (navigationController?.getSystemBars()?.top ?: 0) -
            (navigationController?.getSystemBars()?.bottom ?: 0)
        val targetHeight = max(minRequiredHeight, window?.windowView?.height ?: 0)
        contentView.minHeight = targetHeight
    }

    override fun setupViews() {
        super.setupViews()

        setTopBlur(visible = false, animated = false)

        view.addView(
            scrollView,
            ConstraintLayout.LayoutParams(0, 0).apply {
                matchConstraintMaxWidth = WWindow.WIDE_LAYOUT_INNER_WIDTH_DP.dp
            }
        )
        view.setConstraints {
            allEdges(scrollView)
        }

        applyContentConstraints()
        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollView.setPaddingRelative(systemBarStartInset, 0, systemBarEndInset, 0)
        applyContentConstraints()
    }

    override val isTinted = true
    override fun updateTheme() {
        super.updateTheme()
        val backgroundColor = if (ThemeManager.isDark) {
            WColor.SecondaryBackground.color
        } else {
            WColor.Background.color
        }
        view.setBackgroundColor(backgroundColor)
        tonParticlesView.setBackgroundColor(backgroundColor)
        tonParticlesView.particleColor = WColor.Tint.color
        titleImageView.setColorFilter(WColor.PrimaryText.color)
        moreInfoButton.addRippleEffect(WColor.BackgroundRipple.color, ViewConstants.BLOCK_RADIUS.dp)
        updateMoreInfoLabel()
        updateTermsLabel()
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
        tonParticlesView.setInteraction(false, false)
    }

    private fun updateMoreInfoLabel() {
        val attr = SpannableStringBuilder()
        val str = LocaleController.getSpannableStringWithKeyValues(
            "More about %app_name%",
            listOf(
                Pair("%app_name%", context.getString(BaseR.string.app_locale_name_key))
            )
        )
        attr.append(
            SpannableString("$str ").apply {
                setSpan(
                    WFont.Regular,
                    0,
                    length,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
        )
        val drawable = context.requireDrawableCompat(
            org.mytonwallet.app_air.icons.R.drawable.ic_relate_right
        )
        drawable.mutate()
        drawable.setTint(WColor.SecondaryText.color)
        val width = 6.dp
        val height = 9.dp
        drawable.setBounds(0, 2, width, height)
        val imageSpan = VerticalImageSpan(drawable, LocaleController.isRTL)
        attr.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        moreInfoButton.text = attr
    }

    private fun updateTermsLabel() {
        fun link(key: String, url: Int): CharSequence {
            val title = LocaleController.getString(key)
            return SpanHelpers.buildSpannable(
                title,
                object : ClickableSpan() {
                    override fun onClick(widget: View) {
                        val window = window ?: return
                        val nav = WNavigationController(window)
                        nav.setRoot(
                            InAppBrowserVC(
                                context,
                                InAppBrowserConfig(
                                    context.getString(url),
                                    injectDappConnect = false,
                                    injectDarkModeStyles = false,
                                    title = title.replace('\n', ' ')
                                )
                            )
                        )
                        window.present(nav)
                    }

                    override fun updateDrawState(ds: android.text.TextPaint) {
                        ds.color = WColor.Tint.color
                        ds.isUnderlineText = false
                    }
                }
            )
        }
        termsView.text = LocaleController.getSpannableStringWithKeyValues(
            "By continuing, you agree to our %terms% and %privacy%.",
            listOf(
                Pair("%terms%", link("\$auth_terms_of_use", BaseR.string.app_terms_of_use_url)),
                Pair(
                    "%privacy%",
                    link("\$auth_privacy_policy", BaseR.string.app_privacy_policy_url)
                )
            )
        )
        termsView.highlightColor = Color.TRANSPARENT
    }

    override fun mnemonicGenerated(words: Array<String>) {
        createNewWalletButton.isLoading = false
        if (!WGlobalStorage.isPasscodeSet()) {
            push(BackupVC(context, network = network, words = words, true, null), onCompletion = {
                view.unlockView()
            })
        } else {
            // Won't happen unless we present IntroVC somewhere in the app, when some passcode protected accounts already exist.
            val passcodeConfirmVC = PasscodeConfirmVC(
                context,
                PasscodeViewState.Default(
                    LocaleController.getString("Enter Passcode"),
                    "",
                    LocaleController.getString("Create New Wallet"),
                    showNavigationSeparator = false,
                    startWithBiometrics = true
                ),
                task = { passcode ->
                    navigationController?.push(
                        BackupVC(context, network = network, words = words, false, passcode),
                        onCompletion = {
                            navigationController?.removePrevViewControllerOnly()
                        }
                    )
                }
            )
            push(passcodeConfirmVC, onCompletion = {
                view.unlockView()
            })
        }
    }
}
