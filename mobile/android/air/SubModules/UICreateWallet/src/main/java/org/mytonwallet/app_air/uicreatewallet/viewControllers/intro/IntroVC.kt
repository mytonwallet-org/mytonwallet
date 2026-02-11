package org.mytonwallet.app_air.uicreatewallet.viewControllers.intro

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.Spannable
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ClickableSpan
import android.text.style.ImageSpan
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.View.TEXT_ALIGNMENT_CENTER
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.TextView
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.drawable.CheckboxDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.particles.ParticleConfig
import org.mytonwallet.app_air.uicomponents.widgets.particles.ParticleView
import org.mytonwallet.app_air.uicomponents.widgets.pulseView
import org.mytonwallet.app_air.uicomponents.widgets.shakeView
import org.mytonwallet.app_air.uicreatewallet.viewControllers.addAccountOptions.AddAccountOptionsVC
import org.mytonwallet.app_air.uisettings.viewControllers.appInfo.AppInfoVC
import org.mytonwallet.app_air.uicreatewallet.viewControllers.backup.BackupVC
import org.mytonwallet.app_air.uisettings.viewControllers.userResponsibility.UserResponsibilityVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan

@SuppressLint("ViewConstructor")
class IntroVC(
    context: Context,
    private val network: MBlockchainNetwork,
) : WViewController(context), IntroVM.Delegate {
    override val TAG = "Intro"

    private val introVM by lazy {
        IntroVM(this)
    }

    override val shouldDisplayTopBar = false

    // Normal particle configuration
    private val particleParams = ParticleConfig(
        particleCount = 35,
        centerShift = floatArrayOf(0f, 32f),
        distanceLimit = 0.45f,
        color = ParticleConfig.Companion.PARTICLE_COLORS.TON
    )

    var particlesCleaner: (() -> Unit)? = null
    val tonParticlesView = ParticleView(context).apply {
        id = View.generateViewId()
        isGone = true
    }

    val logoImageView = AppCompatImageView(view.context).apply {
        id = View.generateViewId()
        setImageDrawable(
            ContextCompat.getDrawable(
                view.context,
                org.mytonwallet.app_air.uicomponents.R.drawable.img_logo
            )
        )
        setOnClickListener {
            pulseView(0.98f, AnimationConstants.VERY_VERY_QUICK_ANIMATION)
            tonParticlesView.addParticleSystem(
                ParticleConfig.particleBurstParams(
                    ParticleConfig.Companion.PARTICLE_COLORS.TON
                )
            )
        }
    }

    val titleLabel = WLabel(view.context).apply {
        text = LocaleController.getString("MyTonWallet")
        setStyle(32f, WFont.NunitoExtraBold)
        setTextColor(WColor.PrimaryText)
    }

    val subtitleLabel = WLabel(view.context).apply {
        text = LocaleController.getString("\$auth_intro")
            .replace("\n", " ")
            .toProcessedSpannableStringBuilder()
        gravity = Gravity.CENTER
        setStyle(17f, WFont.Regular)
        setTextColor(WColor.PrimaryText)
    }

    private val checkboxDrawable = CheckboxDrawable {
        termsView.invalidate()
    }
    private var termsAccepted = false

    val moreInfoButton: WLabel by lazy {
        val btn = WLabel(context)
        btn.textAlignment = TEXT_ALIGNMENT_CENTER
        btn.setStyle(16f)
        btn.setPaddingDp(16, 8, 16, 8)
        btn.setOnClickListener {
            push(AppInfoVC(context))
        }
        btn
    }

    val termsView: WLabel by lazy {
        val btn = WLabel(context)
        btn.textAlignment = TEXT_ALIGNMENT_CENTER
        btn.setStyle(14f)
        btn.setPaddingDp(16, 1, 16, 8)
        btn
    }

    val createNewWalletButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.PRIMARY)
        btn.text = LocaleController.getString("Create New Wallet")
        btn.setOnClickListener {
            view.lockView()
            createNewWalletButton.isLoading = true
            introVM.createWallet()
        }
        btn.isEnabled = termsAccepted
        btn
    }

    val importExistingWalletButton: WButton by lazy {
        val btn = WButton(context, WButton.Type.SECONDARY)
        btn.text = LocaleController.getString("Import Existing Wallet")
        btn.setOnClickListener {
            if (!termsAccepted) {
                termsView.shakeView(AnimationConstants.INSTANT_ANIMATION)
                return@setOnClickListener
            }
            val nav = WNavigationController(
                window!!,
                WNavigationController.PresentationConfig(
                    overFullScreen = false,
                    isBottomSheet = true,
                    aboveKeyboard = true
                )
            )
            nav.setRoot(AddAccountOptionsVC(context, network = network, isOnIntro = true))
            window?.present(nav)
        }
        btn
    }

    override fun setupViews() {
        super.setupViews()

        setTopBlur(visible = false, animated = false)

        view.addView(tonParticlesView, FrameLayout.LayoutParams(0, WRAP_CONTENT))
        view.addView(logoImageView, FrameLayout.LayoutParams(124.dp, 124.dp))
        view.addView(titleLabel)
        view.addView(subtitleLabel, FrameLayout.LayoutParams(0, WRAP_CONTENT))
        view.addView(moreInfoButton)
        view.addView(termsView, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        view.addView(createNewWalletButton, FrameLayout.LayoutParams(0, WRAP_CONTENT))
        view.addView(importExistingWalletButton, FrameLayout.LayoutParams(0, WRAP_CONTENT))

        view.isVisible = false
        view.post {
            view.isVisible = true
            val screenHeight =
                (navigationController?.height ?: 0) -
                    (navigationController?.getSystemBars()?.top ?: 0) -
                    (navigationController?.getSystemBars()?.bottom ?: 0)
            val minRequiredHeight = 657.dp

            val logoTopMargin = if (screenHeight < minRequiredHeight) 40 else 80
            val titleTopMargin = if (screenHeight < minRequiredHeight) 20f else 30f
            val subtitleTopMargin = if (screenHeight < minRequiredHeight) 12f else 18f
            val moreInfoTopMargin = if (screenHeight < minRequiredHeight) 22f else 43f

            view.setConstraints {
                toTopPx(
                    tonParticlesView,
                    (navigationController?.getSystemBars()?.top
                        ?: 0) + (if (screenHeight < minRequiredHeight) -23 else 17).dp
                )
                toCenterX(tonParticlesView)
                toTopPx(
                    logoImageView,
                    (navigationController?.getSystemBars()?.top ?: 0) + logoTopMargin.dp
                )
                toCenterX(logoImageView)
                topToBottom(titleLabel, logoImageView, titleTopMargin)
                toCenterX(titleLabel, 32f)
                topToBottom(subtitleLabel, titleLabel, subtitleTopMargin)
                toCenterX(subtitleLabel, 20f)
                topToBottom(moreInfoButton, subtitleLabel, moreInfoTopMargin)
                toCenterX(moreInfoButton)

                toBottomPx(
                    importExistingWalletButton,
                    32.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
                )
                toCenterX(importExistingWalletButton, 32f)
                bottomToTop(createNewWalletButton, importExistingWalletButton, 16f)
                toCenterX(createNewWalletButton, 32f)
                bottomToTop(termsView, createNewWalletButton, 20f)
                toCenterX(termsView, 32f)
            }
        }

        updateTheme()
    }

    override val isTinted = true
    override fun updateTheme() {
        super.updateTheme()
        val backgroundColor = WColor.Background.color
        view.setBackgroundColor(backgroundColor)
        tonParticlesView.setParticleBackgroundColor(backgroundColor)
        moreInfoButton.addRippleEffect(WColor.BackgroundRipple.color, ViewConstants.BLOCK_RADIUS.dp)
        checkboxDrawable.checkedColor = WColor.Tint.color
        checkboxDrawable.uncheckedColor = WColor.SecondaryText.color
        termsView.addRippleEffect(WColor.BackgroundRipple.color, 16f.dp)
        updateMoreInfoLabel()
        updateTermsLabel()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()

        if (particlesCleaner == null) {
            particlesCleaner = tonParticlesView.addParticleSystem(particleParams)
            tonParticlesView.isGone = false
        }
        tonParticlesView.fadeIn()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        tonParticlesView.fadeOut()
    }

    override fun onDestroy() {
        super.onDestroy()
        particlesCleaner?.invoke()
    }

    private fun updateMoreInfoLabel() {
        val attr = SpannableStringBuilder()
        val str = LocaleController.getSpannableStringWithKeyValues(
            "More about %app_name%",
            listOf(
                Pair("%app_name%", "MyTonWallet")
            )
        )
        attr.append(SpannableString("$str ").apply {
            setSpan(
                WFont.Regular,
                0,
                length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        })
        val drawable = ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.walletcontext.R.drawable.ic_relate_right
        )!!
        drawable.mutate()
        drawable.setTint(WColor.SecondaryText.color)
        val width = 6.dp
        val height = 9.dp
        drawable.setBounds(0, 2, width, height)
        val imageSpan = VerticalImageSpan(drawable, LocaleController.isRTL)
        attr.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        moreInfoButton.text = attr
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun updateTermsLabel() {
        val attr = SpannableStringBuilder()
        val termsString = LocaleController.getString("use the wallet responsibly")
        checkboxDrawable.setBounds(
            (-2).dp,
            1,
            checkboxDrawable.intrinsicWidth + 2.dp,
            checkboxDrawable.intrinsicHeight + 1
        )
        val imageSpan = ImageSpan(checkboxDrawable, ImageSpan.ALIGN_BOTTOM)
        attr.append(" ")
        attr.setSpan(imageSpan, 0, 1, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        attr.append("  ")
        attr.append(
            LocaleController.getSpannableStringWithKeyValues(
                "I agree to %term%",
                listOf(
                    Pair("%term%", termsString)
                )
            )
        )
        val start = attr.indexOf(termsString)
        if (start >= 0) {
            val end = start + termsString.length
            val clickableSpan = object : ClickableSpan() {
                override fun onClick(widget: View) {
                    push(UserResponsibilityVC(context))
                }

                override fun updateDrawState(ds: android.text.TextPaint) {
                    super.updateDrawState(ds)
                    ds.isUnderlineText = false
                    ds.color = WColor.Tint.color
                }
            }
            attr.setSpan(
                clickableSpan,
                start,
                end,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        termsView.text = attr

        termsView.setOnClickListener {
            // This will be called only when not clicking on the terms link
            termsAccepted = !termsAccepted
            checkboxDrawable.setChecked(termsAccepted, animated = true)
            createNewWalletButton.isEnabled = termsAccepted
        }

        termsView.setOnTouchListener { v, event ->
            val widget = v as TextView
            val action = event.action

            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_DOWN) {
                var x = event.x.toInt()
                var y = event.y.toInt()

                x -= widget.totalPaddingLeft
                y -= widget.totalPaddingTop

                x += widget.scrollX
                y += widget.scrollY

                val layout = widget.layout
                if (layout != null) {
                    val line = layout.getLineForVertical(y)
                    val off = layout.getOffsetForHorizontal(line, x.toFloat())

                    val clickableSpans = attr.getSpans(
                        off, off,
                        ClickableSpan::class.java
                    )

                    if (clickableSpans.isNotEmpty()) {
                        if (action == MotionEvent.ACTION_UP) {
                            clickableSpans[0].onClick(widget)
                        }
                        return@setOnTouchListener true
                    }
                }
            }
            false
        }
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
                        })
                }
            )
            push(passcodeConfirmVC, onCompletion = {
                view.unlockView()
            })
        }
    }
}
