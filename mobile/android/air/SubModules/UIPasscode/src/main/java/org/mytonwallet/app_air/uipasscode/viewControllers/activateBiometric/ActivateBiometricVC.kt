package org.mytonwallet.app_air.uipasscode.viewControllers.activateBiometric

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderAndActionsView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.particles.ParticleConfig
import org.mytonwallet.app_air.uicomponents.widgets.particles.ParticleView
import org.mytonwallet.app_air.uicomponents.widgets.pulseView
import org.mytonwallet.app_air.uipasscode.R
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletcore.models.MBridgeError

@SuppressLint("ViewConstructor")
class ActivateBiometricVC(context: Context, onCompletion: (activated: Boolean) -> Unit) :
    WViewController(context) {
    override val TAG = "ActivateBiometric"

    override val shouldDisplayTopBar = false

    private val particleParams = ParticleConfig(
        particleCount = 35,
        centerShift = floatArrayOf(0f, 32f),
        distanceLimit = 0.45f,
        color = ParticleConfig.Companion.PARTICLE_COLORS.GREEN
    )

    var particlesCleaner: (() -> Unit)? = null
    val greenParticlesView = ParticleView(context).apply {
        id = View.generateViewId()
        isGone = true
    }

    private val headerView: HeaderAndActionsView by lazy {
        val v = HeaderAndActionsView(
            context,
            HeaderAndActionsView.Media.Image(
                image = R.drawable.ic_fingerprint,
                tintedImage = false,
                onClick = {
                    headerView.pulseView(0.98f, AnimationConstants.VERY_VERY_QUICK_ANIMATION)
                    greenParticlesView.addParticleSystem(
                        ParticleConfig.particleBurstParams(
                            ParticleConfig.Companion.PARTICLE_COLORS.GREEN
                        )
                    )
                }
            ),
            title = LocaleController.getString("Use Biometrics"),
            subtitle = LocaleController.getString("\$auth_biometric_info")
                .toProcessedSpannableStringBuilder(),
        )
        v
    }

    private val connectButton = WButton(context, WButton.Type.PRIMARY).apply {
        text = LocaleController.getString("Connect Biometrics")
        setOnClickListener {
            BiometricHelpers.authenticate(
                window!!,
                LocaleController.getString("Use Biometrics"),
                subtitle = null,
                description = null,
                cancel = null,
                onSuccess = {
                    isLoading = true
                    view.lockView()
                    onCompletion(true)
                },
                onCanceled = {}
            )
        }
    }

    private val skipButton = WButton(context, WButton.Type.SECONDARY).apply {
        text = LocaleController.getString("Not Now")
        setOnClickListener {
            isLoading = true
            view.lockView()
            onCompletion(false)
        }
    }

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true)
        setTopBlur(visible = false, animated = false)

        view.addView(greenParticlesView, FrameLayout.LayoutParams(0, WRAP_CONTENT))
        view.addView(headerView)
        view.addView(connectButton, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        view.addView(skipButton, ViewGroup.LayoutParams(0, WRAP_CONTENT))

        view.setConstraints {
            toTopPx(
                headerView,
                WNavigationBar.DEFAULT_HEIGHT.dp +
                    (navigationController?.getSystemBars()?.top ?: 0)
            )
            toCenterX(headerView)
            topToTop(greenParticlesView, headerView, -59f)
            toCenterX(greenParticlesView)
            toBottomPx(skipButton, 32.dp + (navigationController?.getSystemBars()?.bottom ?: 0))
            toCenterX(skipButton, 32f)
            bottomToTop(connectButton, skipButton, 16f)
            toCenterX(connectButton, 32f)
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()

        val backgroundColor = WColor.Background.color
        view.setBackgroundColor(backgroundColor)
        greenParticlesView.setParticleBackgroundColor(backgroundColor)
    }

    override fun viewDidAppear() {
        super.viewDidAppear()

        if (particlesCleaner == null) {
            particlesCleaner = greenParticlesView.addParticleSystem(particleParams)
            greenParticlesView.isGone = false
        }
        greenParticlesView.fadeIn()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        greenParticlesView.fadeOut()
    }

    override fun onDestroy() {
        super.onDestroy()
        particlesCleaner?.invoke()
    }

    override fun showError(error: MBridgeError?) {
        super.showError(error)
        connectButton.isLoading = false
        skipButton.isLoading = false
        view.unlockView()
    }
}
