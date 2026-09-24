package org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.core.graphics.toColorInt
import androidx.core.net.toUri
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.R
import org.mytonwallet.app_air.uisettings.viewControllers.mintCard.MintCardVideoCache
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.MTW_CARDS_MINT_BASE_URL
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType

@SuppressLint("ViewConstructor")
class MintCardPosterView(context: Context) : FrameLayout(context) {

    companion object {
        private const val CROP_FOCUS_Y = 0.73f

        private val videoEnabled: Boolean
            get() = WGlobalStorage.getAreAnimationsActive()

        private fun slideBackgroundColor(type: ApiMtwCardType): Int = when (type) {
            ApiMtwCardType.STANDARD -> "#1D2033".toColorInt()
            ApiMtwCardType.BLACK -> "#030303".toColorInt()
            else -> "#181818".toColorInt()
        }

        private fun posterRes(type: ApiMtwCardType): Int = when (type) {
            ApiMtwCardType.STANDARD -> R.drawable.mtw_card_standard_poster
            ApiMtwCardType.SILVER -> R.drawable.mtw_card_silver_poster
            ApiMtwCardType.GOLD -> R.drawable.mtw_card_gold_poster
            ApiMtwCardType.PLATINUM -> R.drawable.mtw_card_platinum_poster
            ApiMtwCardType.BLACK -> R.drawable.mtw_card_black_poster
        }
    }

    private var type: ApiMtwCardType? = null
    private var videoPrepared = false

    private val placeholderView = WView(context)
    private val posterView = ImageView(context)

    private var mediaPlayer: MediaPlayer? = null
    private var surface: Surface? = null
    private var wantsToPlay = false
    private var wantsToPrepare = false

    private val videoView = TextureView(context).apply {
        alpha = 0f
        surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) {
                surface = Surface(st)
                mediaPlayer?.setSurface(surface)
                maybePrepareVideo()
            }

            override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {}

