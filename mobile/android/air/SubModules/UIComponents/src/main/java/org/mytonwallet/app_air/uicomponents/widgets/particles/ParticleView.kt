package org.mytonwallet.app_air.uicomponents.widgets.particles

import android.content.Context
import android.graphics.PixelFormat
import android.opengl.GLSurfaceView
import android.util.AttributeSet
import android.view.ViewGroup

class ParticleView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : GLSurfaceView(context, attrs) {

    private val renderer: ParticleRenderer = ParticleRenderer()
    private val systemIds = mutableListOf<String>()

    init {
        // Configure OpenGL ES 2.0
        setEGLContextClientVersion(2)

        // Use solid background instead of transparency
        setZOrderOnTop(false)  // Respect normal z-ordering
        setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        holder.setFormat(PixelFormat.OPAQUE)

        // Set renderer
        renderer.setDisplayDensity(context.resources.displayMetrics.density)
        setRenderer(renderer)

        // Render continuously for animations
        renderMode = RENDERMODE_CONTINUOUSLY
    }

    fun addParticleSystem(config: ParticleConfig = ParticleConfig()): () -> Unit {
        val systemId = renderer.addSystem(config)
        systemIds.add(systemId)

        // Update view size if needed
        updateViewSize(config)

        // Return cleanup function
        return {
            removeParticleSystem(systemId)
        }
    }

    fun removeParticleSystem(systemId: String) {
        renderer.removeSystem(systemId)
        systemIds.remove(systemId)

        if (systemIds.isEmpty()) {
            requestRender()
        }
    }

    fun clearAllSystems() {
        renderer.clearAllSystems()
        systemIds.clear()
        requestRender()
    }

    /**
     * Sets the background color of the particle view.
     * @param color The color in ARGB format (e.g., 0xFFFFFFFF for white)
     */
    fun setParticleBackgroundColor(color: Int) {
        val r = ((color shr 16) and 0xFF) / 255f
        val g = ((color shr 8) and 0xFF) / 255f
        val b = (color and 0xFF) / 255f
        val a = ((color shr 24) and 0xFF) / 255f

        renderer.setBackgroundColor(r, g, b, a)
        requestRender()
    }

    private fun updateViewSize(config: ParticleConfig) {
        post {
            val params = layoutParams ?: ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )

            // Update size based on config
            val density = context.resources.displayMetrics.density
            params.width = (config.width * density).toInt()
            params.height = (config.height * density).toInt()

            layoutParams = params
        }
    }

    override fun onPause() {
        super.onPause()
        renderMode = RENDERMODE_WHEN_DIRTY
    }

    override fun onResume() {
        super.onResume()
        if (systemIds.isNotEmpty()) {
            renderMode = RENDERMODE_CONTINUOUSLY
        }
    }

    companion object {
        // Convenience method to create with default TON particles
        fun createTonParticles(context: Context): ParticleView {
            return ParticleView(context).apply {
                addParticleSystem(
                    ParticleConfig(
                        color = ParticleConfig.Companion.PARTICLE_COLORS.TON
                    )
                )
            }
        }

        // Convenience method to create with USDT particles
        fun createUsdtParticles(context: Context): ParticleView {
            return ParticleView(context).apply {
                addParticleSystem(
                    ParticleConfig(
                        color = ParticleConfig.Companion.PARTICLE_COLORS.USDT
                    )
                )
            }
        }

        // Convenience method to create with MY particles
        fun createMyParticles(context: Context): ParticleView {
            return ParticleView(context).apply {
                addParticleSystem(
                    ParticleConfig(
                        color = ParticleConfig.Companion.PARTICLE_COLORS.MY
                    )
                )
            }
        }
    }
}
