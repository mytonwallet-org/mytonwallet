package org.mytonwallet.app_air.uicomponents.commonViews

import org.mytonwallet.app_air.uicomponents.commonViews.cardMotion.CardSurfaceLight

internal data class CardSurfaceFrame(
    val width: Float,
    val height: Float,
    val density: Float,
    val lineTime: Double,
    val blobTime: Double,
    val light: CardSurfaceLight,
    val touchExtent: Float = 0f
) {
    data class BackgroundKey(
        val width: Float,
        val height: Float,
        val density: Float,
        val time: Float,
        val blobTime: Float,
        val tiltX: Float,
        val tiltY: Float,
        val touchX: Float,
        val touchY: Float,
        val touchOpacity: Float,
        val touchExtent: Float,
        val gramAngle: Float,
        val gramEnergy: Float
    )

    fun backgroundKey(movingArtwork: Boolean, blobs: Boolean): BackgroundKey = BackgroundKey(
        width, height, density,
        if (movingArtwork) lineTime.toFloat() else 0f,
        if (blobs) blobTime.toFloat() else 0f,
        (light.border?.x ?: light.x).toFloat(),
        (light.border?.y ?: light.y).toFloat(),
        light.touch?.position?.x?.toFloat() ?: 0f,
        light.touch?.position?.y?.toFloat() ?: 0f,
        light.touch?.opacity?.toFloat() ?: 0f,
        touchExtent,
        light.gram?.rotation?.toFloat() ?: 0f,
        light.gram?.energy?.toFloat() ?: 1f
    )
}
