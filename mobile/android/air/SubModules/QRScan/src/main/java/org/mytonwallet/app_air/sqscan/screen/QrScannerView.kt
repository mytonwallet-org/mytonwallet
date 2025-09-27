package org.mytonwallet.app_air.sqscan.screen

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.util.AttributeSet
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.annotation.OptIn
import androidx.appcompat.widget.AppCompatImageView
import androidx.appcompat.widget.AppCompatTextView
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import me.vkryl.android.util.ClickHelper
import me.vkryl.core.fromTo
import me.vkryl.core.fromToArgb
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.addCircleRect
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setOnClickListener
import org.mytonwallet.app_air.uicomponents.extensions.setView
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

class QrScannerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {
    private val flashlightView = QrScannerToggleFlashlight(context)
    private val flashlightRect = Rect()
    private val blurRender = QrBlur()

    private val closeButtonRect = Rect()
    private val closeBlur = QrBlur()

    private val closeButtonView = AppCompatImageView(context).apply {
        setImageResource(R.drawable.ic_qr_close_12)
        scaleType = ImageView.ScaleType.CENTER
        background = WRippleDrawable.create(15f.dp).apply {
            backgroundColor = QrScannerToggleFlashlight.BACKGROUND_DARK
            rippleColor = 0x10FFFFFF
        }

    }

    private val previewView = PreviewView(context)
    private val previewClickHelper = ClickHelper(object : ClickHelper.Delegate {
        override fun needClickAt(view: View?, x: Float, y: Float): Boolean {
            return true
        }

        override fun onClickAt(view: View?, x: Float, y: Float) {
            previewCamera?.cameraControl?.let {
                val point = previewView.meteringPointFactory.createPoint(x, y)
                val action = FocusMeteringAction.Builder(point).build()
                it.startFocusAndMetering(action)
            }
            view?.performClick()
        }
    })

