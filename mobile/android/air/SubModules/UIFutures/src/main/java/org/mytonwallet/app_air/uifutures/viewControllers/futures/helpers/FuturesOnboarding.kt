package org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.net.Uri
import android.view.View
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.widgets.stories.StoriesView
import org.mytonwallet.app_air.uicomponents.widgets.stories.StoryPage
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsOnboarding

private const val FINALE_ID = "finale"
private val STORY_IDS =
    listOf("intro", "long", "short", "leverage", "liquidation", "funding", FINALE_ID)

object FuturesOnboarding {
    const val BANNER_ID = "perps-onboarding"

    fun makeStoriesView(window: WWindow, onboarding: MApiPerpsOnboarding?) =
        StoriesView(window, pages(window, onboarding), FuturesStoryBackgroundView(window))

    private fun pages(context: Context, onboarding: MApiPerpsOnboarding?): List<StoryPage> {
        val appName = context.getString(BaseR.string.app_locale_name_key)
        return STORY_IDS.map { id ->
            val key = "PerpsStory" + id.replaceFirstChar(Char::uppercase)
            val story = onboarding?.stories?.firstOrNull { it.id == id }
            val body = if (id == FINALE_ID) {
                LocaleController.getStringWithKeyValues(
                    "${key}Body",
                    listOf("%app_name%" to appName)
                )
            } else {
                LocaleController.getString("${key}Body")
            }
            StoryPage(
                id = id,
                title = LocaleController.getString("${key}Title"),
                body = body,
                buttonTitle = if (id ==
                    FINALE_ID
                ) {
                    LocaleController.getString("PerpsStoryViewMarkets")
                } else {
                    null
                },
                duration = story?.duration ?: 7.0,
                previewFile = story?.let { FuturesStoryMediaCache.cachedFile(context, it.preview) },
                videoUri = story?.let {
                    FuturesStoryMediaCache.cachedFile(context, it.videoUrl)?.let(Uri::fromFile)
                        ?: Uri.parse(it.videoUrl)
                }
            )
        }
    }
}

@SuppressLint("ViewConstructor")
private class FuturesStoryBackgroundView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        shader = RadialGradient(
            0f,
            0f,
            1f,
            Color.argb((0.55f * 255).toInt(), 0xA8, 0xE3, 0xFF),
            Color.argb(0, 0xA8, 0xE3, 0xFF),
            Shader.TileMode.CLAMP
        )
    }
    private val matrix = Matrix()

    override fun onDraw(canvas: Canvas) {
        val scale = width / DESIGN_WIDTH
        val glowWidth = GLOW_WIDTH * scale
        val glowHeight = GLOW_HEIGHT * scale
        val left = (width - glowWidth) / 2
        val top = 0.5f * scale
        matrix.setScale(glowWidth / 2, glowHeight / 2)
        matrix.postTranslate(left + glowWidth / 2, top + glowHeight / 2)
        paint.shader.setLocalMatrix(matrix)
        canvas.drawOval(left, top, left + glowWidth, top + glowHeight, paint)
    }

    private companion object {
        const val DESIGN_WIDTH = 402f
        const val GLOW_WIDTH = 515f
        const val GLOW_HEIGHT = 629f
    }
}
