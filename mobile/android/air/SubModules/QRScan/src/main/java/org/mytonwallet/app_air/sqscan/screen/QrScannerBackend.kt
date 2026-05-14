package org.mytonwallet.app_air.sqscan.screen

import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.mlkit.vision.barcode.BarcodeScanning
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer

data class DecodedBarcode(val displayValue: String, val boundingBox: Rect)

interface QrScannerBackend {
    fun process(
        image: InputImage,
        onResult: (List<DecodedBarcode>) -> Unit,
        onError: (Throwable) -> Unit,
        onComplete: () -> Unit,
    )

    fun close()
}

class MlKitBackend : QrScannerBackend {
    private val scanner = BarcodeScanning.getClient()

    override fun process(
        image: InputImage,
        onResult: (List<DecodedBarcode>) -> Unit,
        onError: (Throwable) -> Unit,
        onComplete: () -> Unit,
    ) {
        scanner.process(image)
            .addOnSuccessListener { barcodes ->
                onResult(barcodes.mapNotNull { it.toDecoded() })
            }
            .addOnFailureListener(onError)
            .addOnCompleteListener { onComplete() }
    }

    override fun close() = scanner.close()

    private fun Barcode.toDecoded(): DecodedBarcode? {
        val value = displayValue ?: return null
        val box = boundingBox ?: return null
        return DecodedBarcode(value, box)
    }
}

class ZXingBackend : QrScannerBackend {
    private val reader = MultiFormatReader().apply {
        setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE)))
    }

    // Decode runs on CameraX's analyzer background thread; downstream view code touches
    // animators that require the main looper. Match MlKit Task semantics by posting
    // result/error/complete callbacks back to the main thread.
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun process(
        image: InputImage,
        onResult: (List<DecodedBarcode>) -> Unit,
        onError: (Throwable) -> Unit,
        onComplete: () -> Unit,
    ) {
        val mainResult: (List<DecodedBarcode>) -> Unit = { res ->
            mainHandler.post { onResult(res) }
        }
        val mainError: (Throwable) -> Unit = { e ->
            mainHandler.post { onError(e) }
        }
        val mainComplete: () -> Unit = {
            mainHandler.post { onComplete() }
        }
        try {
            val mediaImage = image.mediaImage
            if (mediaImage == null) {
                mainResult(emptyList())
                return
            }
            // Strip rowStride padding into a tight width*height grayscale buffer.
            val yPlane = mediaImage.planes[0]
            val rowStride = yPlane.rowStride
            val pixelStride = yPlane.pixelStride
            val srcWidth = mediaImage.width
            val srcHeight = mediaImage.height
            val yBytes = ByteArray(srcWidth * srcHeight)
            val src = yPlane.buffer
            src.rewind()
            val rowBuffer = ByteArray(rowStride)
            for (row in 0 until srcHeight) {
                val rowOffset = row * rowStride
                if (rowOffset >= src.limit()) break
                src.position(rowOffset)
                val bytesThisRow = minOf(rowStride, src.limit() - rowOffset)
                src.get(rowBuffer, 0, bytesThisRow)
                if (pixelStride == 1) {
                    System.arraycopy(
                        rowBuffer, 0, yBytes, row * srcWidth,
                        minOf(srcWidth, bytesThisRow),
                    )
                } else {
                    val maxPixels = minOf(bytesThisRow / pixelStride, srcWidth)
                    for (col in 0 until maxPixels) {
                        yBytes[row * srcWidth + col] = rowBuffer[col * pixelStride]
                    }
                }
            }

            // Rotate so the camera stream is upright (portrait) before binarizing.
            val (rotatedBytes, width, height) = rotateY(
                yBytes, srcWidth, srcHeight, image.rotationDegrees,
            )

            val source = PlanarYUVLuminanceSource(
                rotatedBytes, width, height, 0, 0, width, height, false,
            )
            val bitmap = BinaryBitmap(HybridBinarizer(source))
            val result = try {
                reader.decodeWithState(bitmap)
            } catch (_: NotFoundException) {
                null
            } catch (t: Throwable) {
                Logger.d(
                    Logger.LogTag.QR_SCAN,
                    "Unexpected decode error: ${Log.getStackTraceString(t)}",
                )
                null
            } finally {
                reader.reset()
            }
            if (result == null) {
                mainResult(emptyList())
                return
            }

            val box = boundingBoxFromPoints(result.resultPoints, width, height)
            mainResult(listOf(DecodedBarcode(result.text, box)))
        } catch (t: Throwable) {
            mainError(t)
        } finally {
            mainComplete()
        }
    }

    private fun rotateY(
        src: ByteArray,
        width: Int,
        height: Int,
        rotationDegrees: Int,
    ): Triple<ByteArray, Int, Int> {
        return when (rotationDegrees % 360) {
            0 -> Triple(src, width, height)
            90 -> {
                val out = ByteArray(src.size)
                for (y in 0 until height) {
                    for (x in 0 until width) {
                        out[x * height + (height - 1 - y)] = src[y * width + x]
                    }
                }
                Triple(out, height, width)
            }

            180 -> {
                val out = ByteArray(src.size)
                val total = width * height
                for (i in 0 until total) {
                    out[i] = src[total - 1 - i]
                }
                Triple(out, width, height)
            }

            270 -> {
                val out = ByteArray(src.size)
                for (y in 0 until height) {
                    for (x in 0 until width) {
                        out[(width - 1 - x) * height + y] = src[y * width + x]
                    }
                }
                Triple(out, height, width)
            }

            else -> Triple(src, width, height)
        }
    }

    override fun close() {}

    private fun boundingBoxFromPoints(
        points: Array<com.google.zxing.ResultPoint>?,
        imageWidth: Int,
        imageHeight: Int,
    ): Rect {
        if (points.isNullOrEmpty()) {
            return Rect(0, 0, imageWidth, imageHeight)
        }
        var minX = Float.MAX_VALUE
        var minY = Float.MAX_VALUE
        var maxX = -Float.MAX_VALUE
        var maxY = -Float.MAX_VALUE
        for (p in points) {
            if (p.x < minX) minX = p.x
            if (p.y < minY) minY = p.y
            if (p.x > maxX) maxX = p.x
            if (p.y > maxY) maxY = p.y
        }
        val pad = 0.05f * (maxX - minX).coerceAtLeast(maxY - minY)
        return Rect(
            (minX - pad).toInt().coerceAtLeast(0),
            (minY - pad).toInt().coerceAtLeast(0),
            (maxX + pad).toInt().coerceAtMost(imageWidth),
            (maxY + pad).toInt().coerceAtMost(imageHeight),
        )
    }
}
