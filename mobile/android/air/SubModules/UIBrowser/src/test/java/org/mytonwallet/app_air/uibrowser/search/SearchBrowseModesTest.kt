package org.mytonwallet.app_air.uibrowser.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SearchBrowseModesTest {
    @Test
    fun `tokens and apps toggle only while both lists have rows`() {
        assertEquals(
            SearchBrowseAccessory.TOGGLE,
            recentOrTrendingAccessory(hasRecent = true, hasTrending = true)
        )
        assertEquals(
            SearchBrowseAccessory.RECENT_TEXT,
            recentOrTrendingAccessory(hasRecent = true, hasTrending = false)
        )
        assertEquals(
            SearchBrowseAccessory.ALTERNATIVE_TEXT,
            recentOrTrendingAccessory(hasRecent = false, hasTrending = true)
        )
        assertEquals(
            SearchBrowseAccessory.NONE,
            recentOrTrendingAccessory(hasRecent = false, hasTrending = false)
        )
    }

    @Test
    fun `tokens and apps fall back to the list that has rows`() {
        assertFalse(selectsTrending(false, hasRecent = true, hasTrending = true))
        assertTrue(selectsTrending(false, hasRecent = false, hasTrending = true))
        assertTrue(selectsTrending(true, hasRecent = true, hasTrending = true))
        assertFalse(selectsTrending(true, hasRecent = true, hasTrending = false))
    }

    @Test
    fun `chats toggle while there are suggestions and name the chats without them`() {
        val toggle = SearchBrowseAccessory.TOGGLE
        assertEquals(toggle, chatsAccessory(hasChats = false, hasSuggestions = true))
        assertEquals(toggle, chatsAccessory(hasChats = true, hasSuggestions = true))
        assertEquals(
            SearchBrowseAccessory.RECENT_TEXT,
            chatsAccessory(hasChats = true, hasSuggestions = false)
        )
        assertEquals(
            SearchBrowseAccessory.NONE,
            chatsAccessory(hasChats = false, hasSuggestions = false)
        )
    }

    @Test
    fun `chats show suggestions by default only while there are no chats`() {
        assertFalse(selectsSuggestions(null, hasChats = true, hasSuggestions = true))
        assertTrue(selectsSuggestions(null, hasChats = false, hasSuggestions = true))
        assertTrue(selectsSuggestions(true, hasChats = true, hasSuggestions = true))
        assertFalse(selectsSuggestions(false, hasChats = false, hasSuggestions = true))
        assertFalse(selectsSuggestions(true, hasChats = true, hasSuggestions = false))
    }
}
