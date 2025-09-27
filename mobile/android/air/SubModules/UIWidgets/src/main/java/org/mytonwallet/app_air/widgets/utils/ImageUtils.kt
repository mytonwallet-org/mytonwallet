package org.mytonwallet.app_air.widgets.utils

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.PorterDuff
import androidx.annotation.DrawableRes
import androidx.core.content.ContextCompat
import androidx.core.graphics.createBitmap

object ImageUtils {
    fun getTintedBitmap(
        context: Context,
        @DrawableRes drawableId: Int,
        color: Int
    ): Bitmap? {
        var drawable = ContextCompat.getDrawable(context, drawableId)
        if (drawable == null) return null

        drawable = drawable.mutate()
        drawable.setColorFilter(color, PorterDuff.Mode.SRC_IN)

        val bitmap = createBitmap(drawable.intrinsicWidth, drawable.intrinsicHeight)

        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)

        return bitmap
    }

}
