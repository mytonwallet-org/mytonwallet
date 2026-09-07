package org.mytonwallet.app_air.uicomponents.glass

/**
 * Telegram's two blur strengths: 6dp + saturation for pills, 40dp for panels. [FROSTED_PLAIN] is
 * the 40dp blur with no saturation, for pills floating over colorful content.
 */
enum class GlassFlavor { GLASS, FROSTED, FROSTED_PLAIN }

/** Set while a [GlassRoot] records a capture; glass surfaces draw nothing during it. */
object GlassCapture {
    @Volatile
    var capturing = false
        internal set
}
