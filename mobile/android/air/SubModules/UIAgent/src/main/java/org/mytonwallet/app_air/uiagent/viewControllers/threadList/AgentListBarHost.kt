package org.mytonwallet.app_air.uiagent.viewControllers.threadList

/** The root's bottom toolbar that hosts the chat list's question bar, which grows out of it */
interface AgentListBarHost {
    /** How far above the bottom of the window the toolbar's field ends */
    val agentBarBottomInset: Int

    /** The list's bar was covered by a chat or uncovered, or a question started or stopped being written */
    fun onAgentBarStateChanged()
}
