package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.google.zxing.qrcode.encoder.ByteMatrix
import com.google.zxing.qrcode.encoder.Encoder
import com.google.zxing.qrcode.encoder.QRCode
import org.mytonwallet.app_air.uicomponents.extensions.dp
import java.util.EnumMap
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min


@SuppressLint("ViewConstructor")
class WQRCodeView(
    context: Context,
    private val qrCode: String,
    private val qWidth: Int,
    private val qHeight: Int,
    private val logoRes: Int,
    private val logoSize: Int,
    private val colorGradient: LinearGradient?
) :
    AppCompatImageView(context) {

    init {
        id = generateViewId()
    }

    var isGenerated = false
        private set

    private var leftPadding: Int = 0
    var topPadding: Int = 0
        private set

    fun generate(onCompletion: (() -> Unit)? = null) {
        val executor = Executors.newSingleThreadExecutor()
        executor.execute {
            val encodingHints: MutableMap<EncodeHintType, Any> =
                EnumMap(com.google.zxing.EncodeHintType::class.java)
            encodingHints[EncodeHintType.CHARACTER_SET] = "UTF-8"
            encodingHints[EncodeHintType.MARGIN] = 0
            val code: QRCode = Encoder.encode(qrCode, ErrorCorrectionLevel.H, encodingHints)
            val bitmap: Bitmap = renderQRImage(
                code, qWidth, qHeight, try {
                    ContextCompat.getDrawable(context, logoRes)
                } catch (t: Throwable) {
                    null
                }, logoSize
            )
            Handler(Looper.getMainLooper()).post {
                setImageBitmap(bitmap)
                isGenerated = true
                onCompletion?.invoke()
            }
        }
    }

    // It's probably not an expensive operation.
    fun generateInUi() {
        val encodingHints: MutableMap<EncodeHintType, Any> =
            EnumMap(com.google.zxing.EncodeHintType::class.java)
        encodingHints[EncodeHintType.CHARACTER_SET] = "UTF-8"
        encodingHints[EncodeHintType.MARGIN] = 0
        val code: QRCode = Encoder.encode(qrCode, ErrorCorrectionLevel.H, encodingHints)
        val bitmap: Bitmap = renderQRImage(
            code, qWidth, qHeight, try {
                ContextCompat.getDrawable(context, logoRes)
            } catch (t: Throwable) {
                null
            }, logoSize, quietZone = 0
        )

        setImageBitmap(bitmap)
        isGenerated = true
    }

    private fun renderQRImage(
        code: QRCode,
        width: Int,
        height: Int,
        logoDrawable: Drawable?,
        logoSize: Int,
        logoPadding: Int = 10.dp,
        quietZone: Int = 4
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // Set up paint for background
        val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.WHITE
        }

        // Draw rounded rectangle background
        val backgroundRect = RectF(0f, 0f, width.toFloat(), height.toFloat())
        canvas.drawRoundRect(backgroundRect, 36f.dp, 36f.dp, backgroundPaint)

        // Set up paint for drawing QR code
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            if (colorGradient != null)
                shader = colorGradient
            else
                color = Color.BLACK
        }

        // Get the QR code matrix
        val input: ByteMatrix = code.matrix ?: throw IllegalStateException()

        // Calculate dimensions
        val inputWidth = input.width
        val inputHeight = input.height
        val qrWidth = inputWidth + (quietZone * 2)
        val qrHeight = inputHeight + (quietZone * 2)
        val outputWidth = max(width, qrWidth)
        val outputHeight = max(height, qrHeight)

        // Calculate scaling factors and padding
        val multiple = min(outputWidth / qrWidth, outputHeight / qrHeight)
        leftPadding = (outputWidth - (inputWidth * multiple)) / 2
        topPadding = (outputHeight - (inputHeight * multiple)) / 2
        val FINDER_PATTERN_SIZE = 7
        val CIRCLE_SCALE_DOWN_FACTOR = 1
        val circleSize = (multiple * CIRCLE_SCALE_DOWN_FACTOR)

        // Iterate through each QR code module
        val centerX = outputWidth / 2
        val centerY = outputHeight / 2
        val halfLogoSizeWithPadding = logoSize / 2 + logoPadding
        fun isInCenter(x: Int, y: Int): Boolean {
            return (x >= centerX - halfLogoSizeWithPadding) && (x <= centerX + halfLogoSizeWithPadding) &&
                (y >= centerY - halfLogoSizeWithPadding) && (y <= centerY + halfLogoSizeWithPadding)
        }
        for (inputY in 0 until inputHeight) {
            val outputY = topPadding + multiple * inputY
            for (inputX in 0 until inputWidth) {
                val outputX = leftPadding + multiple * inputX
                if (input.get(inputX, inputY).toInt() == 1) {
                    val isInCorners =
                        (inputX <= FINDER_PATTERN_SIZE && inputY <= FINDER_PATTERN_SIZE ||
                            inputX >= inputWidth - FINDER_PATTERN_SIZE && inputY <= FINDER_PATTERN_SIZE ||
                            inputX <= FINDER_PATTERN_SIZE && inputY >= inputHeight - FINDER_PATTERN_SIZE)
                    if (!isInCorners && !isInCenter(outputX, outputY)) {
                        canvas.drawOval(
                            RectF(
                                outputX.toFloat(),
                                outputY.toFloat(),
                                (outputX + circleSize).toFloat(),
                                (outputY + circleSize).toFloat()
                            ),
                            paint
                        )
                        // Draw line instead of individual circles if connected
                        if (inputX < inputWidth - 1 &&
                            input.get(inputX + 1, inputY).toInt() == 1 &&
                            !isInCenter(outputX + multiple, outputY)
                        ) {
                            canvas.drawRect(
                                outputX.toFloat() + multiple / 2,
                                outputY.toFloat(),
                                outputX + multiple + multiple / 2f,
                                (outputY + multiple).toFloat(),
                                paint
                            )
                        }
                        if (inputY < inputHeight - 1 &&
                            input.get(inputX, inputY + 1).toInt() == 1 &&
                            !isInCenter(outputX, outputY + multiple)
                        ) {
                            canvas.drawRect(
                                outputX.toFloat(),
                                outputY.toFloat() + multiple / 2,
                                outputX.toFloat() + multiple,
                                outputY + multiple + multiple / 2f,
                                paint
                            )
                        }
                    }
                }
            }
        }

        // Draw finder patterns
        val circleDiameter = multiple * FINDER_PATTERN_SIZE
        drawFinderPatternCircleStyle(canvas, paint, leftPadding, topPadding, circleDiameter)
        drawFinderPatternCircleStyle(
            canvas,
            paint,
            leftPadding + (inputWidth - FINDER_PATTERN_SIZE) * multiple,
            topPadding,
            circleDiameter
        )
        drawFinderPatternCircleStyle(
            canvas,
            paint,
            leftPadding,
            topPadding + (inputHeight - FINDER_PATTERN_SIZE) * multiple,
            circleDiameter
        )

        logoDrawable?.let {
            val x = (qWidth - logoSize) / 2 + 4
            val y = (qHeight - logoSize) / 2 + 4
            it.setBounds(x, y, x + logoSize, y + logoSize)
            it.draw(canvas)
        }
        return bitmap
    }

    private fun drawFinderPatternCircleStyle(
        canvas: Canvas,
        paint: Paint,
        x: Int,
        y: Int,
        circleDiameter: Int
    ) {
        val WHITE_CIRCLE_DIAMETER = circleDiameter * 5 / 7
        val WHITE_CIRCLE_OFFSET = circleDiameter / 7
        val MIDDLE_DOT_DIAMETER = circleDiameter * 3 / 7
        val MIDDLE_DOT_OFFSET = circleDiameter * 2 / 7

        val shaderCache = paint.shader
        canvas.drawOval(
            RectF(
                x.toFloat(),
                y.toFloat(),
                (x + circleDiameter).toFloat(),
                (y + circleDiameter).toFloat()
            ),
            paint
        )

        paint.color = Color.WHITE
        paint.shader = null
        canvas.drawOval(
            RectF(
                (x + WHITE_CIRCLE_OFFSET).toFloat(),
                (y + WHITE_CIRCLE_OFFSET).toFloat(),
                (x + WHITE_CIRCLE_OFFSET + WHITE_CIRCLE_DIAMETER).toFloat(),
                (y + WHITE_CIRCLE_OFFSET + WHITE_CIRCLE_DIAMETER).toFloat()
            ),
            paint
        )
        if (shaderCache != null)
            paint.shader = shaderCache
        else
            paint.color = Color.BLACK

        canvas.drawOval(
            RectF(
                (x + MIDDLE_DOT_OFFSET).toFloat(),
                (y + MIDDLE_DOT_OFFSET).toFloat(),
                (x + MIDDLE_DOT_OFFSET + MIDDLE_DOT_DIAMETER).toFloat(),
                (y + MIDDLE_DOT_OFFSET + MIDDLE_DOT_DIAMETER).toFloat()
            ),
            paint
        )
    }
}
