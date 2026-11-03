package org.mytonwallet.app_air.uicomponents.glass

import android.view.View

/**
 * Telegram's two blur strengths: 6dp + saturation for pills, 40dp for panels. [FROSTED_PLAIN] is
 * the 40dp blur with no saturation, for pills floating over colorful content.
 */
enum class GlassFlavor { GLASS, FROSTED, FROSTED_PLAIN }

/**
 * Set while a glass root records a capture. A [GlassRoot] capture names its [root]: that root's
 * glass surfaces draw nothing during it, while another root's draw as they show, since the display
 * lists the capture records are the ones the frame draws. No glass surface draws during a
 * [GlassRootBitmap] capture, which names none.
 */
object GlassCapture {
    @Volatile
    var capturing = false
        internal set

    @Volatile
    var root: View? = null
        internal set
}