    private val backgroundPath = Path()
    private val backgroundRectDefault = RectF()
    private val backgroundRect = RectF()
    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = 0x20000000
    }
    private val outlinePath = Path()
    private val outlinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        color = Color.WHITE
    }

    private val titleTextView = AppCompatTextView(context).apply {
        setLineHeight(TypedValue.COMPLEX_UNIT_DIP, 24f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setTextColor(Color.WHITE)
        setText(LocaleController.getString("Scan QR Code"))
        gravity = Gravity.CENTER
        typeface = WFont.Medium.typeface
        maxLines = 1
    }

    private val qrCodeDetectedAnimator =
        BoolAnimator(220L, AnimatorUtils.DECELERATE_INTERPOLATOR, false) { state, value, _, _ ->
            flashlightView.scaleX = 1f - value
            flashlightView.scaleY = 1f - value
            backgroundPaint.color = fromToArgb(0x20000000, 0x7F000000, value)
            rebuildBackgroundPath()
            invalidate()
            if (state == BoolAnimator.State.TRUE) {
                validatedQrCode?.let { qrCode -> delegate.onQrScanComplete(qrCode) }
            }
        }
    private val qrCodeRect = RectF()


    private var validatedQrCode: String? = null

    init {
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        previewView.setOnTouchListener(previewClickHelper::onTouchEvent)

        flashlightView.setOnClickListener(::toggleFlashlight)

        addView(previewView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(flashlightView, LayoutParams(75.dp, 75.dp, Gravity.CENTER_HORIZONTAL))
        addView(
            titleTextView,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                leftMargin = 56.dp
                topMargin = 20.dp
                rightMargin = 56.dp
            })
        addView(closeButtonView, LayoutParams(30.dp, 30.dp, Gravity.TOP or Gravity.RIGHT).apply {
            rightMargin = 16.dp
            topMargin = 16.dp
        })
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val lp = (previewView.layoutParams as? LayoutParams)
        lp?.leftMargin = -paddingLeft
        lp?.topMargin = -paddingTop
        lp?.rightMargin = -paddingRight
        lp?.bottomMargin = -paddingBottom

        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)

        val size = minOf(measuredWidth, measuredHeight) * 0.7f
        val half = size * 0.5f
        val cx = measuredWidth / 2f
        val cy = measuredHeight / 2f

        val freeSpacePart =
            (measuredHeight - size - flashlightView.height - paddingTop - paddingBottom) / 7f

        val y1 = paddingTop + freeSpacePart * 3
        val y2 = y1 + size + freeSpacePart

        backgroundRectDefault.set(cx - half, y1, cx + half, y1 + size)

        val flvX = (measuredWidth - flashlightView.measuredWidth) / 2
        val flvY = y2.roundToInt()
        flashlightView.layout(
            flvX,
            flvY,
            flvX + flashlightView.measuredWidth,
            flvY + flashlightView.measuredHeight
        )

        rebuildBackgroundPath()
    }

    override fun drawChild(canvas: Canvas, child: View?, drawingTime: Long): Boolean {
        val r = super.drawChild(canvas, child, drawingTime)
        if (child == previewView) {
            canvas.drawPath(backgroundPath, backgroundPaint)
            canvas.drawPath(outlinePath, outlinePaint)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                blurRender.draw(canvas, flashlightRect) { super.drawChild(it, child, drawingTime) }
                closeBlur.draw(canvas, closeButtonRect) { super.drawChild(it, child, drawingTime) }
            }
        }

        return r
    }

    private fun rebuildBackgroundPath() {
        backgroundPath.reset()
        backgroundPath.addRect(
            0f,
            0f,
            measuredWidth.toFloat(),
            measuredHeight.toFloat(),
            Path.Direction.CW
        )
        backgroundRect.set(
            fromTo(backgroundRectDefault.left, qrCodeRect.left, qrCodeDetectedAnimator.floatValue),
            fromTo(backgroundRectDefault.top, qrCodeRect.top, qrCodeDetectedAnimator.floatValue),
            fromTo(
                backgroundRectDefault.right,
                qrCodeRect.right,
                qrCodeDetectedAnimator.floatValue
            ),
            fromTo(
                backgroundRectDefault.bottom,
                qrCodeRect.bottom,
                qrCodeDetectedAnimator.floatValue
            )
        )

        val scale = minOf(
            backgroundRect.width() / backgroundRectDefault.width(),
            backgroundRect.height() / backgroundRectDefault.height()
        )
        val radius = 32f.dp * scale
        backgroundPath.addRoundRect(backgroundRect, radius, radius, Path.Direction.CCW)

        flashlightRect.setView(flashlightView)
        if (qrCodeDetectedAnimator.floatValue > 0f) {
            val ox = flashlightRect.centerX()
            val oy = flashlightRect.centerY()
            val s = 1f - qrCodeDetectedAnimator.floatValue
            flashlightRect.offset(-ox, -oy)
            flashlightRect.left = (flashlightRect.left * s).roundToInt()
            flashlightRect.top = (flashlightRect.top * s).roundToInt()
            flashlightRect.right = (flashlightRect.right * s).roundToInt()
            flashlightRect.bottom = (flashlightRect.bottom * s).roundToInt()
            flashlightRect.offset(ox, oy)
        }

        closeButtonRect.setView(closeButtonView)
        backgroundPath.addCircleRect(flashlightRect, Path.Direction.CCW)
        backgroundPath.addCircleRect(closeButtonRect, Path.Direction.CCW)

        val side = 60f.dp * scale
        val l = backgroundRect.left
        val t = backgroundRect.top
        val r = backgroundRect.right
        val b = backgroundRect.bottom

        outlinePaint.strokeWidth = 8f.dp * scale

        outlinePath.reset()
        outlinePath.moveTo(l, t + side)
        outlinePath.lineTo(l, t + radius)
        tmpRect.set(l, t, l + radius * 2, t + radius * 2)
        outlinePath.arcTo(tmpRect, 180f, 90f)
        outlinePath.lineTo(l + side, t)

        outlinePath.moveTo(r - side, t)
        outlinePath.lineTo(r - radius, t)
        tmpRect.set(r - radius * 2, t, r, t + radius * 2)
        outlinePath.arcTo(tmpRect, 270f, 90f)
        outlinePath.lineTo(r, t + side)

        outlinePath.moveTo(r, b - side)
        outlinePath.lineTo(r, b - radius)
        tmpRect.set(r - radius * 2, b - radius * 2, r, b)
        outlinePath.arcTo(tmpRect, 0f, 90f)
        outlinePath.lineTo(r - side, b)

        outlinePath.moveTo(l + side, b)
        outlinePath.lineTo(l + radius, b)
        tmpRect.set(l, b - radius * 2, l + radius * 2, b)
        outlinePath.arcTo(tmpRect, 90f, 90f)
        outlinePath.lineTo(l, b - side)
    }


    /* Lifecycle */

    private val cameraProviderFuture by lazy { ProcessCameraProvider.getInstance(context) }
    private lateinit var lifecycleOwner: LifecycleOwner
    private lateinit var delegate: QrScannerListener
    private lateinit var cameraExecutor: ExecutorService
    private lateinit var barcodeScanner: BarcodeScanner
    private var previewCamera: Camera? = null

    fun init(lifecycleOwner: LifecycleOwner, listener: QrScannerListener) {
        this.lifecycleOwner = lifecycleOwner
        this.delegate = listener

        closeButtonView.setOnClickListener(delegate::onQrScanCancel)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        barcodeScanner = BarcodeScanning.getClient()
        cameraExecutor = Executors.newSingleThreadExecutor()
        previewCamera = null
        cameraProviderFuture.addListener(
            ::startScanningImpl,
            ContextCompat.getMainExecutor(context)
        )
        startScanningImpl()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        cameraExecutor.shutdown()
        barcodeScanner.close()
        previewCamera = null
    }

    private fun startScanningImpl() {
        if (!isAttachedToWindow) {
            return
        }

        previewCamera = try {
            val cameraProvider = cameraProviderFuture.get()

            // CameraX Preview
            val preview = androidx.camera.core.Preview.Builder().build().also {
                it.surfaceProvider = previewView.surfaceProvider
            }

            // CameraX ImageAnalysis
            val imageAnalysis = ImageAnalysis.Builder().build().also {
                it.setAnalyzer(cameraExecutor) { imageProxy -> processImage(imageProxy) }
            }

            // Use the back camera
            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            // rebind
            cameraProvider.unbindAll()
            cameraProvider.bindToLifecycle(
                lifecycleOwner,
                cameraSelector,
                preview,
                imageAnalysis
            )
        } catch (e: Throwable) {
            Log.e(TAG, "Unhandled exception", e)
            null
        }
    }


    /* Scan */

    @OptIn(ExperimentalGetImage::class)
    private fun processImage(imageProxy: androidx.camera.core.ImageProxy) {
        val mediaImage = imageProxy.image ?: return
        val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        barcodeScanner.process(image)
            .addOnSuccessListener { processBarcodes(image, it) }
            .addOnFailureListener { imageProxy.close() }
            .addOnCompleteListener { imageProxy.close() }
    }

    private fun processBarcodes(image: InputImage, barcodes: List<Barcode>) {
        val imageWidth =
            if (image.rotationDegrees == 0 || image.rotationDegrees == 180) image.width else image.height
        val imageHeight =
            if (image.rotationDegrees == 0 || image.rotationDegrees == 180) image.height else image.width

        for (barcode in barcodes) {
            val qrCode = barcode.displayValue ?: continue
            val boundingBox = barcode.boundingBox ?: continue
            if (qrCodeDetectedAnimator.value && qrCode != validatedQrCode) {
                continue
            }

            transformBoundingBoxToScreen(qrCodeRect, boundingBox, imageWidth, imageHeight)
            rebuildBackgroundPath()
            invalidate()

            if (delegate?.onQrScanValidate(qrCode) != false && !qrCodeDetectedAnimator.value) {
                validatedQrCode = qrCode
                qrCodeDetectedAnimator.animatedValue = true
            }
        }
    }

    private fun transformBoundingBoxToScreen(
        out: RectF,
        boundingBox: Rect,
        imageWidth: Int,
        imageHeight: Int
    ) {
        val viewWidth = previewView.width
        val viewHeight = previewView.height

        val scaleX = viewWidth.toFloat() / imageWidth
        val scaleY = viewHeight.toFloat() / imageHeight
        val scale = max(scaleX, scaleY)

        val dx = (viewWidth - imageWidth * scale) / 2
        val dy = (viewHeight - imageHeight * scale) / 2

        val left = boundingBox.left * scale + dx
        val top = boundingBox.top * scale + dy
        val right = boundingBox.right * scale + dx
        val bottom = boundingBox.bottom * scale + dy

        out.set(left, top, right, bottom)
    }

    private fun toggleFlashlight() {
        val isEnabled = flashlightView.toggle()
        previewCamera?.cameraControl?.enableTorch(isEnabled)
    }


    companion object {
        private const val TAG = "QRScannerView"

        private val tmpRect = RectF()
    }
}
