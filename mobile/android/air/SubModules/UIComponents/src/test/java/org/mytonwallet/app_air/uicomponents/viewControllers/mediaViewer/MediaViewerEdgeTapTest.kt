package org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaViewerEdgeTapTest {
    @Test
    fun sideZonesAreAnEighthOfTheWidthUpTo135Px() {
        assertEquals(100f, mediaViewerEdgeTapSide(800f), 0f)
        assertEquals(135f, mediaViewerEdgeTapSide(1080f), 0f)
        assertEquals(135f, mediaViewerEdgeTapSide(2400f), 0f)
    }

    @Test
    fun tapsInTheSideZonesPageAndOnlyTapsBetweenThemCanZoom() {
        val width = 1080f
        // Paging at once, never half of a double tap
        listOf(0f, 60f, 134.9f, 945.1f, 1020f, 1079f).forEach { x ->
            assertTrue("x = $x", isMediaViewerEdgeTap(x, width))
        }
        // Single taps wait for a second, which zooms
        listOf(135f, 300f, 540f, 945f).forEach { x ->
            assertFalse("x = $x", isMediaViewerEdgeTap(x, width))
        }
    }
}
