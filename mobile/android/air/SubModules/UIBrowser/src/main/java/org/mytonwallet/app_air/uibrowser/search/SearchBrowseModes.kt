package org.mytonwallet.app_air.uibrowser.search

internal enum class SearchBrowseAccessory {
    TOGGLE,
    RECENT_TEXT,
    ALTERNATIVE_TEXT,
    NONE
}

internal fun recentOrTrendingAccessory(
    hasRecent: Boolean,
    hasTrending: Boolean
): SearchBrowseAccessory = when {
    hasRecent && hasTrending -> SearchBrowseAccessory.TOGGLE
    hasRecent -> SearchBrowseAccessory.RECENT_TEXT
    hasTrending -> SearchBrowseAccessory.ALTERNATIVE_TEXT
    else -> SearchBrowseAccessory.NONE
}

internal fun selectsTrending(
    prefersTrending: Boolean,
    hasRecent: Boolean,
    hasTrending: Boolean
): Boolean = if (prefersTrending) hasTrending else !hasRecent

/** Buttons need suggestions, since Recent always has a row. */
internal fun chatsAccessory(hasChats: Boolean, hasSuggestions: Boolean): SearchBrowseAccessory =
    when {
        hasSuggestions -> SearchBrowseAccessory.TOGGLE
        hasChats -> SearchBrowseAccessory.RECENT_TEXT
        else -> SearchBrowseAccessory.NONE
    }

internal fun selectsSuggestions(
    prefersSuggestions: Boolean?,
    hasChats: Boolean,
    hasSuggestions: Boolean
): Boolean = hasSuggestions && (prefersSuggestions ?: !hasChats)
