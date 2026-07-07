package org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.view.Gravity
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.uisettings.viewControllers.mintCard.MintCardVideoCache
import org.mytonwallet.app_air.walletcore.MTW_CARDS_MINT_BASE_URL
import org.mytonwallet.app_air.walletcore.models.MCardInfo
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import androidx.core.graphics.toColorInt
import androidx.core.net.toUri
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import kotlin.math.roundToInt
import androidx.core.graphics.createBitmap

@SuppressLint("ViewConstructor")
class MintCardPosterView(context: Context) : FrameLayout(context) {

    companion object {
        private const val CROP_FOCUS_Y = 0.73f

        private const val MIRROR_SCALE = 0.1f
        private const val MIRROR_FRAME_STRIDE = 3

        private val videoEnabled: Boolean
            get() = WGlobalStorage.getAreAnimationsActive()

        private fun slideBackgroundColor(type: ApiMtwCardType): Int {
            return when (type) {
                ApiMtwCardType.STANDARD -> "#1D2033".toColorInt()
                ApiMtwCardType.BLACK -> "#030303".toColorInt()
                else -> "#181818".toColorInt()
            }
        }
    }

    private val blurEnabled = WGlobalStorage.isBlurEnabled()

    private var type: ApiMtwCardType? = null
    private var videoPrepared = false

    private val placeholderView = WView(context)

    private var mediaPlayer: MediaPlayer? = null
    private var surface: Surface? = null
    private var wantsToPlay = false
    private var wantsToPrepare = false

    private val blurSourceContainer = FrameLayout(context)
    private val blurSourceView = ImageView(context).apply {
        scaleType = ImageView.ScaleType.FIT_XY
    }
    private var blurSample: Bitmap? = null

    private var mirrorFrameCounter = 0

    private val textureView: TextureView? = if (blurEnabled) TextureView(context).apply {
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

            override fun onSurfaceTextureUpdated(st: SurfaceTexture) {
                mirrorFrameForBlur()
            }
        }
    } else null

    private val surfaceView: SurfaceView? = if (blurEnabled) null else SurfaceView(context).apply {
        alpha = 0f
        // Lift above the window background so the placeholder shows through before playback,
        // while later siblings (poster overlay, labels) still render on top.
        setZOrderMediaOverlay(true)
        holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(h: SurfaceHolder) {
                surface = h.surface
                mediaPlayer?.setSurface(surface)
                maybePrepareVideo()
            }

            override fun surfaceChanged(h: SurfaceHolder, f: Int, w: Int, ht: Int) {}

            override fun surfaceDestroyed(h: SurfaceHolder) {
                surface = null
            }
        })
    }

    private val videoView: View = textureView ?: surfaceView!!

    private fun mirrorFrameForBlur() {
        if (!blurEnabled) return
        if (mirrorFrameCounter++ % MIRROR_FRAME_STRIDE != 0 && videoView.alpha == 1f) return
        val vw = videoView.width
        val vh = videoView.height
        val tv = textureView ?: return
        if (vw <= 0 || vh <= 0 || !tv.isAvailable) return
        val scale = MIRROR_SCALE
        val sw = (vw * scale).roundToInt().coerceAtLeast(1)
        val sh = (vh * scale).roundToInt().coerceAtLeast(1)
        var sample = blurSample
        if (sample == null || sample.width != sw || sample.height != sh) {
            sample?.recycle()
            sample = createBitmap(sw, sh)
            blurSample = sample
        }
        val captured = tv.getBitmap(sample)
        blurSourceView.setImageBitmap(captured)
        blurSourceView.invalidate()
    }

    private var pendingVideoW = 0
    private var pendingVideoH = 0

    private fun coverScaleVideo(videoWidth: Int, videoHeight: Int) {
        pendingVideoW = videoWidth
        pendingVideoH = videoHeight
        val boxW = videoContainer.width
        val boxH = videoContainer.height
        if (boxW <= 0 || boxH <= 0 || videoWidth <= 0 || videoHeight <= 0) {
            videoView.alpha = 0f
            return
        }
        val coverScale = maxOf(boxW.toFloat() / videoWidth, boxH.toFloat() / videoHeight)
        val targetW = (videoWidth * coverScale).roundToInt()
        val targetH = (videoHeight * coverScale).roundToInt()
        val lm = ((boxW - targetW) / 2f).roundToInt()
        val tm = ((boxH - targetH) * CROP_FOCUS_Y).roundToInt()
        videoView.layoutParams = (videoView.layoutParams as LayoutParams).apply {
            gravity = Gravity.NO_GRAVITY
            width = targetW
            height = targetH
            leftMargin = lm
            topMargin = tm
        }
        videoView.requestLayout()
    }

    // Re-fits the video whenever its own size actually changes (e.g. after a rotation wide <-> phone).
    // onSizeChanged only fires on real size changes, so this is free on ordinary layout passes.
    private val videoContainer = object : FrameLayout(context) {
        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            if (pendingVideoW > 0 && pendingVideoH > 0) {
                coverScaleVideo(pendingVideoW, pendingVideoH)
            }
        }
    }.apply {
        clipChildren = true
        clipToPadding = true
    }

    private val posterOverlay = WView(context).apply {
        alpha = 0.18f
        setBackgroundColor(Color.BLACK, 0f)
    }

    private val typeLabel = WLabel(context).apply {
        setStyle(22f, WFont.Medium)
        setTextColor(Color.WHITE)
        gravity = Gravity.CENTER
    }

    private val availabilityView = MintCardAvailabilityView(context)

    private val bottomStack = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
    }

    init {
        // Dots live in the parent VC as a single shared indicator; the poster only shows the
        // card-specific name + availability.
        bottomStack.addView(
            typeLabel,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )
        bottomStack.addView(
            availabilityView,
            LinearLayout.LayoutParams(MATCH_PARENT, 30.dp).apply { topMargin = 10.dp }
        )

        videoContainer.addView(
            videoView,
            LayoutParams(MATCH_PARENT, MATCH_PARENT).apply { gravity = Gravity.CENTER }
        )
        blurSourceContainer.addView(
            blurSourceView,
            LayoutParams(MATCH_PARENT, MATCH_PARENT).apply { gravity = Gravity.CENTER }
        )
        addView(blurSourceContainer, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(placeholderView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(videoContainer, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(posterOverlay, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(
            bottomStack,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.BOTTOM
                leftMargin = 32.dp
                rightMargin = 32.dp
                bottomMargin = 16.dp
            }
        )
    }

    private var blurConfigured = false
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (!blurConfigured) {
            blurConfigured = true
            availabilityView.setupBlur(blurSourceContainer)
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY)
        )
    }

    fun configure(type: ApiMtwCardType, title: String, cardInfo: MCardInfo?) {
        this.type = type
        typeLabel.text = title
        val bg = slideBackgroundColor(type)
        placeholderView.setBackgroundColor(bg, 0f)
        if (blurEnabled) blurSourceContainer.setBackgroundColor(bg)
        availabilityView.configure(cardInfo)
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
                if (w > 0 && h > 0) coverScaleVideo(w, h)
            }
            setOnPreparedListener { mp ->
                videoPrepared = true
                coverScaleVideo(mp.videoWidth, mp.videoHeight)
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
        // Hide the surface so it can't bleed over the current page (placeholder shows through).
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
        blurSample?.recycle()
        blurSample = null
        blurSourceView.setImageBitmap(null)
    }
}
