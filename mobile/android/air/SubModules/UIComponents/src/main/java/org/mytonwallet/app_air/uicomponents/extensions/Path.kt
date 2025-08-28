package org.mytonwallet.app_air.uicomponents.extensions

import android.graphics.Path
import android.graphics.Rect

fun Path.addCircleRect(r: Rect, dir: Path.Direction) {
    this.addCircle(r.exactCenterX(), r.exactCenterY(), maxOf(r.width(), r.height()) / 2f, dir)
}
