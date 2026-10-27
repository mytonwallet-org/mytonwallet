package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import org.mytonwallet.app_air.uicomponents.commonViews.cardMotion.mix

internal object CardSurfaceTextures {
    val transparent = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
    fun default(context: Context, gram: Boolean): CardBackgroundArtwork.Artwork {
        val base = if (!gram) {
            BitmapFactory.decodeResource(
                context.resources,
                org.mytonwallet.app_air.uicomponents.R.drawable.img_card
            )
        } else {
            Bitmap.createBitmap(800, 464, Bitmap.Config.ARGB_8888).also {
                val c = Canvas(it)
                c.scale(2f, 2f)
                val angle =
                    145 * PI / 180
                val dx = sin(angle).toFloat()
                val dy = -cos(angle).toFloat()
                val len =
                    (abs(dx) * 400 + abs(dy) * 232) / 2
                val p = Paint(Paint.ANTI_ALIAS_FLAG)
                p.shader =
                    LinearGradient(
                        200 - dx * len,
                        116 - dy * len,
                        200 + dx * len,
                        116 + dy * len,
                        intArrayOf(
                            Color.rgb(92, 200, 255),
                            Color.rgb(0, 136, 255),
                            Color.rgb(0, 87, 194)
                        ),
                        floatArrayOf(0f, .46f, 1f),
                        Shader.TileMode.CLAMP
                    )
                c.drawRect(0f, 0f, 400f, 232f, p)
            }
        }
        val spots = if (gram) {
            emptyList()
        } else {
            listOf(
                floatArrayOf(335f, 30f, 190f, 160f, .05f, .94f, 1f, .72f),
                floatArrayOf(65f, 205f, 175f, 145f, .06f, .71f, 1f, .6f),
                floatArrayOf(100f, -10f, 180f, 140f, .015f, .23f, .93f, .6f)
            ).map { v ->
                Bitmap.createBitmap(656, 488, Bitmap.Config.ARGB_8888).also { b ->
                    val c = Canvas(b)
                    c.translate(128 + v[0], 128 + v[1])
                    c.scale(v[2], v[3])
                    val p = Paint(Paint.ANTI_ALIAS_FLAG)
                    fun color(a: Float) = Color.argb(
                        (a * 255).roundToInt(),
                        (v[4] * 255).roundToInt(),
                        (v[5] * 255).roundToInt(),
                        (
                            v[6] *
                                255
                            ).roundToInt()
                    )
                    p.shader =
                        RadialGradient(
                            0f,
                            0f,
                            1f,
                            intArrayOf(color(v[7]), color(v[7] * .55f), color(0f)),
                            floatArrayOf(0f, .4f, 1f),
                            Shader.TileMode.CLAMP
                        )
                    c.drawCircle(0f, 0f, 1f, p)
                }
            }
        }
        return CardBackgroundArtwork.Artwork(base, spots, null, 0f)
    }
    val brush: Bitmap by lazy {
        Bitmap.createBitmap(800, 464, Bitmap.Config.ARGB_8888).also { b ->
            val c = Canvas(b)
            c.scale(2f, 2f)
            c.drawColor(Color.rgb(128, 128, 128))
            val patterns =
                arrayOf(
                    11.7f to arrayOf(Triple(0f, .7f, .32f), Triple(.7f, 1.25f, -.18f)),
                    5.2f to
                        arrayOf(
                            Triple(0f, .14f, .22f),
                            Triple(.95f, 1.85f, -.14f),
                            Triple(1.85f, 2.7f, .16f)
                        ),
                    8.3f to
                        arrayOf(
                            Triple(0f, .45f, -.18f),
                            Triple(1.15f, 1.95f, .28f),
                            Triple(1.95f, 2.15f, -.12f),
                            Triple(4.2f, 4.38f, .12f)
                        ),
                    6.1f to
                        arrayOf(
                            Triple(0f, .22f, .42f),
                            Triple(.22f, .7f, -.2f),
                            Triple(1.45f, 1.58f, .18f),
                            Triple(2.5f, 3.45f, -.16f)
                        )
                )
            val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
            for ((period, strokes) in patterns) {
                var offset = 0f
                while (offset < hypot(400f, 232f)) {
                    for ((start, end, opacity) in strokes) {
                        p.color =
                            if (opacity >
                                0
                            ) {
                                Color.WHITE
                            } else {
                                Color.BLACK
                            }
                        p.alpha = (abs(opacity) * 255).roundToInt()
                        p.strokeWidth =
                            end - start
                        c.drawCircle(200f, 116f, offset + (start + end) / 2, p)
                    }
                    offset += period
                }
            }
        }
    }
    fun glow(width: Float): Pair<Bitmap, Float> {
        val radius = width * 1.18 * sqrt(.4) / 2
        val extent = (radius * 2 + 144).toFloat()
        val n = 512
        val raw = FloatArray(n * n)
        val stops = arrayOf(0.0 to .27, .28 to .1425, .58 to .0525, 1.0 to 0.0)
        for (y in 0 until n) {
            for (x in 0 until n) {
                val distance = hypot(x + .5 - 256, y + .5 - 256) * extent / n
                if (distance <= radius) {
                    val at =
                        distance / (radius * sqrt(2.0))
                    val idx = stops.indexOfFirst { it.first >= at }.coerceAtLeast(1)
                    val a = stops[
                        idx -
                            1
                    ]
                    val z = stops[idx]
                    raw[y * n + x] = (
                        mix(
                            a.second,
                            z.second,
                            (at - a.first) / (z.first - a.first)
                        )
                        ).toFloat()
                }
            }
        }
        val sigma =
            24 * n / extent
        val reach = ceil(3 * sigma).toInt()
        val weights =
            FloatArray(reach * 2 + 1) {
                exp(-((it - reach).toDouble().pow(2)) / (2 * sigma * sigma)).toFloat()
            }
        val total = weights.sum()
        for (i in weights.indices) {
            weights[i] /=
                total
        }
        val mid = FloatArray(raw.size)
        val blurred = FloatArray(raw.size)
        for (y in 0 until n) {
            for (x in 0 until n) {
                var v = 0f
                for (k in -reach..reach) {
                    if (x + k in
                        0 until n
                    ) {
                        v += raw[y * n + x + k] * weights[k + reach]
                    }
                }
                mid[y * n + x] = v
            }
        }
        for (y in 0 until n) {
            for (x in 0 until n) {
                var v = 0f
                for (k in -reach..reach) {
                    if (y + k in
                        0 until n
                    ) {
                        v += mid[(y + k) * n + x] * weights[k + reach]
                    }
                }
                blurred[y * n + x] = v
            }
        }
        val pixels =
            IntArray(raw.size) {
                Color.argb((blurred[it] * 255).roundToInt().coerceIn(0, 255), 255, 255, 255)
            }
        return Bitmap.createBitmap(pixels, n, n, Bitmap.Config.ARGB_8888) to extent
    }
}