            override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
                surface?.release()
                surface = null
                return true
            }

            override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
        }
    }

    private var pendingVideoW = 0
    private var pendingVideoH = 0

    private fun updateVideoSize(videoWidth: Int, videoHeight: Int) {
        if (videoWidth <= 0 || videoHeight <= 0) return
        if (pendingVideoW == videoWidth && pendingVideoH == videoHeight) return
        pendingVideoW = videoWidth
        pendingVideoH = videoHeight
        requestLayout()
    }

    private fun setCoverBounds(view: View, width: Int, height: Int, left: Int, top: Int) {
        val params = view.layoutParams as LayoutParams
        if (params.width == width && params.height == height &&
            params.leftMargin == left && params.topMargin == top &&
            params.gravity == Gravity.NO_GRAVITY
        ) {
            return
        }
        params.gravity = Gravity.NO_GRAVITY
        params.width = width
        params.height = height
        params.leftMargin = left
        params.topMargin = top
        view.layoutParams = params
    }

    private fun coverScaleVideo(videoWidth: Int, videoHeight: Int, boxW: Int, boxH: Int) {
        val coverScale = maxOf(boxW.toFloat() / videoWidth, boxH.toFloat() / videoHeight)
        val targetW = (videoWidth * coverScale).roundToInt()
        val targetH = (videoHeight * coverScale).roundToInt()
        val lm = ((boxW - targetW) / 2f).roundToInt()
        val tm = ((boxH - targetH) * CROP_FOCUS_Y).roundToInt()
        setCoverBounds(videoView, targetW, targetH, lm, tm)
    }

    private val videoContainer = FrameLayout(context).apply {
        clipChildren = true
        clipToPadding = true
    }

    private val posterOverlay = WView(context).apply {
        alpha = 0.18f
        setBackgroundColor(Color.BLACK, 0f)
    }

    init {
        videoContainer.addView(
            videoView,
            LayoutParams(MATCH_PARENT, MATCH_PARENT).apply { gravity = Gravity.CENTER }
        )
        addView(placeholderView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(posterView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(videoContainer, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(posterOverlay, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        if (width > 0) {
            val posterHeight = (width * 750f / 540f).roundToInt()
            val posterTop = ((width - posterHeight) * CROP_FOCUS_Y).roundToInt()
            setCoverBounds(posterView, width, posterHeight, 0, posterTop)
        }
        // Size the video before its container measures children, using this pass's poster width.
        if (width > 0 && pendingVideoW > 0 && pendingVideoH > 0) {
            coverScaleVideo(pendingVideoW, pendingVideoH, width, width)
        }
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY)
        )
    }

    fun configure(type: ApiMtwCardType) {
        if (this.type != type) {
            releaseVideo()
            posterView.setImageResource(posterRes(type))
        }
        this.type = type
        val bg = slideBackgroundColor(type)
        placeholderView.setBackgroundColor(bg, 0f)
    }

    fun prepareVideo() {
        type ?: return
        if (!videoEnabled) return
        wantsToPrepare = true
        maybePrepareVideo()
    }

    fun playVideo() {
        type ?: return
        if (!videoEnabled) return
        if (wantsToPlay && mediaPlayer?.isPlaying == true) return
        wantsToPlay = true
        wantsToPrepare = true
        videoContainer.visibility = VISIBLE
        if (videoPrepared) {
            try {
                mediaPlayer?.start()
            } catch (_: IllegalStateException) {
                releaseVideo()
                wantsToPlay = true
                wantsToPrepare = true
                videoContainer.visibility = VISIBLE
                maybePrepareVideo()
            }
        } else {
            maybePrepareVideo()
        }
    }

    private fun maybePrepareVideo() {
        val type = type ?: return
        if (videoPrepared || mediaPlayer != null) return
        if (surface == null || (!wantsToPlay && !wantsToPrepare)) return
        val player = MediaPlayer().apply {
            setSurface(surface)
            isLooping = true
            setVolume(0f, 0f)
            setOnVideoSizeChangedListener { _, w, h ->
                updateVideoSize(w, h)
            }
            setOnPreparedListener { mp ->
                videoPrepared = true
                updateVideoSize(mp.videoWidth, mp.videoHeight)
                if (wantsToPlay) mp.start()
            }
            setOnInfoListener { _, what, _ ->
                if (what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) {
                    videoView.fadeIn()
                }
                false
            }
            setOnErrorListener { _, _, _ ->
                releaseVideo()
                true
            }
        }
        mediaPlayer = player
        try {
            // Prefer the on-disk cache (instant, offline); fall back to streaming the remote URL.
            val cached = MintCardVideoCache.cachedFile(context, type)
            if (cached != null) {
                player.setDataSource(cached.absolutePath)
            } else {
                player.setDataSource(
                    context,
                    "${MTW_CARDS_MINT_BASE_URL}mtw_card_${type.name.lowercase()}.h264.mp4".toUri()
                )
            }
            player.prepareAsync()
        } catch (_: Exception) {
            videoContainer.visibility = INVISIBLE
            releaseVideo()
        }
    }

    fun stopVideo() {
        wantsToPlay = false
        mediaPlayer?.let { if (it.isPlaying) it.pause() }
        // Hide the surface so the poster shows through.
        videoContainer.visibility = INVISIBLE
    }

    fun releaseVideo() {
        wantsToPlay = false
        wantsToPrepare = false
        mediaPlayer?.let {
            try {
                it.stop()
            } catch (_: IllegalStateException) {
            }
            it.release()
        }
        mediaPlayer = null
        videoPrepared = false
        pendingVideoW = 0
        pendingVideoH = 0
        videoContainer.scaleX = 1f
        videoContainer.scaleY = 1f
        videoContainer.translationY = 0f
        videoContainer.visibility = INVISIBLE
        videoView.alpha = 0f
    }
}
