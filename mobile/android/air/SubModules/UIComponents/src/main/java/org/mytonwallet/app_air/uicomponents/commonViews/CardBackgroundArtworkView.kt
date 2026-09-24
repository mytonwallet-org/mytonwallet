package org.mytonwallet.app_air.uicomponents.commonViews

import android.animation.ValueAnimator
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.view.Choreographer
import android.view.View
import androidx.core.graphics.withRotation
import androidx.core.graphics.withTranslation
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.sin
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

/** Cached card artwork with optional Home-only displacement and light response. */
class CardBackgroundArtworkView(context: Context) : View(context) {
    private class GramStar(val x: Float, val y: Float, val radius: Float) {
        val azimuth = atan2(x - 0.5f, 0.5f - y)
    }
    private class ColorBlob(
        val x: Float,
        val y: Float,
        val radiusX: Float,
        val radiusY: Float,
        color: Int
    ) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            val alpha = Color.alpha(color)
            shader = RadialGradient(
                0f,
                0f,
                1f,
                intArrayOf(
                    color,
                    Color.argb(
                        (alpha * .55f).toInt(),
                        Color.red(color),
                        Color.green(color),
                        Color.blue(color)
                    ),
                    Color.argb(0, Color.red(color), Color.green(color), Color.blue(color))
                ),
                floatArrayOf(0f, .4f, 1f),
                Shader.TileMode.CLAMP
            )
        }
    }

    companion object {
        private val gramShineBitmap by lazy {
            BitmapFactory.decodeResource(
                ApplicationContextHolder.applicationContext.resources,
                R.drawable.img_gram_card_shine
            )
        }
        private val gramStars = arrayOf(
            GramStar(30f / 400, 28f / 232, 6f), GramStar(74f / 400, 18f / 232, 3f),
            GramStar(127f / 400, 30f / 232, 4f), GramStar(211f / 400, 18f / 232, 2.5f),
            GramStar(293f / 400, 24f / 232, 3f), GramStar(368f / 400, 32f / 232, 8f),
            GramStar(344f / 400, 63f / 232, 3.5f), GramStar(26f / 400, 85f / 232, 4f),
            GramStar(379f / 400, 119f / 232, 5f), GramStar(27f / 400, 147f / 232, 3f),
            GramStar(59f / 400, 179f / 232, 7.5f), GramStar(28f / 400, 214f / 232, 3f),
            GramStar(101f / 400, 209f / 232, 4.5f), GramStar(170f / 400, 214f / 232, 3f),
            GramStar(238f / 400, 209f / 232, 2.5f), GramStar(316f / 400, 212f / 232, 4f),
            GramStar(370f / 400, 154f / 232, 6f), GramStar(340f / 400, 165f / 232, 3.5f),
            GramStar(377f / 400, 69f / 232, 4f), GramStar(85f / 400, 56f / 232, 3f)
        )
        private val gramStarPath = Path().apply {
            moveTo(0f, -1f)
            cubicTo(.08f, -.3f, .3f, -.08f, 1f, 0f)
            cubicTo(.3f, .08f, .08f, .3f, 0f, 1f)
            cubicTo(-.08f, .3f, -.3f, .08f, -1f, 0f)
            cubicTo(-.3f, -.08f, -.08f, -.3f, 0f, -1f)
            close()
        }
    }

    private val artworkPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val gramStarPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val spotPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        alpha = CardBackgroundArtwork.SPOT_ALPHA
    }
    private val myWalletBlobs = arrayOf(
        ColorBlob(335f, 30f, 190f, 160f, Color.argb(184, 13, 240, 255)),
        ColorBlob(65f, 205f, 175f, 145f, Color.argb(153, 15, 181, 255)),
        ColorBlob(100f, -10f, 180f, 140f, Color.argb(153, 4, 59, 237))
    )
    private val gramArtworkBounds = RectF()
    private val gramShineBounds = RectF()
    private val gramShinePaint = if (ApplicationContextHolder.isGramApp) {
        Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            color = Color.WHITE
            xfermode = PorterDuffXfermode(PorterDuff.Mode.ADD)
        }
    } else {
        null
    }
    private val artworkShineShader = LinearGradient(
        -1.5f,
        0f,
        1.5f,
        0f,
        IntArray(13) { index ->
            val distance = -1.5 + index * 0.25
            Color.argb((255 * exp(-2.7725887 * distance * distance)).toInt(), 255, 255, 255)
        },
        FloatArray(13) { it / 12f },
        Shader.TileMode.CLAMP
    )
    private val artworkShineMatrix = Matrix()
    private val artworkShinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        shader = artworkShineShader
        xfermode = PorterDuffXfermode(PorterDuff.Mode.ADD)
    }
    private val linearShine = CardLinearShineMotion()
    private val meshWidth = 12
    private val meshHeight = 7
    private val vertices = FloatArray((meshWidth + 1) * (meshHeight + 1) * 2)
    private val rowEnvelope = FloatArray(meshHeight + 1) { sin(PI * it / meshHeight).toFloat() }
    private val columnEnvelope = FloatArray(meshWidth + 1) { sin(PI * it / meshWidth).toFloat() }
    private val rowWave = FloatArray(meshHeight + 1)
    private val columnWave = FloatArray(meshWidth + 1)
    private var artwork: CardBackgroundArtwork.Artwork? = null
    val hasArtwork: Boolean get() = artwork != null
    private var cardNumber: Int? = null
    private var isDefaultCard = true
    private var requestedEffects = false
    private var fadeOutRequested = false
    private var currentEffects = false
    val effectsActive: Boolean get() = currentEffects
    var onEffectsChanged: ((Boolean) -> Unit)? = null
    var onArtworkChanged: ((Boolean) -> Unit)? = null
    var shineEnabled = false
    var preserveFadeOnReparent = false
    private var tiltX = 0f
    private var tiltY = 0f
    private var press = 0f
    private var devicePitch = 0.0
    private var deviceRoll = 0.0
    private var deviceTiltInitialized = false
    private var lightActivity = 0f
    private var motionTarget = 0f
    private var motionAt = 0L
    private var lastLightAt = 0L
    private var holdRemaining = 0.0
    private var fadeElapsed = 0.0
    private var fadeStart = 0f
    private var lineTime = 0.0
    private var blobTime = 0.0
    private var boost = 0.0
    private var lastAnimationAt = 0L
    private var effectsLevel = 0f
    private var levelFrom = 0f
    private var levelTo = 0f
    private var levelChangedAt = 0L
    private var levelDuration = 0L
    private var framePosted = false
    private var lastFrameNanos = 0L
    private val frameCallback = Choreographer.FrameCallback { frameTimeNanos ->
        framePosted = false
        if (currentEffects || effectsLevel != levelTo) {
            val interactive = press > 0f || lightActivity > 0f || linearShine.isAnimating ||
                SystemClock.uptimeMillis() - motionAt < 400L
            val interval = if (interactive) 16_000_000L else 30_000_000L
            if (lastFrameNanos == 0L || frameTimeNanos - lastFrameNanos >= interval) {
                lastFrameNanos = frameTimeNanos
                invalidate()
            }
            scheduleFrame()
        }
    }
    private val powerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            updateEffects()
        }
    }

    init {
        id = generateViewId()
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    fun setNft(nft: ApiNft?, resolution: Int = 800) {
        val number = nft?.metadata?.mtwCardId?.takeIf { nft.isMtwCard }
        val defaultChanged = isDefaultCard != (nft == null)
        isDefaultCard = nft == null
        if (!defaultChanged && number == cardNumber && (number == null || artwork != null)) {
            onArtworkChanged?.invoke(artwork != null)
            return
        }
        animate().cancel()
        alpha = 1f
        cardNumber = number
        artwork = null
        lineTime = 0.0
        blobTime = 0.0
        boost = 0.0
        linearShine.reset()
        linearShine.rebase(devicePitch, deviceRoll)
        lastAnimationAt = 0L
        onArtworkChanged?.invoke(false)
        updateEffects()
        invalidate()
        if (number == null || nft == null) return
        var loadingSynchronously = true
        CardBackgroundArtwork.load(context, nft, resolution) { image ->
            if (cardNumber != number) return@load
            val shouldFadeIn = image != null && !loadingSynchronously && isShown
            if (shouldFadeIn) alpha = 0f
            artwork = image
            onArtworkChanged?.invoke(image != null)
            updateEffects()
            invalidate()
            if (shouldFadeIn) fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
        }
        loadingSynchronously = false
    }

    fun setEffectsActive(active: Boolean, fadeOut: Boolean = false) {
        requestedEffects = active
        fadeOutRequested = !active && fadeOut
        updateEffects()
    }

    fun setLightTilt(x: Float, y: Float, press: Float = 0f) {
        val nextX = x.coerceIn(-1f, 1f)
        val nextY = y.coerceIn(-1f, 1f)
        val nextPress = press.coerceIn(0f, 1f)
        if (tiltX == nextX && tiltY == nextY && this.press == nextPress) return
        val now = SystemClock.uptimeMillis()
        val dt = (now - lastLightAt) / 1000f
        if (lastLightAt > 0L && dt in 0.001f..0.5f) {
            val speed = hypot(nextX - tiltX, nextY - tiltY) / (dt * 1.5f)
            val movement = ((speed - .08f) / .52f).coerceIn(0f, 1f)
            motionTarget = movement * movement * (3f - 2f * movement)
            motionAt = now
        }
        lastLightAt = now
        tiltX = nextX
        tiltY = nextY
        this.press = nextPress
        postInvalidateOnAnimation()
    }

    fun pressShine() {
        if (!currentEffects || !shineEnabled || gramShinePaint != null) return
        linearShine.press()
        postInvalidateOnAnimation()
    }

    fun setDeviceTilt(pitch: Float, roll: Float, recentered: Boolean) {
        devicePitch = pitch.toDouble()
        deviceRoll = roll.toDouble()
        if (recentered || !deviceTiltInitialized) {
            linearShine.rebase(devicePitch, deviceRoll)
            deviceTiltInitialized = true
        }
    }

    /** Keep an entering Home card's light and fade on the same timeline as the visible card. */
    fun syncEffectsFrom(other: CardBackgroundArtworkView) {
        val now = SystemClock.uptimeMillis()
        other.updateEffectsLevel(now)
        tiltX = other.tiltX
        tiltY = other.tiltY
        press = other.press
        devicePitch = other.devicePitch
        deviceRoll = other.deviceRoll
        deviceTiltInitialized = other.deviceTiltInitialized
        linearShine.copyFrom(other.linearShine)
        lightActivity = other.lightActivity
        motionTarget = other.motionTarget
        motionAt = other.motionAt
        lastLightAt = other.lastLightAt
        holdRemaining = other.holdRemaining
        fadeElapsed = other.fadeElapsed
        fadeStart = other.fadeStart
        lineTime = other.lineTime
        blobTime = other.blobTime
        boost = other.boost
        lastAnimationAt = now
        effectsLevel = other.effectsLevel
        levelFrom = other.levelFrom
        levelTo = other.levelTo
        levelChangedAt = other.levelChangedAt
        levelDuration = other.levelDuration
        lastFrameNanos = other.lastFrameNanos
        requestedEffects = false
        fadeOutRequested = effectsLevel > 0f
        postInvalidateOnAnimation()
        if (effectsLevel != levelTo) scheduleFrame()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        context.registerReceiver(
            powerReceiver,
            IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        )
        updateEffects()
        if (effectsLevel > 0f) {
            postInvalidateOnAnimation()
            scheduleFrame()
        }
    }

    override fun onDetachedFromWindow() {
        animate().cancel()
        alpha = 1f
        context.unregisterReceiver(powerReceiver)
        stopFrameLoop()
        val wasActive = currentEffects
        currentEffects = false
        if (!preserveFadeOnReparent || !fadeOutRequested) {
            effectsLevel = 0f
            levelTo = 0f
            resetLightActivity()
        }
        if (wasActive) onEffectsChanged?.invoke(false)
        super.onDetachedFromWindow()
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        updateEffects()
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        updateEffects()
    }

    private fun updateEffects() {
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val systemAnimationsEnabled = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            ValueAnimator.areAnimatorsEnabled()
        val canAnimate =
            (artwork != null || (isDefaultCard && gramShinePaint == null) || shineEnabled) &&
                isAttachedToWindow &&
                isShown && hasWindowFocus() &&
                WGlobalStorage.getAreAnimationsActive() && systemAnimationsEnabled &&
                power?.isPowerSaveMode != true
        val allowed = requestedEffects && canAnimate
        val fadeOut = !requestedEffects && fadeOutRequested && canAnimate
        if (allowed == currentEffects) {
            val reparenting = preserveFadeOnReparent && fadeOutRequested && !isAttachedToWindow
            if (!allowed && !fadeOut && !reparenting && (effectsLevel > 0f || levelTo > 0f)) {
                setEffectsLevel(0f, 0L)
            }
            return
        }
        currentEffects = allowed
        onEffectsChanged?.invoke(allowed)
        if (allowed) {
            lastAnimationAt = 0L
            setEffectsLevel(1f, 300L)
        } else {
            lastAnimationAt = 0L
            setEffectsLevel(0f, if (fadeOut) 180L else 0L)
        }
    }

    private fun updateEffectsLevel(now: Long) {
        if (effectsLevel == levelTo) return
        val progress = ((now - levelChangedAt).toFloat() / levelDuration).coerceIn(0f, 1f)
        effectsLevel = levelFrom + (levelTo - levelFrom) * progress
        if (!currentEffects && effectsLevel == 0f) resetLightActivity()
    }

    private fun setEffectsLevel(target: Float, duration: Long) {
        val now = SystemClock.uptimeMillis()
        updateEffectsLevel(now)
        levelFrom = effectsLevel
        levelTo = target
        levelChangedAt = now
        levelDuration = duration
        if (duration == 0L) {
            effectsLevel = target
            if (target == 0f) resetLightActivity()
        }
        postInvalidateOnAnimation()
        if (currentEffects || effectsLevel != levelTo) scheduleFrame()
    }

    private fun scheduleFrame() {
        if (framePosted || !isAttachedToWindow) return
        framePosted = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private fun stopFrameLoop() {
        if (framePosted) Choreographer.getInstance().removeFrameCallback(frameCallback)
        framePosted = false
        lastFrameNanos = 0L
    }

    private fun resetLightActivity() {
        press = 0f
        lightActivity = 0f
        motionTarget = 0f
        motionAt = 0L
        lastLightAt = 0L
        holdRemaining = 0.0
        fadeElapsed = 0.0
        fadeStart = 0f
        linearShine.reset()
        deviceTiltInitialized = false
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (currentEffects || effectsLevel > 0f) updateEffects()
        val now = SystemClock.uptimeMillis()
        updateEffectsLevel(now)
        advanceAnimation(now)
        if (isDefaultCard && gramShinePaint != null && shineEnabled) {
            val scale = max(width / 400f, height / 232f)
            val artworkWidth = 400f * scale
            val artworkHeight = 232f * scale
            gramArtworkBounds.set(
                (width - artworkWidth) / 2,
                (height - artworkHeight) / 2,
                (width + artworkWidth) / 2,
                (height + artworkHeight) / 2
            )
            canvas.drawBitmap(
                GramDefaultCardArtwork.base,
                null,
                gramArtworkBounds,
                artworkPaint
            )
        }
        val layers = artwork
        if (layers != null && width > 0 && height > 0) {
            val image = layers.base
            val scale = max(width.toFloat() / image.width, height.toFloat() / image.height)
            canvas.withTranslation(
                (width - image.width * scale) / 2f,
                (height - image.height * scale) / 2f
            ) {
                canvas.scale(scale, scale)
                if (effectsLevel > 0f) {
                    drawMovingArtwork(canvas, image, effectsLevel)
                } else {
                    canvas.drawBitmap(image, 0f, 0f, artworkPaint)
                }
                val layerSave = canvas.save()
                canvas.scale(image.width / 400f, image.height / 232f)
                val spotsSave = canvas.save()
                canvas.rotate((blobTime * .7 * 360 / 40).toFloat(), 200f, 116f)
                layers.spots.forEach { canvas.drawBitmap(it, -128f, -128f, spotPaint) }
                canvas.restoreToCount(spotsSave)
                layers.contrast?.let {
                    canvas.drawRect(0f, 0f, 400f, 232f, it.overlay)
                    it.base?.let { base -> canvas.drawRect(0f, 0f, 400f, 232f, base) }
                }
                canvas.restoreToCount(layerSave)
            }
        }
        if (isDefaultCard && gramShinePaint == null) drawMyWalletBlobs(canvas)
        if (shineEnabled && gramShinePaint != null) {
            val angle = -90f + (tiltX * 90f + tiltY * 60f) * effectsLevel
            if (effectsLevel > 0f && shineEnabled) drawGramShine(canvas, angle, effectsLevel)
        } else if (effectsLevel > 0f && shineEnabled && linearShine.isAnimating) {
            drawArtworkShine(canvas, effectsLevel)
        }
        if (isDefaultCard && gramShinePaint != null && shineEnabled) {
            val angle = -90f + (tiltX * 90f + tiltY * 60f) * effectsLevel
            drawGramStars(canvas, angle)
        }
    }

    private fun advanceAnimation(now: Long) {
        if (!currentEffects) return
        val dt = if (lastAnimationAt ==
            0L
        ) {
            0.0
        } else {
            ((now - lastAnimationAt).coerceIn(0L, 100L)) / 1000.0
        }
        lastAnimationAt = now
        if (dt == 0.0) return
        if (gramShinePaint == null) {
            linearShine.advance(devicePitch, deviceRoll, dt)
        }
        val movement = if (now - motionAt < 100L) motionTarget else 0f
        val target = max(movement, press)
        if (target > 0f) {
            holdRemaining = 1.0
            fadeElapsed = 0.0
            if (target > lightActivity) {
                val response = if (press > 0f) .08 else .16
                lightActivity += ((target - lightActivity) * (1 - exp(-dt / response))).toFloat()
            }
        } else if (lightActivity > 0f) {
            val fadingTime = (dt - holdRemaining).coerceAtLeast(0.0)
            holdRemaining = (holdRemaining - dt).coerceAtLeast(0.0)
            if (fadingTime > 0) {
                if (fadeElapsed == 0.0) fadeStart = lightActivity
                fadeElapsed = (fadeElapsed + fadingTime).coerceAtMost(2.0)
                val progress = fadeElapsed / 2
                lightActivity =
                    (fadeStart * (1 - progress * progress * (3 - 2 * progress))).toFloat()
            }
        }
        lineTime += dt * 1.55
        val boostTarget = max(press, lightActivity).toDouble()
        val response = if (boostTarget > boost) .12 else .65
        val decay = exp(-dt / response)
        val integratedBoost = boostTarget * dt + (boost - boostTarget) * response * (1 - decay)
        blobTime += dt + 2 * integratedBoost
        boost = boostTarget + (boost - boostTarget) * decay
    }

    private fun drawMyWalletBlobs(canvas: Canvas) {
        if (width <= 0 || height <= 0) return
        val save = canvas.save()
        canvas.scale(width / 400f, height / 232f)
        canvas.rotate((blobTime * .7 * 360 / 40).toFloat(), 200f, 116f)
        for (blob in myWalletBlobs) {
            val spotSave = canvas.save()
            canvas.translate(blob.x, blob.y)
            canvas.scale(
                blob.radiusX * CardBackgroundArtwork.SPOT_SCALE,
                blob.radiusY * CardBackgroundArtwork.SPOT_SCALE
            )
            canvas.drawCircle(0f, 0f, 1f, blob.paint)
            canvas.restoreToCount(spotSave)
        }
        canvas.restoreToCount(save)
    }

    private fun drawMovingArtwork(canvas: Canvas, image: Bitmap, strength: Float) {
        val t = lineTime
        val seed = ((cardNumber ?: 0) * 0.61803398875).toFloat()
        for (row in 0..meshHeight) {
            val v = row.toFloat() / meshHeight
            rowWave[row] = (sin(t * 0.7 + v * 5 + seed) - sin(v * 5 + seed)).toFloat()
        }
        for (column in 0..meshWidth) {
            val u = column.toFloat() / meshWidth
            columnWave[column] = (sin(t * 0.53 + u * 4 + seed) - sin(u * 4 + seed)).toFloat()
        }
        val amount = 15f * image.width / 400f * strength
        var index = 0
        for (row in 0..meshHeight) {
            for (column in 0..meshWidth) {
                val u = column.toFloat() / meshWidth
                val v = row.toFloat() / meshHeight
                val envelope = columnEnvelope[column] * rowEnvelope[row]
                vertices[index++] = u * image.width + rowWave[row] * envelope * amount
                vertices[index++] = v * image.height + columnWave[column] * envelope * amount
            }
        }
        canvas.drawBitmapMesh(image, meshWidth, meshHeight, vertices, 0, null, 0, artworkPaint)
    }

    private fun drawGramShine(canvas: Canvas, angle: Float, strength: Float) {
        val paint = gramShinePaint ?: return
        drawRadialShine(canvas, angle, strength, paint)
    }

    private fun drawArtworkShine(canvas: Canvas, strength: Float) {
        val angle = 29f
        val normalX = cos(Math.toRadians(angle.toDouble())).toFloat()
        val normalY = sin(Math.toRadians(angle.toDouble())).toFloat()
        val bandWidth = width * .28f
        val travel = (normalX * width + normalY * height) / 2 + bandWidth * 1.5f
        val offset = linearShine.position.toFloat() * travel
        val centerX = width * .5f + normalX * offset
        val centerY = height * .5f + normalY * offset
        artworkShineMatrix.setScale(bandWidth, 1f)
        artworkShineMatrix.postRotate(angle)
        artworkShineMatrix.postTranslate(centerX, centerY)
        artworkShineShader.setLocalMatrix(artworkShineMatrix)
        artworkShinePaint.alpha = (255 * .14f * strength).toInt()
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), artworkShinePaint)
    }

    private fun drawRadialShine(canvas: Canvas, angle: Float, strength: Float, paint: Paint) {
        val size = width * 1.5f
        val left = (width - size) / 2f
        val top = (height - size) / 2f
        canvas.withRotation(angle, width / 2f, height / 2f) {
            paint.alpha = (255 * strength).toInt()
            gramShineBounds.set(left, top, left + size, top + size)
            canvas.drawBitmap(gramShineBitmap, null, gramShineBounds, paint)
        }
    }

    private fun drawGramStars(canvas: Canvas, angle: Float) {
        val lightAngle = Math.toRadians((angle + 54f).toDouble())
        val time = SystemClock.uptimeMillis() / 1000.0
        for ((index, star) in gramStars.withIndex()) {
            val phase = index * 2.3999632
            val pulse = ((.5 + .5 * sin(phase) - .15) / .85).coerceIn(0.0, 1.0)
            val resting = pulse * pulse * (3 - 2 * pulse)
            val animated = ((.5 + .5 * sin(time * (.45 + index % 5 * .055) + phase) - .15) / .85)
                .coerceIn(0.0, 1.0)
            val twinkle = resting +
                (animated * animated * (3 - 2 * animated) - resting) * effectsLevel.toDouble()
            val light = 1f + .35f * abs(cos(lightAngle - star.azimuth)).toFloat() * effectsLevel
            val scale = gramArtworkBounds.width() / 400f * star.radius *
                (.15f + .85f * twinkle.toFloat()) * light
            canvas.withTranslation(
                gramArtworkBounds.left + gramArtworkBounds.width() * star.x,
                gramArtworkBounds.top + gramArtworkBounds.height() * star.y
            ) {
                canvas.scale(scale, scale)
                gramStarPaint.alpha =
                    (255 * .65f * twinkle.toFloat() * light).toInt().coerceIn(0, 255)
                canvas.drawPath(gramStarPath, gramStarPaint)
            }
        }
    }
}
