package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BlendMode
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import androidx.core.graphics.createBitmap
import androidx.core.graphics.toColorInt
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.pow
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

internal object CardBackgroundArtwork {
    private const val WIDTH = 400f
    private const val HEIGHT = 232f
    private const val SPOT_PADDING = 128f
    internal const val SPOT_SCALE = 0.85f
    internal const val SPOT_ALPHA = 255

    // Android maps BlurMaskFilter radius to sigma as radius * 0.57735 + 0.5.
    private const val SPOT_BLUR_RADIUS = (40f * SPOT_SCALE - 0.5f) / 0.57735f

    internal class Contrast(val overlay: Paint, val base: Paint?)

    internal class Artwork(val base: Bitmap, val spots: List<Bitmap>, val contrast: Contrast?)

    private val requiredTraits = setOf(
        "Card Type", "Background", "Shine", "Text", "Texture Type", "Texture Color",
        "Texture Rotation", "Texture Size", "Texture Position X", "Texture Position Y",
        "First Spot Color", "First Spot Position", "Second Spot Color", "Second Spot Position",
        "Third Spot Color", "Third Spot Position"
    )
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val images = object : LruCache<String, Artwork>(24 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Artwork) =
            value.base.byteCount + value.spots.sumOf { it.byteCount }
    }
    private var recipes: JSONObject? = null
    private val fetchedNfts = mutableMapOf<String, ApiNft>()
    private val pendingFetches = mutableMapOf<String, MutableList<(ApiNft?) -> Unit>>()

    fun load(context: Context, nft: ApiNft, width: Int, completion: (Artwork?) -> Unit) {
        if (!hasRequiredTraits(nft)) {
            fetchAttributes(nft) { fresh ->
                if (fresh != null && hasRequiredTraits(fresh)) {
                    loadResolved(context, fresh, width, completion)
                } else {
                    completion(null)
                }
            }
            return
        }
        loadResolved(context, nft, width, completion)
    }

    private fun hasRequiredTraits(nft: ApiNft): Boolean {
        val names = nft.metadata?.attributes?.filterNotNull()
            ?.filter { it.value != null }
            ?.mapNotNull { it.traitType }?.toSet() ?: return false
        return names.containsAll(requiredTraits)
    }

    private fun fetchAttributes(nft: ApiNft, completion: (ApiNft?) -> Unit) {
        fetchedNfts[nft.address]?.let { return completion(it) }
        pendingFetches[nft.address]?.let {
            it.add(completion)
            return
        }
        pendingFetches[nft.address] = mutableListOf(completion)
        WalletCore.doOnBridgeReady {
            val method = ApiMethod.Nft.FetchNftByAddress(MBlockchainNetwork.MAINNET, nft.address)
            WalletCore.call(method) { fresh, _ ->
                main.post {
                    val resolved = fresh?.takeIf {
                        it.address == nft.address &&
                            it.metadata?.mtwCardId == nft.metadata?.mtwCardId
                    }
                    if (resolved != null) {
                        if (fetchedNfts.size >= 256) fetchedNfts.clear()
                        fetchedNfts[nft.address] = resolved
                    }
                    pendingFetches.remove(nft.address)?.forEach { it(resolved) }
                }
            }
        }
    }

    private fun loadResolved(
        context: Context,
        nft: ApiNft,
        width: Int,
        completion: (Artwork?) -> Unit
    ) {
        val number = nft.metadata?.mtwCardId ?: return completion(null)
        val key = "$number:$width"
        synchronized(images) { images.get(key) }?.let { return completion(it) }
        val appContext = context.applicationContext
        worker.execute {
            val image = synchronized(images) { images.get(key) } ?: runCatching {
                val data = recipes ?: JSONObject(
                    appContext.assets.open("card-backgrounds/CardBackgroundRecipes.json")
                        .bufferedReader().use { it.readText() }
                ).also { recipes = it }
                val traits = traits(data, nft) ?: return@runCatching null
                render(data, traits, width).also { artwork ->
                    synchronized(images) { images.put(key, artwork) }
                }
            }.getOrNull()
            main.post { completion(image) }
        }
    }

    private fun traits(data: JSONObject, nft: ApiNft): Map<String, String>? {
        if (!nft.isMtwCard) return null
        val values = nft.metadata?.attributes?.filterNotNull()
            ?.associate { it.traitType to it.value } ?: return null
        val attributes = data.getJSONArray("attributes")
        val traits = mutableMapOf<String, String>()
        for (i in 0 until attributes.length()) {
            val attribute = attributes.getJSONObject(i)
            val name = attribute.getString("name")
            val value = values[name] ?: return null
            val options = attribute.getJSONArray("options")
            if ((0 until options.length()).none { options.getString(it) == value }) return null
            traits[name] = value
        }
        return traits
    }

    private fun render(data: JSONObject, traits: Map<String, String>, width: Int): Artwork {
        val height = (width * HEIGHT / WIDTH).toInt()
        val base = createBitmap(width, height)
        val canvas = Canvas(base)
        canvas.scale(width / WIDTH, height / HEIGHT)
        val standard = traits["Card Type"] == "🍀 Standard"
        drawBackground(canvas, data, traits, standard)
        drawTexture(canvas, data, traits, standard)
        if (!standard) {
            drawPremiumHighlight(canvas, traits["Card Type"] == "🗝 Black")
        }
        val spots = if (standard) {
            listOf("First", "Second", "Third").mapNotNull { renderSpot(data, traits, it) }
        } else {
            emptyList()
        }
        val contrast = if (standard) {
            val preview = base.copy(Bitmap.Config.ARGB_8888, true)
            val previewCanvas = Canvas(preview)
            previewCanvas.scale(width / WIDTH, height / HEIGHT)
            val spotPaint = Paint().apply { alpha = SPOT_ALPHA }
            spots.forEach { previewCanvas.drawBitmap(it, -SPOT_PADDING, -SPOT_PADDING, spotPaint) }
            contrastPaint(preview, traits).also { preview.recycle() }
        } else {
            null
        }
        return Artwork(base, spots, contrast)
    }

    private fun drawBackground(
        canvas: Canvas,
        data: JSONObject,
        traits: Map<String, String>,
        standard: Boolean
    ) {
        val type = traits["Card Type"]
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        if (standard) {
            val background = data.getJSONObject("backgrounds").optJSONObject(traits["Background"])
            if (background?.has("transform") == true) {
                paint.shader =
                    radial(background.getJSONArray("transform"), background.getJSONArray("stops"))
            } else {
                paint.color =
                    (
                        background?.optString("fill")?.takeIf {
                            it.isNotEmpty()
                        } ?: "#FFFFFF"
                        ).toColorInt()
            }
        } else if (type == "⚜️ Gold") {
            paint.shader =
                LinearGradient(
                    220f,
                    0f,
                    220f,
                    HEIGHT,
                    Color.rgb(196, 132, 43),
                    Color.rgb(255, 222, 94),
                    Shader.TileMode.CLAMP
                )
        } else {
            paint.color = when (type) {
                "🗝 Black" -> Color.BLACK
                "💍 Platinum" -> Color.rgb(57, 58, 63)
                else -> Color.rgb(196, 195, 197)
            }
        }
        canvas.drawRect(0f, 0f, WIDTH, HEIGHT, paint)
        if (type == "🗝 Black" || type == "💍 Platinum") {
            val black = type == "🗝 Black"
            val oval =
                RectF(
                    if (black) -249f else -274f,
                    if (black) 220f else 249f,
                    if (black) 310f else 285f,
                    if (black) 492f else 521f
                )
            val blur = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor(if (black) "#484D68" else "#010627")
                maskFilter = BlurMaskFilter(129.5f, BlurMaskFilter.Blur.NORMAL)
            }
            canvas.drawOval(oval, blur)
        }
    }

    private fun drawTexture(
        canvas: Canvas,
        data: JSONObject,
        traits: Map<String, String>,
        standard: Boolean
    ) {
        val name = traits["Texture Type"] ?: return
        val items = data.getJSONObject("textures").optJSONArray(name) ?: return
        val paths = (0 until items.length()).map { path(items.getJSONArray(it)) }
        val bounds = RectF()
        paths.forEachIndexed { index, path ->
            val box = RectF()
            path.computeBounds(box, true)
            if (index == 0) bounds.set(box) else bounds.union(box)
        }
        val scale = (traits["Texture Size"]?.toFloatOrNull() ?: 900f) / 900f
        val rotation = -(traits["Texture Rotation"]?.removeSuffix("°")?.toFloatOrNull() ?: 0f)
        val x =
            ((traits["Texture Position X"]?.removeSuffix("%")?.toFloatOrNull() ?: 0f) / 100f) *
                (WIDTH - bounds.width() * scale) -
                bounds.left * scale
        val y =
            ((traits["Texture Position Y"]?.removeSuffix("%")?.toFloatOrNull() ?: 0f) / 100f) *
                (HEIGHT - bounds.height() * scale) -
                bounds.top * scale
        val save = canvas.save()
        canvas.translate(x + bounds.centerX() * scale, y + bounds.centerY() * scale)
        canvas.rotate(rotation)
        canvas.scale(scale, scale)
        canvas.translate(-bounds.centerX(), -bounds.centerY())
        val gold = traits["Card Type"] == "⚜️ Gold"
        val layer = if (gold) canvas.saveLayerAlpha(null, 191) else null
        val hex = if (standard) {
            data.getJSONObject(
                "colors"
            ).getJSONObject("Texture Color").optString(traits["Texture Color"], "#FFFFFF")
        } else if (traits["Card Type"] == "💍 Platinum") {
            "#000006"
        } else {
            "#FFFFFF"
        }
        paths.forEach { current ->
            val box = RectF()
            current.computeBounds(box, true)
            val paint = colorPaint(hex, box.centerX(), box.top, box.centerX(), box.bottom).apply {
                if (name != "Desert" && name != "Moderate") {
                    style = Paint.Style.STROKE
                    strokeWidth = 0.5f
                }
            }
            canvas.drawPath(current, paint)
        }
        if (layer != null) canvas.restoreToCount(layer)
        canvas.restoreToCount(save)
    }

    private fun renderSpot(
        data: JSONObject,
        traits: Map<String, String>,
        ordinal: String
    ): Bitmap? {
        val key = "$ordinal Spot"
        val color = data.getJSONObject("colors").getJSONObject("$key Color")
            .optString(traits["$key Color"], "")
        val spot = data.getJSONObject("spots").getJSONObject(key)
            .optJSONObject(traits["$key Position"]) ?: return null
        if (color.isEmpty() || traits["$key Color"] == "No") return null
        val bitmap =
            createBitmap((WIDTH + 2 * SPOT_PADDING).toInt(), (HEIGHT + 2 * SPOT_PADDING).toInt())
        val canvas = Canvas(bitmap)
        canvas.translate(SPOT_PADDING, SPOT_PADDING)
        val filter = spot.getJSONArray("filter")
        canvas.clipRect(
            filter.f(0),
            filter.f(1),
            filter.f(0) + filter.f(2),
            filter.f(1) + filter.f(3)
        )
        val spotPath = path(spot.getJSONArray("commands"))
        val bounds = RectF()
        spotPath.computeBounds(bounds, true)
        spotPath.transform(
            Matrix().apply {
                setScale(SPOT_SCALE, SPOT_SCALE, bounds.centerX(), bounds.centerY())
            }
        )
        val paint = colorPaint(color, 134.545f, 219.305f, 425.876f, 219.305f).apply {
            maskFilter = BlurMaskFilter(SPOT_BLUR_RADIUS, BlurMaskFilter.Blur.NORMAL)
        }
        canvas.drawPath(spotPath, paint)
        return bitmap
    }

    private fun drawPremiumHighlight(canvas: Canvas, black: Boolean) {
        val save = canvas.save()
        canvas.clipRect(
            if (black) 116f else 111f,
            if (black) -119f else -103f,
            if (black) 488.769f else 417f,
            if (black) 123f else 103f
        )
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(248, 248, 248)
            maskFilter = BlurMaskFilter(if (black) 52f else 45f, BlurMaskFilter.Blur.NORMAL)
        }
        canvas.drawOval(
            RectF(
                if (black) 220f else 194f,
                if (black) -15f else -11f,
                if (black) 384.77f else 358.77f,
                if (black) 19f else 23f
            ),
            paint
        )
        canvas.restoreToCount(save)
    }

    private fun contrastPaint(bitmap: Bitmap, traits: Map<String, String>): Contrast {
        val darkText = traits["Text"] == "Dark"
        val mean = DoubleArray(3)
        var samples = 0
        val scale = bitmap.width / WIDTH
        for (y in 68..127 step 3) {
            for (x in 74..325 step 3) {
                val pixel = bitmap.getPixel((x * scale).toInt(), (y * scale).toInt())
                mean[0] += Color.red(pixel) / 255.0
                mean[1] += Color.green(pixel) / 255.0
                mean[2] += Color.blue(pixel) / 255.0
                samples++
            }
        }
        for (i in mean.indices) {
            mean[i] /= max(1, samples)
        }
        val overlay = if (darkText) 1.0 else 0.0
        val text = if (darkText) {
            doubleArrayOf(47 / 255.0, 50 / 255.0, 65 / 255.0)
        } else {
            doubleArrayOf(1.0, 1.0, 1.0)
        }

        fun luminance(rgb: DoubleArray): Double {
            val linear = rgb.map { component ->
                if (component <= 0.04045) {
                    component / 12.92
                } else {
                    ((component + 0.055) / 1.055).pow(2.4)
                }
            }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            fun contrast(alpha: Double): Double {
                val adjusted = DoubleArray(3) { mean[it] * (1 - alpha) + overlay * alpha }
                val a = luminance(adjusted)
                val b = luminance(text)
                return (max(a, b) + 0.05) / (minOf(a, b) + 0.05)
            }
            var low = 0.16
            var high = 1.0
            if (contrast(low) < 4.5) {
                repeat(20) {
                    val mid = (low + high) / 2
                    if (contrast(mid) >= 4.5) high = mid else low = mid
                }
            } else {
                high = low
            }
            val color = if (darkText) Color.WHITE else Color.BLACK
            val alpha = (high * 255).toInt().coerceAtMost(255)
            val shader = RadialGradient(
                200f,
                116f,
                1f,
                intArrayOf(
                    Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color)),
                    Color.TRANSPARENT
                ),
                null,
                Shader.TileMode.CLAMP
            )
            shader.setLocalMatrix(Matrix().apply { setScale(269.69f, 158f, 200f, 116f) })
            return Contrast(Paint(Paint.ANTI_ALIAS_FLAG).apply { this.shader = shader }, null)
        }

        val base = DoubleArray(3) { mean[it] * 0.84 + overlay * 0.16 }
        val blended = DoubleArray(3) {
            if (base[it] < 0.5) {
                2 * base[it] * overlay
            } else {
                1 - 2 * (1 - base[it]) * (1 - overlay)
            }
        }

        fun contrast(alpha: Double): Double {
            val adjusted = DoubleArray(3) { base[it] * (1 - alpha) + blended[it] * alpha }
            val a = luminance(adjusted)
            val b = luminance(text)
            return (max(a, b) + 0.05) / (minOf(a, b) + 0.05)
        }

        var low = 0.0
        var high = if (contrast(0.0) >= 4.5) 0.0 else 1.0
        if (high > 0.0 && contrast(high) >= 4.5) {
            repeat(20) {
                val mid = (low + high) / 2
                if (contrast(mid) >= 4.5) high = mid else low = mid
            }
        }
        val color = if (darkText) Color.WHITE else Color.BLACK
        fun paint(opacity: Double, overlayBlend: Boolean): Paint {
            val stops = floatArrayOf(0f, 0.25f, 0.5f, 0.75f, 1f)
            val alphas = doubleArrayOf(1.0, 0.8, 0.5, 0.2, 0.0)
            val shader = RadialGradient(
                200f,
                116f,
                1f,
                IntArray(stops.size) { index ->
                    Color.argb(
                        (opacity * alphas[index] * 255).toInt(),
                        Color.red(color),
                        Color.green(color),
                        Color.blue(color)
                    )
                },
                stops,
                Shader.TileMode.CLAMP
            )
            shader.setLocalMatrix(Matrix().apply { setScale(269.69f, 158f, 200f, 116f) })
            return Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.shader = shader
                if (overlayBlend) blendMode = BlendMode.OVERLAY
            }
        }
        return Contrast(paint(high, true), paint(0.16, false))
    }

    private fun radial(transform: JSONArray, stops: JSONArray): Shader {
        val colors =
            IntArray(stops.length()) {
                Color.parseColor(stops.getJSONObject(it).getString("color"))
            }
        val positions =
            FloatArray(stops.length()) { stops.getJSONObject(it).getDouble("location").toFloat() }
        return RadialGradient(0f, 0f, 1f, colors, positions, Shader.TileMode.CLAMP).apply {
            setLocalMatrix(
                Matrix().apply {
                    setValues(
                        floatArrayOf(
                            transform.f(
                                0
                            ),
                            transform.f(
                                2
                            ),
                            transform.f(
                                4
                            ),
                            transform.f(1), transform.f(3), transform.f(5), 0f, 0f, 1f
                        )
                    )
                }
            )
        }
    }

    private fun colorPaint(hex: String, x0: Float, y0: Float, x1: Float, y1: Float): Paint {
        val colors = hex.split("-").map(Color::parseColor)
        return Paint(Paint.ANTI_ALIAS_FLAG).apply {
            if (colors.size == 1) {
                color = colors[0]
            } else {
                shader =
                    LinearGradient(x0, y0, x1, y1, colors.toIntArray(), null, Shader.TileMode.CLAMP)
            }
        }
    }

    private fun path(commands: JSONArray): Path = Path().apply {
        for (i in 0 until commands.length()) {
            val command = commands.getJSONArray(i)
            when (command.getInt(0)) {
                0 -> moveTo(command.f(1), command.f(2))

                1 -> lineTo(command.f(1), command.f(2))

                2 -> cubicTo(
                    command.f(1),
                    command.f(2),
                    command.f(3),
                    command.f(4),
                    command.f(5),
                    command.f(6)
                )

                3 -> quadTo(command.f(1), command.f(2), command.f(3), command.f(4))

                4 -> close()
            }
        }
    }

    private fun JSONArray.f(index: Int) = getDouble(index).toFloat()
}
