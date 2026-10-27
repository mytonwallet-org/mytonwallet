package org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer

import android.animation.ValueAnimator
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.os.PowerManager
import android.view.Choreographer
import android.view.View
import androidx.annotation.RequiresApi
import org.mytonwallet.app_air.uicomponents.commonViews.cardMotion.CardFrameCadence
import org.mytonwallet.app_air.uicomponents.commonViews.cardMotion.HeroParticleField
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@RequiresApi(34)
internal class HeroSensitiveLayer(
    private val host: View,
    private val content: View,
    val config: WSensitiveDataContainer.HeroConfig,
    private val defaultColor: () -> Int
) {
    private val density = host.resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var colors: Pair<Int, Int>? = null
    private val source = RectF()
    private var framePosted = false
    private var lastFrame = 0L
    private val cadence = CardFrameCadence()

    init {
        host.post {
            if (host.isAttachedToWindow) HeroParticleField.prewarm()
        }
    }
    var active = true
        set(value) {
            if (field == value) return
            field = value
            if (!value) stop() else schedule()
        }
    var finger: Pair<Double, Double>? = null
    private val field = HeroParticleField(
        softwareSnapshot = config.softwareSnapshot,
        visible = { canvas ->
            val save = canvas.save()
            canvas.translate(
                content.left / density - host.width / density / 2,
                content.top / density - host.height / density / 2
            )
            canvas.scale(1 / density, 1 / density)
            content.draw(canvas)
            canvas.restoreToCount(save)
        },
        palette = {
            paint.color = colors?.first ?: defaultColor()
            paint
        }
    )
    val concealed get() = field.concealed
    val cloudActive get() = field.cloudActive
    private fun mode(): Int {
        if (!WGlobalStorage.getAreAnimationsActive() ||
            !ValueAnimator.areAnimatorsEnabled()
        ) {
            return 2
        }
        val power = host.context.getSystemService(PowerManager::class.java)
        return if (power?.isPowerSaveMode == true) 1 else 0
    }
    fun layout() {
        if (host.width == 0 || host.height == 0) return
        val w = config.widthDp
        val h = config.heightDp
        source.set(
            content.left / density - host.width / density / 2,
            content.top / density - host.height / density / 2,
            content.right / density - host.width / density / 2,
            content.bottom / density - host.height / density / 2
        )
        field.layout(RectF(-w / 2, -h / 2, w / 2, h / 2), source)
    }
    fun setColors(primary: Int, secondary: Int) {
        colors = primary to secondary
        paint.shader = if (primary == secondary) {
            null
        } else {
            RadialGradient(
                0f,
                0f,
                config.widthDp * .65f,
                intArrayOf(primary, secondary),
                null,
                Shader.TileMode.CLAMP
            )
        }
        host.invalidate()
    }
    fun setHidden(hidden: Boolean, animated: Boolean, x: Float = 0f, y: Float = 0f) {
        layout()
        field.setConcealed(
            hidden,
            x.toDouble(),
            y.toDouble(),
            if (animated && active && host.isShown &&
                host.isAttachedToWindow
            ) {
                mode()
            } else {
                2
            }
        )
        if (!animated) field.settle()
        updateAccessibility()
        schedule()
        host.requestLayout()
        host.invalidate()
    }
    fun revealLocally(x: Float, y: Float) {
        field.revealLocally(5.0, x.toDouble(), y.toDouble(), mode())
        content.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_AUTO
        host.contentDescription = null
        schedule()
        host.requestLayout()
    }
    fun draw(canvas: Canvas) {
        val save = canvas.save()
        canvas.translate(host.width / 2f, host.height / 2f)
        canvas.scale(density, density)
        field.draw(canvas)
        canvas.restoreToCount(save)
    }
    private val frame = Choreographer.FrameCallback { time ->
        framePosted = false
        if (!active || !host.isAttachedToWindow || !host.isShown || !host.hasWindowFocus()) {
            stop()
            return@FrameCallback
        }
        if (!cadence.shouldTick(time, 60)) {
            schedule()
            return@FrameCallback
        }
        val dt = if (lastFrame == 0L) 1.0 / 60 else ((time - lastFrame) / 1e9).coerceIn(0.0, .1)
        lastFrame = time
        val wasHidden = field.concealed
        val animationMode = mode()
        field.advance(dt, animationMode == 0, finger, animationMode)
        if (wasHidden != field.concealed) host.requestLayout()
        if (wasHidden != field.concealed) updateAccessibility()
        host.invalidate()
        if (!field.cloudActive) host.requestLayout()
        schedule()
    }
    private var revealTimeoutPosted = false
    private val revealTimeout = Runnable {
        revealTimeoutPosted = false
        if (!active || !host.isAttachedToWindow || !host.isShown || !host.hasWindowFocus()) {
            stop()
            return@Runnable
        }
        field.expireLocalReveal(mode())
        updateAccessibility()
        host.requestLayout()
        host.invalidate()
        schedule()
    }

    // A settled local reveal only waits to conceal again, so it needs no frames.
    private fun postRevealTimeout() {
        if (revealTimeoutPosted) return
        revealTimeoutPosted = true
        host.postDelayed(
            revealTimeout,
            (field.localRevealSeconds * 1000).toLong().coerceAtLeast(1L)
        )
    }
    fun schedule() {
        if (framePosted || !active || !host.isAttachedToWindow || !host.isShown ||
            !host.hasWindowFocus()
        ) {
            return
        }
        if (!field.cloudActive) {
            if (field.localRevealPending) postRevealTimeout()
            return
        }
        if (mode() != 0 && !field.animating) return
        framePosted = true
        Choreographer.getInstance().postFrameCallback(frame)
    }
    private fun updateAccessibility() {
        if (field.concealed) {
            content.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            host.contentDescription = LocaleController.getString("Tap to reveal")
        } else {
            content.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_AUTO
            host.contentDescription = null
        }
    }
    fun policyChanged() {
        if (mode() != 0) stop() else schedule()
        host.invalidate()
    }
    fun stop() {
        if (framePosted) Choreographer.getInstance().removeFrameCallback(frame)
        framePosted = false
        host.removeCallbacks(revealTimeout)
        revealTimeoutPosted = false
        lastFrame = 0L
        cadence.reset()
        finger = null
        if (field.localRevealPending &&
            (!active || !host.isAttachedToWindow || !host.isShown || !host.hasWindowFocus())
        ) {
            field.setConcealed(WGlobalStorage.getIsSensitiveDataProtectionOn(), 0.0, 0.0, 2)
            host.requestLayout()
        }
        field.settle()
        if (field.localRevealPending) postRevealTimeout()
        updateAccessibility()
        host.invalidate()
    }
}
