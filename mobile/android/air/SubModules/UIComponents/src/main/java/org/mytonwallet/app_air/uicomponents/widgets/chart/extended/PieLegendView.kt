package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.content.Context
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface

class PieLegendView(
    context: Context
) : LegendSignatureView(context) {
    private val root: LinearLayout
    private var signature: TextView? = null
    private var value: TextView? = null

    init {
        root = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(4.dp, 2.dp, 4.dp, 2.dp)
        }
        signature = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_DIP, 14f)
            typeface = WFont.DemiBold.typeface
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            maxWidth = 120.dp
        }
        root.addView(
            signature,
            LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        )
        value = TextView(context).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_DIP, 14f)
            typeface = WFont.Medium.typeface
            gravity = Gravity.END
        }
        root.addView(
            value,
            LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                marginStart = 8.dp
            }
        )
        addView(root)

        setPadding(12.dp, 12.dp, 12.dp, 12.dp)
        chevron.visibility = GONE
        zoomEnabled = false
    }

    override fun recolor() {
        if (signature == null) {
            return
        }
        super.recolor()
        signature?.setTextColor(style.primaryTextColor)
        if (value?.currentTextColor == 0) {
            value?.setTextColor(style.primaryTextColor)
        }
    }

    fun setData(name: String?, value: Long, color: Int, percentagePrefix: CharSequence? = null) {
        signature?.text = if (percentagePrefix.isNullOrEmpty()) {
            name
        } else {
            "$percentagePrefix $name"
        }
        this.value?.text = valueFormatter?.formatLegendValue(value, this.value!!.paint) ?: value.toString()
        this.value?.setTextColor(color)
    }

    override fun setSize(n: Int) {
    }

    fun setData(index: Int, date: Long, lines: ArrayList<LineViewData>) {
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        root.measure(widthMeasureSpec, heightMeasureSpec)
        val width = root.measuredWidth + paddingLeft + paddingRight
        val height = root.measuredHeight + paddingTop + paddingBottom
        setMeasuredDimension(width, height)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val childLeft = paddingLeft
        val childTop = paddingTop
        root.layout(
            childLeft,
            childTop,
            childLeft + root.measuredWidth,
            childTop + root.measuredHeight
        )
    }
}
