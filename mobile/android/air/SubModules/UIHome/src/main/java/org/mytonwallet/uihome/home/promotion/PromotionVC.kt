package org.mytonwallet.uihome.home.promotion

import android.content.Context
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Outline
import android.graphics.Shader
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.PaintDrawable
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.RectShape
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.ApiPromotion
import kotlin.math.min
import kotlin.math.roundToInt

class PromotionVC(
    context: Context,
    private val promotion: ApiPromotion
) : WViewController(context) {

    override val TAG = "Promotion"
    override val shouldDisplayTopBar = false
    override val isExpandable = false

    private val modal get() = promotion.modal

    private var calculatedHeight: Int? = null

    override fun getModalHalfExpandedHeight(): Int? {
        return calculatedHeight ?: super.getModalHalfExpandedHeight()
    }

    private val contentLayout = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
    }

    private val scrollView = ScrollView(context).apply {
        isVerticalScrollBarEnabled = false
        addView(contentLayout, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    override fun setupViews() {
        super.setupViews()

        val container = FrameLayout(context)
        val cornerRadius = ViewConstants.TOOLBAR_RADIUS.dp
        container.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(
                    0,
                    0,
                    view.width,
                    view.height + cornerRadius.toInt(),
                    cornerRadius
                )
            }
        }
        container.clipToOutline = true
        view.addView(container, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))

        setupBackground(container)
        container.addView(scrollView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))

        setupHeroImage()
        setupTitle()
        setupDescription()
        setupAvailabilityIndicator()
        setupActionButton(container)
        setupCloseButton(container)

        view.post {
            contentLayout.measure(
                View.MeasureSpec.makeMeasureSpec(view.width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
            )
            val measured = contentLayout.measuredHeight
            val windowHeight = window?.windowView?.height?.takeIf { it > 0 }
            calculatedHeight = if (windowHeight != null) min(measured, windowHeight) else measured
        }
    }

    private fun setupBackground(container: FrameLayout) {
        val m = modal ?: return

        val fallback = m.backgroundFallback
        val bgColor = parseCssColor(fallback) ?: parseLinearGradient(fallback)
        if (bgColor != null) {
            container.background = bgColor
        } else {
            container.setBackgroundColor(WColor.Background.color)
        }

        val bgUrl = m.backgroundImageUrl
        if (bgUrl.isNotBlank()) {
            val bgImageView = WCustomImageView(context).apply {
                defaultRounding = Content.Rounding.Radius(0f)
                set(Content.ofUrl(bgUrl))
            }
            container.addView(bgImageView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    private fun setupHeroImage() {
        val heroUrl = modal?.heroImageUrl ?: return
        if (heroUrl.isBlank()) return

        val heroView = WCustomImageView(context).apply {
            defaultRounding = Content.Rounding.Radius(0f)
            set(Content.ofUrl(heroUrl))
        }

        val screenWidth = context.resources.displayMetrics.widthPixels
        val heroHeight = (screenWidth * 9f / 16f).roundToInt()
        contentLayout.addView(heroView, LinearLayout.LayoutParams(MATCH_PARENT, heroHeight))
    }

    private fun setupTitle() {
        val m = modal ?: return
        if (m.title.isBlank()) return

        val titleLabel = WLabel(context).apply {
            setStyle(20f, WFont.SemiBold)
            text = m.title
            gravity = Gravity.CENTER
            setTextColor(parseCssColorInt(m.titleColor) ?: Color.WHITE)
            setPadding(16.dp, 8.dp, 16.dp, 0)
        }
        contentLayout.addView(titleLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    private fun setupDescription() {
        val m = modal ?: return
        if (m.description.isBlank()) return

        val descLabel = WLabel(context).apply {
            setStyle(adaptiveFontSize(), WFont.Medium)
            text = parseSimpleMarkdownBold(m.description)
            gravity = Gravity.CENTER
            setTextColor(parseCssColorInt(m.descriptionColor) ?: Color.argb(191, 255, 255, 255))
            setLineSpacing(4f.dp, 1f)
            setPadding(16.dp, 32.dp, 16.dp, 0)
        }
        contentLayout.addView(descLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    private fun setupAvailabilityIndicator() {
        val indicator = modal?.availabilityIndicator ?: return
        if (indicator.isBlank()) return

        val pill = WLabel(context).apply {
            setStyle(13f, WFont.DemiBold)
            text = indicator
            setTextColor(Color.WHITE)
            setPadding(14.dp, 8.dp, 14.dp, 8.dp)
            setBackgroundColor(Color.argb(41, 255, 255, 255), 100f.dp)
        }
        val params = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            topMargin = 32.dp
        }
        contentLayout.addView(pill, params)
    }

    private fun setupActionButton(container: FrameLayout) {
        val actionButton = modal?.actionButton ?: return
        if (actionButton.title.isBlank()) return

        val button = WButton(context).apply {
            setText(actionButton.title)
            setOnClickListener {
                window?.dismissLastNav {
                    WalletCore.notifyEvent(WalletEvent.OpenUrl(actionButton.url))
                }
            }
        }

        val bottomInset = navigationController?.getSystemBars()?.bottom ?: 0
        val buttonContainer = FrameLayout(context).apply {
            setPadding(16.dp, 16.dp, 16.dp, 16.dp + bottomInset)
            addView(button, FrameLayout.LayoutParams(MATCH_PARENT, 50.dp))
        }

        container.addView(
            buttonContainer,
            FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.BOTTOM
            }
        )

        val bottomPadding = 82.dp + bottomInset
        contentLayout.setPadding(0, 0, 0, bottomPadding)
    }

    private fun setupCloseButton(container: FrameLayout) {
        val closeButton = WImageButton(context).apply {
            setImageDrawable(
                context.getDrawableCompat(
                    org.mytonwallet.app_air.uicomponents.R.drawable.ic_close
                )
            )
            updateColors(WColor.White, WColor.BackgroundRipple)
            setPaddingDp(8)
            setOnClickListener {
                window?.dismissLastNav()
            }
        }
        container.addView(
            closeButton,
            FrameLayout.LayoutParams(40.dp, 40.dp).apply {
                gravity = Gravity.TOP or Gravity.END
                topMargin = 8.dp
                marginEnd = 8.dp
            }
        )
    }

    companion object {
        fun parseCssColorInt(css: String?): Int? {
            if (css.isNullOrBlank()) return null
            val trimmed = css.trim()

            if (trimmed.startsWith("#")) {
                return try {
                    Color.parseColor(trimmed)
                } catch (_: Exception) {
                    null
                }
            }

            val rgbaMatch =
                Regex("""rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([0-9.]+))?\s*\)""")
                    .matchEntire(trimmed.lowercase())
            if (rgbaMatch != null) {
                val r = rgbaMatch.groupValues[1].toInt()
                val g = rgbaMatch.groupValues[2].toInt()
                val b = rgbaMatch.groupValues[3].toInt()
                val a = rgbaMatch.groupValues[4].toDoubleOrNull() ?: 1.0
                return Color.argb((a * 255).roundToInt(), r, g, b)
            }

            return null
        }

        private fun parseCssColor(css: String?): GradientDrawable? {
            val color = parseCssColorInt(css) ?: return null
            return GradientDrawable().apply {
                setColor(color)
            }
        }

        private fun parseLinearGradient(css: String?): PaintDrawable? {
            if (css.isNullOrBlank()) return null
            val trimmed = css.trim()
            if (!trimmed.startsWith("linear-gradient(") || !trimmed.endsWith(")")) return null

            val body = trimmed.removePrefix("linear-gradient(").removeSuffix(")")
            val parts = splitTopLevel(body)
            if (parts.size < 2) return null

            val angleDeg = parts[0].trim().removeSuffix("deg").toDoubleOrNull()
            val colorParts = if (angleDeg != null) parts.drop(1) else parts
            val angle = angleDeg ?: 180.0

            val colors = mutableListOf<Int>()
            val positions = mutableListOf<Float>()

            colorParts.forEachIndexed { index, part ->
                val p = part.trim()
                val percentMatch = Regex("""(.+?)\s+([0-9.]+)%\s*$""").find(p)
                val colorStr: String
                val position: Float

                if (percentMatch != null) {
                    colorStr = percentMatch.groupValues[1].trim()
                    position = percentMatch.groupValues[2].toFloat() / 100f
                } else {
                    colorStr = p
                    position =
                        if (colorParts.size == 1) 0f else index.toFloat() / (colorParts.size - 1)
                }

                val color = parseCssColorInt(colorStr) ?: return null
                colors.add(color)
                positions.add(position)
            }

            if (colors.size < 2) return null

            val radians = Math.toRadians(angle)
            val sin = Math.sin(radians).toFloat()
            val cos = Math.cos(radians).toFloat()

            return PaintDrawable().apply {
                shape = RectShape()
                shaderFactory = object : ShapeDrawable.ShaderFactory() {
                    override fun resize(width: Int, height: Int): Shader {
                        val cx = width / 2f
                        val cy = height / 2f
                        return LinearGradient(
                            cx - sin * cx, cy + cos * cy,
                            cx + sin * cx, cy - cos * cy,
                            colors.toIntArray(),
                            positions.toFloatArray(),
                            Shader.TileMode.CLAMP
                        )
                    }
                }
            }
        }

        private fun splitTopLevel(input: String): List<String> {
            val result = mutableListOf<String>()
            var current = StringBuilder()
            var depth = 0
            for (c in input) {
                when {
                    c == '(' -> {
                        depth++; current.append(c)
                    }

                    c == ')' -> {
                        depth--; current.append(c)
                    }

                    c == ',' && depth == 0 -> {
                        result.add(current.toString().trim())
                        current = StringBuilder()
                    }

                    else -> current.append(c)
                }
            }
            if (current.isNotEmpty()) result.add(current.toString().trim())
            return result
        }

        private fun parseSimpleMarkdownBold(text: String): CharSequence {
            val regex = Regex("""\*\*(.+?)\*\*""")
            val matches = regex.findAll(text).toList()
            if (matches.isEmpty()) return text

            val sb = SpannableStringBuilder()
            var lastEnd = 0
            for (match in matches) {
                sb.append(text, lastEnd, match.range.first)
                val boldText = match.groupValues[1]
                val start = sb.length
                sb.append(boldText)
                sb.setSpan(
                    StyleSpan(android.graphics.Typeface.BOLD),
                    start, sb.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                lastEnd = match.range.last + 1
            }
            sb.append(text, lastEnd, text.length)
            return sb
        }
    }
}
