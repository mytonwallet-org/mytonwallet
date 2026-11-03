package org.mytonwallet.app_air.uiagent.agentV2

/** While the field shows a recording, the draft under it doesn't change */
internal fun AgentDictationState.filterDraftEdit(
    original: CharSequence,
    start: Int,
    end: Int
): CharSequence? = if (isActive) original.subSequence(start, end) else null
