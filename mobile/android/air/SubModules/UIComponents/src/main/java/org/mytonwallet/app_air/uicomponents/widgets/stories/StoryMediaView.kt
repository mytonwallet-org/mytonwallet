package org.mytonwallet.app_air.uicomponents.widgets.stories

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.graphics.SurfaceTexture
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.media.MediaPlayer
import android.view.Surface
import android.view.TextureView
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import android.widget.ImageView
import kotlin.math.max
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
internal class StoryMediaView(context: Context, page: StoryPage) : FrameLayout(context) {
    private val videoUri = page.videoUri?.takeIf {
        it.scheme?.lowercase() in setOf("file", "https", "http")
    }
    private val preview: Drawable? = page.previewFile
        ?.let { BitmapFactory.decodeFile(it.path) }
        ?.let { BitmapDrawable(resources, it) }

    private var player: MediaPlayer? = null
    private var surface: Surface? = null
    private var isPrepared = false
    private var hasFirstFrame = false
    private var hasFailed = false
    private var isReducedMotion = !WGlobalStorage.getAreAnimationsActive()
    private var isPlaybackRequested = false
    private var isPreparationRequested = false
    private var imageTargetAlpha = if (isImageNeeded) 1f else 0f
    private var videoWidth = 0
    private var videoHeight = 0

    private val videoView = TextureView(context).apply {
        surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(
                texture: SurfaceTexture,
                width: Int,
                height: Int
            ) {
                surface = Surface(texture)
                player?.setSurface(surface)
                preparePlayer()
            }

            override fun onSurfaceTextureSizeChanged(
                texture: SurfaceTexture,
                width: Int,
                height: Int
            ) {
                updateVideoTransform()
            }

            override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
                player?.setSurface(null)
                surface?.release()
                surface = null
                return true
            }

            override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {}
        }
    }

    private val imageView = ImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
        setImageDrawable(preview)
        alpha = imageTargetAlpha
    }

    /** `null` shows the whole view. */
    var sweepOffset: Float? = null
        set(value) {
            field = value
            invalidate()
        }
    var isSweepRTL = false
    private val sweepPaint = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN) }
    private val sweepMatrix = Matrix()
    private var sweepShader: LinearGradient? = null

    val isWaitingForFirstFrame: Boolean
        get() = videoUri != null && !hasFailed && !isReducedMotion && !hasFirstFrame

    init {
        isClickable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        addView(videoView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(imageView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    fun setPlaying(isPlaying: Boolean) {
        isReducedMotion = !WGlobalStorage.getAreAnimationsActive()
        isPlaybackRequested = isPlaying && !isReducedMotion
        if (isPlaybackRequested) preparePlayback()
        updateVideoVisibility()
    }

    fun preparePlayback() {
        if (isReducedMotion) return
        isPreparationRequested = true
        preparePlayer()
    }

    fun release() {
        isPlaybackRequested = false
        isPreparationRequested = false
        player?.release()
        player = null
        isPrepared = false
    }

    override fun onDetachedFromWindow() {
        release()
        super.onDetachedFromWindow()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        if (changed) {
            sweepShader = null
            updateVideoTransform()
        }
    }

    override fun dispatchDraw(canvas: Canvas) {
        val offset = sweepOffset
        if (offset == null || width == 0) {
            super.dispatchDraw(canvas)
            return
        }
        val layer = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
        super.dispatchDraw(canvas)
        val shader = sweepShader ?: makeSweepShader().also { sweepShader = it }
        sweepMatrix.setTranslate(offset, 0f)
        shader.setLocalMatrix(sweepMatrix)
        sweepPaint.shader = shader
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), sweepPaint)
        canvas.restoreToCount(layer)
    }

    private fun makeSweepShader(): LinearGradient {
        val length = width * 4f
        val colors = intArrayOf(Color.TRANSPARENT, Color.WHITE, Color.WHITE)
        val positions = floatArrayOf(0f, 0.75f, 1f)
        return if (isSweepRTL) {
            LinearGradient(length, 0f, 0f, 0f, colors, positions, Shader.TileMode.CLAMP)
        } else {
            LinearGradient(0f, 0f, length, 0f, colors, positions, Shader.TileMode.CLAMP)
        }
    }

    private fun preparePlayer() {
        val uri = videoUri ?: return
        if (player != null || hasFailed || !isPreparationRequested) return
        val surface = surface ?: return
        val player = MediaPlayer()
        this.player = player
        player.setSurface(surface)
        player.setVolume(0f, 0f)
        player.setOnVideoSizeChangedListener { _, width, height ->
            videoWidth = width
            videoHeight = height
            updateVideoTransform()
        }
        player.setOnPreparedListener {
            isPrepared = true
            updateVideoVisibility()
        }
        player.setOnInfoListener { _, what, _ ->
            if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) {
                hasFirstFrame = true
                updateVideoVisibility()
            }
            false
        }
        player.setOnErrorListener { _, _, _ ->
            stopVideo()
            true
        }
        try {
            player.setDataSource(context, uri)
            player.prepareAsync()
        } catch (_: Exception) {
            stopVideo()
        }
    }

    private fun updateVideoVisibility() {
        setImageVisible(isImageNeeded)
        val player = player ?: return
        if (!isPrepared) return
        if (isPlaybackRequested && !hasFailed) {
            if (!player.isPlaying) player.start()
        } else if (player.isPlaying) {
            player.pause()
        }
    }

    private val isImageNeeded: Boolean
        get() = videoUri == null || hasFailed || isReducedMotion

    private fun setImageVisible(isVisible: Boolean) {
        val alpha = if (isVisible) 1f else 0f
        if (imageTargetAlpha == alpha) return
        imageTargetAlpha = alpha
        imageView.animate().cancel()
        if (WGlobalStorage.getAreAnimationsActive()) {
            imageView.animate().alpha(alpha).setDuration(IMAGE_FADE_DURATION).start()
        } else {
            imageView.alpha = alpha
        }
    }

    private fun stopVideo() {
        hasFailed = true
        setImageVisible(true)
        player?.release()
        player = null
        isPrepared = false
    }

    private fun updateVideoTransform() {
        if (videoWidth <= 0 || videoHeight <= 0 || width == 0 || height == 0) return
        val scale = max(width / videoWidth.toFloat(), height / videoHeight.toFloat())
        val matrix = Matrix()
        matrix.setScale(
            videoWidth * scale / width,
            videoHeight * scale / height,
            width / 2f,
            height / 2f
        )
        videoView.setTransform(matrix)
    }

    private companion object {
        const val IMAGE_FADE_DURATION = 200L
    }
}
