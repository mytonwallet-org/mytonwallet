package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.text.TextPaint
import android.text.style.ReplacementSpan
import androidx.appcompat.content.res.AppCompatResources
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.R
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentSupportLabelStyle
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentSupportActiveLabelColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentSupportPlateColor
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.sp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

// In dp
private const val LABEL_HEIGHT = 18
private const val LABEL_RADIUS = 6f
private const val LABEL_HORIZONTAL_PADDING = 6
private const val LABEL_MARGIN_END = 6
private const val ICON_SIZE = 12
private const val ICON_GAP = 3

private const val TEXT_SIZE = 12f

/** The label of a chat with support before its preview in the chat list: the headset and Support on a plate */
internal class AgentSupportLabelSpan(context: Context, private val style: AgentSupportLabelStyle) :
    ReplacementSpan() {
    private val text = LocaleController.getString("\$agent_support_label")
    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = TEXT_SIZE.sp
        typeface = WFont.Bold.typeface
    }
    private val platePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val icon = AppCompatResources.getDrawable(
        context,
        R.drawable.ic_agent_support
    )!!.mutate()
    private val plate = RectF()
    private val labelWidth =
        (2 * LABEL_HORIZONTAL_PADDING + ICON_SIZE + ICON_GAP).dp + textPaint.measureText(text)

    override fun getSize(
        paint: Paint,
        text: CharSequence?,
        start: Int,
        end: Int,
        fontMetrics: Paint.FontMetricsInt?
    ): Int = labelWidth.roundToInt() + LABEL_MARGIN_END.dp

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
        val (foreground, background) = when (style) {
            AgentSupportLabelStyle.ACTIVE -> WColor.Tint.color to agentSupportActiveLabelColor
            AgentSupportLabelStyle.MUTED -> WColor.SecondaryText.color to agentSupportPlateColor
        }
        val isRtl = LocaleController.isRTL
        // The plate keeps its margin on the preview's side
        val left = if (isRtl) x + LABEL_MARGIN_END.dp else x
        val centerY = y + (paint.ascent() + paint.descent()) / 2
        plate.set(
            left,
            centerY - LABEL_HEIGHT.dp / 2f,
            left + labelWidth,
            centerY + LABEL_HEIGHT.dp / 2f
        )
        platePaint.color = background
        canvas.drawRoundRect(plate, LABEL_RADIUS.dp, LABEL_RADIUS.dp, platePaint)

        val iconLeft = if (isRtl) {
            plate.right - (LABEL_HORIZONTAL_PADDING + ICON_SIZE).dp
        } else {
            plate.left + LABEL_HORIZONTAL_PADDING.dp
        }
        val iconTop = (centerY - ICON_SIZE.dp / 2f).roundToInt()
        icon.setBounds(
            iconLeft.roundToInt(),
            iconTop,
            iconLeft.roundToInt() + ICON_SIZE.dp,
            iconTop + ICON_SIZE.dp
        )
        icon.setTint(foreground)
        icon.draw(canvas)

        textPaint.color = foreground
        val textLeft = if (isRtl) {
            plate.left + LABEL_HORIZONTAL_PADDING.dp
        } else {
            plate.left + (LABEL_HORIZONTAL_PADDING + ICON_SIZE + ICON_GAP).dp
        }
        canvas.drawText(
            this.text,
            textLeft,
            centerY - (textPaint.ascent() + textPaint.descent()) / 2,
            textPaint
        )
    }
}
