package org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer

import java.util.Calendar
import java.util.Date
import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.BeforeClass
import org.junit.Test
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

class MediaViewerChromeTest {
    private val now = date(2026, Calendar.OCTOBER, 29, 3, 40)
    private val formatTime: (Date) -> String = { date ->
        val calendar = Calendar.getInstance().apply { time = date }
        "%d:%02d".format(calendar.get(Calendar.HOUR_OF_DAY), calendar.get(Calendar.MINUTE))
    }
    private val formatDay: (Date, Boolean) -> String = { date, withYear ->
        val calendar = Calendar.getInstance().apply { time = date }
        val day = "${calendar.get(Calendar.DAY_OF_MONTH)}.${calendar.get(Calendar.MONTH) + 1}"
        if (withYear) "$day.${calendar.get(Calendar.YEAR)}" else day
    }

    @Test
    fun dateReadsTodayOrYesterdayAtTheTimeAsTelegramsViewerDoes() {
        assertEquals(
            "Today at 0:05",
            format(date(2026, Calendar.OCTOBER, 29, 0, 5))
        )
        assertEquals(
            "Yesterday at 23:59",
            format(date(2026, Calendar.OCTOBER, 28, 23, 59))
        )
        assertEquals(
            "Yesterday at 0:00",
            format(date(2026, Calendar.OCTOBER, 28, 0, 0))
        )
    }

    @Test
    fun earlierDateReadsTheDayWithItsYearOnlyFromAnotherYear() {
        assertEquals("27.10 at 18:28", format(date(2026, Calendar.OCTOBER, 27, 18, 28)))
        assertEquals("2.1 at 9:00", format(date(2026, Calendar.JANUARY, 2, 9, 0)))
        assertEquals("31.12.2025 at 22:10", format(date(2025, Calendar.DECEMBER, 31, 22, 10)))
    }

    @Test
    fun yesterdayCrossesTheNewYear() {
        val newYear = date(2027, Calendar.JANUARY, 1, 10, 0)
        assertEquals(
            "Yesterday at 21:00",
            formatMediaViewerDate(
                date(2026, Calendar.DECEMBER, 31, 21, 0),
                newYear,
                formatTime,
                formatDay
            )
        )
    }

    @Test
    fun titleIsThePlaceAmongSeveralOverTheDate() {
        assertEquals("5 of 24" to "Today at 9:41", mediaViewerTitles(5, 24, "Today at 9:41"))
        assertEquals("2 of 2" to null, mediaViewerTitles(2, 2, null))
    }

    @Test
    fun titleOfALonePictureIsItsDate() {
        assertEquals("Today at 9:41" to null, mediaViewerTitles(1, 1, "Today at 9:41"))
        assertEquals("" to null, mediaViewerTitles(1, 1, null))
    }

    @Test
    fun pictureNameHasItsPlaceAmongSeveralAndTheHeadline() {
        assertEquals(
            "Picture 3 of 24, Bitcoin Core fixes a bug",
            mediaViewerDescription(3, 24, "Bitcoin Core fixes a bug")
        )
        assertEquals(
            "Picture, NEAR opens pre-IPO trading",
            mediaViewerDescription(1, 1, "NEAR opens pre-IPO trading")
        )
        assertEquals("Picture 1 of 2", mediaViewerDescription(1, 2, " "))
    }

    @Test
    fun turnsGoOnlyWhereThereIsAPicture() {
        assertEquals(emptyList<MediaViewerTurn>(), MediaViewerTurn.available(0, 1))
        assertEquals(listOf(MediaViewerTurn.NEXT), MediaViewerTurn.available(0, 3))
        assertEquals(
            listOf(MediaViewerTurn.PREVIOUS, MediaViewerTurn.NEXT),
            MediaViewerTurn.available(1, 3)
        )
        assertEquals(listOf(MediaViewerTurn.PREVIOUS), MediaViewerTurn.available(2, 3))
        assertEquals(listOf("Previous", "Next"), MediaViewerTurn.entries.map { it.titleKey })
    }

    private fun format(date: Date) = formatMediaViewerDate(date, now, formatTime, formatDay)

    private fun date(year: Int, month: Int, day: Int, hour: Int, minute: Int): Date =
        Calendar.getInstance().apply {
            clear()
            set(year, month, day, hour, minute)
        }.time

    companion object {
        private var previousDictionary: Any? = null

        @JvmStatic
        @BeforeClass
        fun installStrings() {
            LocaleController::class.java.getDeclaredField("dictionary").apply {
                isAccessible = true
                previousDictionary = get(null)
                set(
                    null,
                    mapOf(
                        "Today" to "Today",
                        "Yesterday" to "Yesterday",
                        "Picture" to "Picture",
                        "\$agent_wallet_page_indicator" to "%current% of %total%",
                        "\$media_viewer_date_at_time" to "%date% at %time%"
                    )
                )
            }
        }

        @JvmStatic
        @AfterClass
        fun restoreStrings() {
            LocaleController::class.java.getDeclaredField("dictionary").apply {
                isAccessible = true
                set(null, previousDictionary)
            }
        }
    }
}
