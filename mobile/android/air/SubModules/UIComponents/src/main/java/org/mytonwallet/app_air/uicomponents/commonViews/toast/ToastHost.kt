package org.mytonwallet.app_air.uicomponents.commonViews.toast

import android.content.Context
import android.view.ViewGroup
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setMarginsDp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import kotlin.time.Duration

class ToastHost(context: Context) : WFrameLayout(context) {

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val toastQueue = ArrayDeque<ToastManager.Toast>()

    private var blurRootView: ViewGroup? = null
    private var toastView: ToastView? = null

    private var collectorJob: Job? = null
    private var dismissJob: Job? = null
    private var activeToast: ToastManager.Toast? = null
    private var isToastEnabled = true

    init {
        clipChildren = false
        clipToPadding = false
        isInvisible = true
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        syncSubscription()
    }

    override fun onDetachedFromWindow() {
        unsubscribeFromToasts()
        clearToasts()
        super.onDetachedFromWindow()
    }

    private fun onToastRequested(presentation: ToastManager.Toast) {
        toastQueue.addLast(presentation)
        showNextIfPossible()
    }

    fun setToastEnabled(enabled: Boolean) {
        if (isToastEnabled == enabled) {
            return
        }

        isToastEnabled = enabled
        if (enabled) {
            syncSubscription()
        } else {
            unsubscribeFromToasts()
            clearToasts()
        }
    }

    fun pauseBlurring() {
        toastView?.pauseBlurring()
    }

    fun resumeBlurring() {
        if (activeToast != null && isToastEnabled) {
            toastView?.resumeBlurring()
        }
    }

    fun attachBlurRoot(blurRootView: ViewGroup?) {
        if (this.blurRootView === blurRootView) {
            return
        }
        this.blurRootView = blurRootView
        toastView?.attachBlurRoot(blurRootView)
    }

    private fun showNextIfPossible() {
        if (!isToastEnabled || activeToast != null || toastQueue.isEmpty()) {
            return
        }

        activeToast = toastQueue.removeFirst()
        configureActiveToast()
        animateToastIn()
    }

    private fun configureActiveToast() {
        val presentation = activeToast ?: return
        val toastView = getOrCreateToastView()
        toastView.configure(presentation) {
            presentation.onAction?.invoke()
            dismissCurrentToast()
        }
    }

    private fun animateToastIn() {
        isInvisible = false
        val toastView = getOrCreateToastView().apply {
            animate().cancel()
            isVisible = true
            alpha = 0f
            scaleX = 0.9f
            scaleY = 0.9f
            translationY = 12f.dp
            syncShadow()
            resumeBlurring()
        }

        toastView.animate()
            .alpha(1f)
            .scaleX(1f)
            .scaleY(1f)
            .translationY(0f)
            .setDuration(AnimationConstants.QUICK_ANIMATION)
            .setUpdateListener {
                toastView.syncShadow()
            }
            .setInterpolator(CubicBezierInterpolator.EASE_OUT)
            .withEndAction {
                toastView.syncShadow()
                activeToast?.let { toast ->
                    scheduleDismiss(toast.duration)
                }
            }
            .start()
    }

    private fun dismissCurrentToast() {
        cancelDismiss()
        val shouldContinue = isToastEnabled
        activeToast = null
        val toastView = toastView ?: return
        toastView.animate().cancel()
        toastView.animate()
            .alpha(0f)
            .scaleX(0.9f)
            .scaleY(0.9f)
            .translationY(12f.dp)
            .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
            .setUpdateListener {
                toastView.syncShadow()
            }
            .setInterpolator(CubicBezierInterpolator.EASE_OUT)
            .withEndAction {
                toastView.isInvisible = true
                toastView.syncShadow()
                toastView.pauseBlurring()
                if (shouldContinue) {
                    showNextIfPossible()
                }
                isInvisible = activeToast == null
            }
            .start()
    }

    private fun scheduleDismiss(duration: Duration) {
        cancelDismiss()
        dismissJob = scope.launch {
            delay(duration)
            dismissCurrentToast()
        }
    }

    private fun cancelDismiss() {
        dismissJob?.cancel()
        dismissJob = null
    }

    private fun syncSubscription() {
        if (!isAttachedToWindow || !isToastEnabled) {
            unsubscribeFromToasts()
            return
        }
        if (collectorJob?.isActive == true) {
            return
        }
        collectorJob = scope.launch {
            ToastManager.toastsFlow.collect(::onToastRequested)
        }
    }

    private fun unsubscribeFromToasts() {
        collectorJob?.cancel()
        collectorJob = null
    }

    private fun clearToasts() {
        cancelDismiss()
        toastQueue.clear()
        activeToast = null

        toastView?.apply {
            animate().cancel()
            isInvisible = true
            alpha = 0f
            syncShadow()
            pauseBlurring()
        }
        isInvisible = true
    }

    private fun getOrCreateToastView(): ToastView {
        toastView?.let { return it }

        return ToastView(context).apply {
            attachBlurRoot(blurRootView)
        }.also { toastView ->
            addView(
                toastView,
                LayoutParams(LayoutParams.MATCH_PARENT, ToastView.HEIGHT_DP.dp).apply {
                    setMarginsDp(22, 12, 22, 12)
                })
            this.toastView = toastView
        }
    }
}
