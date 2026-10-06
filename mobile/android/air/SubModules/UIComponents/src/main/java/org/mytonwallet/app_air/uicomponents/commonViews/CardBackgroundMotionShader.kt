package org.mytonwallet.app_air.uicomponents.commonViews

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.TIRAMISU)
internal class CardBackgroundMotionShader(private val image: Bitmap, phase: Float) {
    private val shader = RuntimeShader(CODE).apply {
        setInputShader(
            "artwork",
            BitmapShader(image, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply {
                setFilterMode(BitmapShader.FILTER_MODE_LINEAR)
            }
        )
        setFloatUniform("size", image.width.toFloat(), image.height.toFloat())
        setFloatUniform("phase", phase)
    }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        shader =
            this@CardBackgroundMotionShader.shader
    }

    fun draw(canvas: Canvas, time: Double, strength: Float) {
        shader.setFloatUniform("time", time.toFloat())
        shader.setFloatUniform("amount", 15f * strength)
        canvas.drawRect(0f, 0f, image.width.toFloat(), image.height.toFloat(), paint)
    }

    companion object {
        private const val CODE = """
            uniform shader artwork;
            uniform float2 size;
            uniform float time;
            uniform float amount;
            uniform float phase;

            half4 main(float2 position) {
                float2 uv = position / max(size, float2(1.0));
                float2 edge = sin(3.14159265359 * clamp(uv, 0.0, 1.0));
                float envelope = edge.x * edge.y;
                float2 wave = float2(
                    sin(time * 0.7 + uv.y * 5.0 + phase) - sin(uv.y * 5.0 + phase),
                    sin(time * 0.53 + uv.x * 4.0 + phase) - sin(uv.x * 4.0 + phase)
                );
                return artwork.eval(position + wave * envelope * amount * size.x / 400.0);
            }
        """
    }
}
