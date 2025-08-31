package org.mytonwallet.app_air.sqscan.screen

import android.graphics.Canvas
import android.graphics.Path
import android.graphics.Rect
import android.graphics.Shader
import android.os.Build
import org.mytonwallet.app_air.uicomponents.extensions.dp

class QrBlur {
    private val path = Path()
    private val node by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            android.graphics.RenderNode("blur").apply {
                setHasOverlappingRendering(false)
                setRenderEffect(
                    android.graphics.RenderEffect.createBlurEffect(
                        12f.dp,
                        12f.dp,
                        Shader.TileMode.CLAMP
                    )
                )
            }
        } else {
            null
        }
    }

    fun draw(canvas: Canvas, position: Rect, callback: ((Canvas) -> Unit)): Boolean {
        if (position.width() == 0 || position.height() == 0) {
            return false
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val node = node ?: return false

            node.setPosition(position)
            path.reset()
            path.addCircle(
                position.exactCenterX(),
                position.exactCenterY(),
                maxOf(position.width(), position.height()) / 2f,
                Path.Direction.CW
            )

            val recordingCanvas = node.beginRecording()
            recordingCanvas.save()
            try {
                recordingCanvas.translate(-position.left.toFloat(), -position.top.toFloat())
                callback.invoke(recordingCanvas)
            } finally {
                recordingCanvas.restore()
                node.endRecording()
            }

            canvas.save()
            canvas.clipPath(path)
            canvas.drawRenderNode(node)
            canvas.restore()

            return true
        }

        return false
    }
}
