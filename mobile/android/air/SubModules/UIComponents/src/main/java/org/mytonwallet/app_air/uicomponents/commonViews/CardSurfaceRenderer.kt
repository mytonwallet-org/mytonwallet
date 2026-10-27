package org.mytonwallet.app_air.uicomponents.commonViews

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.SystemClock
import android.view.animation.PathInterpolator
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import org.mytonwallet.app_air.uicomponents.commonViews.cardMotion.CardSurfaceLight
import org.mytonwallet.app_air.uicomponents.commonViews.cardMotion.fract
import org.mytonwallet.app_air.uicomponents.commonViews.cardMotion.mix
import org.mytonwallet.app_air.uicomponents.commonViews.cardMotion.quintic
import org.mytonwallet.app_air.uicomponents.commonViews.cardMotion.smooth
import org.mytonwallet.app_air.uicomponents.commonViews.cardMotion.unit

@androidx.annotation.RequiresApi(33)
internal class CardSurfaceRenderer(
    private val source: String,
    val profile: CardMotionProfile,
    val artwork: CardBackgroundArtwork.Artwork,
    val glow: Pair<Bitmap, Float>
) {
    val shader = createShader()
    private val stars = RuntimeShader(STAR_SHADER)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val starValues = FloatArray(80)
    private val stillPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private class Resume(val from: CardSurfaceFrame, var startedAt: Long? = null)
    private var suspended = true
    private var lastFrame: CardSurfaceFrame? = null
    private var resume: Resume? = null
    private var frameCommitOwner: Any? = null
    private var appearanceStartedAt: Long? = null
    private val appearanceCurve = PathInterpolator(.42f, 0f, .58f, 1f)
    var onTextureReady: (() -> Unit)? = null
    private val backdropCache = if (profile.gram) {
        CardSurfaceBackdropCache(::createShader, ::applyFrame) { onTextureReady?.invoke() }
    } else {
        null
    }
    val hasFrame get() = lastFrame != null
    val isResuming get() = resume != null
    val awaitingFirstResumeFrame get() = resume != null && resume?.startedAt == null
    val isAppearing get() = hasFrame &&
        (appearanceStartedAt == null || SystemClock.uptimeMillis() - appearanceStartedAt!! < 300L)

    fun activate(animated: Boolean) {
        if (!suspended) return
        suspended = false
        lastFrame?.takeIf { animated }?.let { resume = Resume(it) }
    }

    fun pause() {
        suspended = true
        resume = null
        frameCommitOwner = null
        backdropCache?.pause()
    }

    fun frameCommittedCallback(): (() -> Unit)? {
        if (suspended || !hasFrame || frameCommitOwner != null ||
            (appearanceStartedAt != null && (resume == null || resume?.startedAt != null))
        ) {
            return null
        }
        val owner = Any()
        val transition = resume
        frameCommitOwner = owner
        return {
            if (frameCommitOwner === owner && !suspended) {
                frameCommitOwner = null
                val now = SystemClock.uptimeMillis()
                if (appearanceStartedAt == null) appearanceStartedAt = now
                if (resume === transition) transition?.startedAt = now
                onTextureReady?.invoke()
            }
        }
    }

    fun close() {
        pause()
        backdropCache?.close()
        onTextureReady = null
    }

    fun savedFrame(): CardSurfaceFrame? = lastFrame

    fun restoreFrame(frame: CardSurfaceFrame) {
        appearanceStartedAt = SystemClock.uptimeMillis() - 300L
        suspended = false
        update(frame, SystemClock.uptimeMillis())
        pause()
    }

    fun transferPresentationTo(next: CardSurfaceRenderer) {
        val frame = lastFrame ?: return
        next.appearanceStartedAt = appearanceStartedAt
        next.suspended = false
        next.update(frame, SystemClock.uptimeMillis())
        next.resume = resume?.let { Resume(it.from, it.startedAt) }
        next.suspended = suspended
        next.paint.alpha = paint.alpha
        if (suspended) next.backdropCache?.pause()
    }

    private fun createShader(): RuntimeShader {
        val shader = RuntimeShader(source)
        fun input(name: String, bitmap: Bitmap) {
            shader.setInputShader(
                name,
                BitmapShader(bitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
                    setFilterMode(BitmapShader.FILTER_MODE_LINEAR)
                }
            )
        }
        input("artwork", artwork.base)
        for ((i, name) in listOf("firstSpot", "secondSpot", "thirdSpot").withIndex()) {
            input(
                name,
                artwork.spots.getOrNull(i) ?: CardSurfaceTextures.transparent
            )
        }
        input("brush", CardSurfaceTextures.brush)
        input("touchSpot", glow.first)
        shader.setFloatUniform(
            "artSize",
            artwork.base.width.toFloat(),
            artwork.base.height.toFloat()
        )
        shader.setFloatUniform("strength", if (profile.custom) 15f else 0f)
        shader.setFloatUniform("seed", artwork.motionPhase / (2 * PI).toFloat())
        shader.setIntUniform("blobCount", artwork.spots.size)
        shader.setFloatUniform("contrastColor", artwork.contrast?.color ?: -1f)
        shader.setFloatUniform("contrastOpacity", artwork.contrast?.opacity ?: 0f)
        shader.setFloatUniform("brushStrength", if (profile.gram) .15f else 0f)
        shader.setFloatUniform("shine", if (profile.gram) .33f else 0f)
        shader.setIntUniform("customSurface", if (profile.custom) 1 else 0)
        shader.setIntUniform("shineStyle", if (profile.gram) 3 else 0)
        shader.setIntUniform("materialPreset", profile.material)
        shader.setIntUniform("materialEnvironment", 0)
        shader.setFloatUniform("materialIntensity", profile.intensity)
        shader.setFloatUniform("materialBevel", .4f)
        shader.setFloatUniform("materialEmboss", .4f)
        shader.setFloatUniform("materialDepth", 3.5f)
        shader.setFloatUniform("touchExtent", glow.second)
        return shader
    }

    private fun applyFrame(shader: RuntimeShader, frame: CardSurfaceFrame) {
        val light = frame.light
        shader.setFloatUniform("size", frame.width, frame.height)
        shader.setFloatUniform("density", frame.density)
        shader.setFloatUniform("time", frame.lineTime.toFloat())
        shader.setFloatUniform("blobTime", frame.blobTime.toFloat())
        shader.setFloatUniform("touchExtent", frame.touchExtent)
        shader.setFloatUniform(
            "materialTilt",
            (light.border?.x ?: light.x).toFloat(),
            (light.border?.y ?: light.y).toFloat()
        )
        shader.setFloatUniform(
            "touchPosition",
            light.touch?.position?.x?.toFloat() ?: 0f,
            light.touch?.position?.y?.toFloat() ?: 0f
        )
        shader.setFloatUniform(
            "touchOpacity",
            ((light.touch?.opacity ?: 0.0) * .7).toFloat()
        )
        shader.setFloatUniform("gramAngle", light.gram?.rotation?.toFloat() ?: 0f)
        shader.setFloatUniform("gramEnergy", light.gram?.energy?.toFloat() ?: 1f)
    }

    fun update(target: CardSurfaceFrame, now: Long) {
        if (suspended) return
        val transition = resume
        val elapsed = transition?.startedAt?.let { (now - it) / 1000.0 } ?: 0.0
        val frame = if (transition != null) {
            target.copy(
                light = target.light.interpolated(
                    transition.from.light,
                    CardSurfaceLight.resumeProgress(elapsed),
                    gpu = true
                ),
                lineTime = if (transition.startedAt ==
                    null
                ) {
                    transition.from.lineTime
                } else {
                    target.lineTime
                },
                blobTime = if (transition.startedAt ==
                    null
                ) {
                    transition.from.blobTime
                } else {
                    target.blobTime
                },
                touchExtent = mix(
                    transition.from.touchExtent.toDouble(),
                    target.touchExtent.toDouble(),
                    CardSurfaceLight.resumeProgress(elapsed)
                ).toFloat()
            )
        } else {
            target
        }
        if (elapsed >= CardSurfaceLight.RESUME_SECONDS) resume = null
        lastFrame = frame
        applyFrame(shader, frame)
        paint.alpha = appearanceStartedAt?.let {
            (
                255 * appearanceCurve.getInterpolation(
                    ((now - it) / 300f).coerceIn(0f, 1f)
                )
                ).roundToInt()
        } ?: 1
        if (profile.gram) {
            stars.setInputShader(
                "backdrop",
                backdropCache?.shaderFor(
                    frame,
                    frame.backgroundKey(profile.custom, artwork.spots.isNotEmpty()),
                    now
                ) ?: shader
            )
            stars.setFloatUniform("size", frame.width, frame.height)
            stars.setFloatUniform("density", frame.density)
            val angle = frame.light.gram?.rotation ?: 0.0
            val energy = frame.light.gram?.energy ?: 1.0
            val activity = frame.light.activity
            for (i in 0 until 20) {
                val p = STAR_POS[i]
                val phase = i * 2.3999632
                val twinkle =
                    smooth(
                        (.5 + .5 * sin(frame.blobTime * (.28 + fract(phase) * .14) + phase) - .15) /
                            .85
                    )
                val field =
                    telegramField(
                        p[0] / 400.0,
                        p[1] / 232.0,
                        frame.height / frame.width.toDouble(),
                        angle,
                        energy,
                        frame.width.toDouble()
                    )
                val activation = field * (.35 + .65 * activity)
                val inside = smooth((field - .05) / .70)
                starValues[i * 4] = p[0]
                starValues[i * 4 + 1] = p[1]
                starValues[i * 4 + 2] = (
                    STAR_RADIUS[i] * (.15 + .85 * twinkle + .45 * activation + .1 * activity) *
                        mix(
                            .5,
                            1.0,
                            inside
                        )
                    ).toFloat()
                starValues[i * 4 + 3] =
                    (
                        unit(.65 * twinkle + .7 * activation + .12 * activity) *
                            mix(.5, 1.0, inside)
                        ).toFloat()
            }
            stars.setFloatUniform("stars", starValues)
        }
        paint.shader = if (profile.gram) stars else shader
    }

    fun drawStill(canvas: Canvas, width: Float, height: Float) {
        val scale = max(width / artwork.base.width, height / artwork.base.height)
        val save = canvas.save()
        canvas.translate(
            (width - artwork.base.width * scale) / 2,
            (height - artwork.base.height * scale) / 2
        )
        canvas.scale(scale, scale)
        canvas.drawBitmap(artwork.base, 0f, 0f, stillPaint)
        canvas.scale(artwork.base.width / 400f, artwork.base.height / 232f)
        artwork.spots.forEach { canvas.drawBitmap(it, -128f, -128f, stillPaint) }
        artwork.contrast?.let {
            canvas.drawRect(0f, 0f, 400f, 232f, it.overlay)
            it.base?.let { color -> canvas.drawRect(0f, 0f, 400f, 232f, color) }
        }
        canvas.restoreToCount(save)
    }
    companion object {
        val STAR_POS =
            arrayOf(
                floatArrayOf(
                    30f,
                    28f
                ),
                floatArrayOf(
                    74f,
                    18f
                ),
                floatArrayOf(
                    127f,
                    30f
                ),
                floatArrayOf(
                    211f,
                    18f
                ),
                floatArrayOf(
                    293f,
                    24f
                ),
                floatArrayOf(
                    368f,
                    32f
                ),
                floatArrayOf(
                    344f,
                    63f
                ),
                floatArrayOf(
                    26f,
                    85f
                ),
                floatArrayOf(
                    379f,
                    119f
                ),
                floatArrayOf(
                    27f,
                    147f
                ),
                floatArrayOf(
                    59f,
                    179f
                ),
                floatArrayOf(
                    28f,
                    214f
                ),
                floatArrayOf(
                    101f,
                    209f
                ),
                floatArrayOf(
                    170f,
                    214f
                ),
                floatArrayOf(
                    238f,
                    209f
                ),
                floatArrayOf(
                    316f,
                    212f
                ),
                floatArrayOf(
                    370f,
                    154f
                ),
                floatArrayOf(340f, 165f), floatArrayOf(377f, 69f), floatArrayOf(85f, 56f)
            )
        val STAR_RADIUS =
            floatArrayOf(
                6f,
                3f,
                4f,
                2.5f,
                3f,
                8f,
                3.5f,
                4f,
                5f,
                3f,
                7.5f,
                3f,
                4.5f,
                3f,
                2.5f,
                4f,
                6f,
                3.5f,
                4f,
                3f
            )
        fun telegramField(
            u: Double,
            v: Double,
            aspect: Double,
            angle: Double,
            energy: Double,
            width: Double
        ): Double {
            val px =
                (u - .5) * 2
            val py =
                (.5 - v) * 2 * aspect
            val radius = hypot(px, py)
            val rx = if (radius >
                .0001
            ) {
                px / radius
            } else {
                1.0
            }
            val ry = if (radius > .0001) py / radius else 0.0
            val k = 1 / sqrt(1 + aspect * aspect)
            val dx = k * cos(angle) + aspect * k * sin(angle)
            val dy = k * sin(angle) - aspect * k * cos(angle)
            val alignment = -ry * dx + rx * dy
            val w = mix(.30, .44, (.20 - .13) / .17)
            val core = exp(-alignment * alignment / (2 * w * w))
            val halo = exp(-alignment * alignment / (2 * (w * 1.70).pow(2)))
            val field = mix(core, halo, .42) * mix(.10, 1.0, quintic(radius / .275))
            val balance = mix(.72, 1.0, .5 + .5 * (rx * dx + ry * dy))
            return mix(.086, field * balance, smooth(radius / (2 / width))) * energy
        }
        const val STAR_SHADER = """
            uniform shader backdrop;
            uniform float2 size;
            uniform float density;
            uniform float4 stars[20];
            float3 lin(float3 c) {return float3(c.r<=.04045?c.r/12.92:pow((c.r+.055)/1.055,2.4),c.g<=.04045?c.g/12.92:pow((c.g+.055)/1.055,2.4),c.b<=.04045?c.b/12.92:pow((c.b+.055)/1.055,2.4));}
            float3 enc(float3 c) {return float3(c.r<=.0031308?c.r*12.92:1.055*pow(max(c.r,0.0),1.0/2.4)-.055,c.g<=.0031308?c.g*12.92:1.055*pow(max(c.g,0.0),1.0/2.4)-.055,c.b<=.0031308?c.b*12.92:1.055*pow(max(c.b,0.0),1.0/2.4)-.055);}
            half4 main(float2 p) {
                float3 base=float3(backdrop.eval(p).rgb);
                float3 d=float3(base.r<=.25?((16.0*base.r-12.0)*base.r+4.0)*base.r:sqrt(max(base.r,0.0)),base.g<=.25?((16.0*base.g-12.0)*base.g+4.0)*base.g:sqrt(max(base.g,0.0)),base.b<=.25?((16.0*base.b-12.0)*base.b+4.0)*base.b:sqrt(max(base.b,0.0)));
                float3 result=lin(base);float3 src=lin(d);
                float2 point=p/size*float2(400,232);
                for(int i=0;i<20;i++) {
                    float4 s=stars[i];float2 local=(point-s.xy)/max(s.z,.001);
                    if(abs(local.x)>1.1||abs(local.y)>1.1) continue;
                    float dist=sqrt(abs(local.x))+sqrt(abs(local.y));
                    float2 step=float2(400,232)/(size*density*max(s.z,.001));
                    float aa=max(.02,abs(sqrt(abs(local.x+step.x))-sqrt(abs(local.x)))+abs(sqrt(abs(local.y+step.y))-sqrt(abs(local.y))));
                    float alpha=(1.0-smoothstep(1.0-aa,1.0+aa,dist))*s.w;
                    result=mix(result,src,alpha);
                }
                return half4(half3(enc(result)),1);
            }
        """
    }
}
