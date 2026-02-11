package org.mytonwallet.app_air.uicomponents.widgets

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.ReplacementSpan
import android.util.AttributeSet
import android.widget.Toast
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import kotlin.math.roundToInt

class CopyTextView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0,
) : AppCompatTextView(context, attrs, defStyle), WThemedView {
    private val span = CopyButtonSpan(context)
    private val ripple = WRippleDrawable.create(8f.dp)

    companion object {
        const val PADDING_HORIZONTAL = 4
        const val PADDING_VERTICAL = 2
    }

    var clipLabel: CharSequence = ""
    var clipToast: CharSequence? = null

    var copyColor: WColor = WColor.SecondaryText
        set(value) {
            field = value
            span.copyDrawable?.setTint(value.color)
            invalidate()
        }

    var rippleColor: WColor = WColor.BackgroundRipple
        set(value) {
            field = value
            ripple.rippleColor = value.color
        }

    init {
        setPaddingDp(PADDING_HORIZONTAL, PADDING_VERTICAL, PADDING_HORIZONTAL, PADDING_VERTICAL)

        background = ripple
        setOnClickListener {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText(clipLabel, originalText)
            clipboard.setPrimaryClip(clip)
            Haptics.play(this, HapticType.LIGHT_TAP)
            clipToast?.let {
                Toast.makeText(context, it, Toast.LENGTH_SHORT).show()
            }
        }

        span.copyDrawable?.setBounds(0, 0, textSize.roundToInt(), textSize.roundToInt())
        updateTheme()
    }

    private var originalText: CharSequence? = null

    fun setText(text: CharSequence?, textToCopy: String) {
        super.setText(text)
        originalText = textToCopy
    }

    override fun setText(text: CharSequence?, type: BufferType?) {
        originalText = text

        val t = text ?: return super.setText(null, type)

        val ssb = SpannableStringBuilder(t)
        ssb.append(' ')
        ssb.setSpan(span, ssb.length - 1, ssb.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        super.setText(ssb, type)
    }

    override fun setTextSize(unit: Int, size: Float) {
        super.setTextSize(unit, size)
        span.copyDrawable?.setBounds(0, 0, textSize.roundToInt(), textSize.roundToInt())
    }

    private class CopyButtonSpan(context: Context) : ReplacementSpan() {
        val copyDrawable =
            ContextCompat.getDrawable(context, org.mytonwallet.app_air.icons.R.drawable.ic_copy_16)

        override fun getSize(
            paint: Paint,
            text: CharSequence?,
            start: Int,
            end: Int,
            fm: Paint.FontMetricsInt?
        ): Int {
            val d = copyDrawable ?: return 0;
            return d.minimumWidth + 3.dp
        }

        override fun draw(
            canvas: Canvas,
            text: CharSequence?,
            start: Int,
            end: Int,
            x: Float,
            top: Int,
            y: Int,
            bottom: Int,
            paint: Paint
        ) {
            val d = copyDrawable ?: return

            canvas.save()
            val transY = bottom - d.bounds.bottom - paint.fontMetricsInt.descent + 2f.dp
            canvas.translate(x + 3.dp, transY)
            d.draw(canvas)
            canvas.restore()
        }
    }

    override fun updateTheme() {
        span.copyDrawable?.setTint(copyColor.color)
        ripple.rippleColor = rippleColor.color
    }
}
