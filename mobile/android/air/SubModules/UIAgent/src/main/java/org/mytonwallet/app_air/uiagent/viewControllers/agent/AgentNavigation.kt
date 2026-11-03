package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.content.Context
import org.mytonwallet.app_air.uicomponents.base.ITabsVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

object AgentNavigation {
    /** [beforePush] gets the discussion's chat before it slides in */
    fun openNewsChat(
        context: Context,
        navigationController: WNavigationController,
        eventId: Int,
        locale: String,
        headline: String,
        icon: String?,
        threadId: String?,
        onThreadCreated: (AgentV2ThreadSummary) -> Unit,
        onThreadMissing: (String) -> Unit,
        excerpt: String? = null,
        imageUrl: String? = null,
        publishedAt: String? = null,
        body: String? = null,
        sources: List<AgentV2NewsFeedItem.Source>? = null,
        beforePush: (AgentVC) -> Unit = {}
    ) {
        val chat = AgentVC(
            context,
            news = AgentNewsChatRequest(
                eventId,
                locale,
                headline,
                icon,
                threadId,
                excerpt = excerpt,
                imageUrl = imageUrl,
                publishedAt = publishedAt,
                body = body,
                sources = sources
            ),
            onNewsThreadCreated = onThreadCreated,
            onNewsThreadMissing = onThreadMissing
        )
        beforePush(chat)
        navigationController.push(chat)
    }

    fun openNewChat(
        context: Context,
        navigationController: WNavigationController?,
        prompt: String,
        entryPoint: AgentV2EntryPoint = AgentV2EntryPoint(),
        fallbackNavigationController: WNavigationController? = null
    ): Boolean {
        navigationController ?: return false
        val tabs = findTabs(navigationController)
        if (tabs?.switchToAgent(prompt = prompt, entryPoint = entryPoint) == true) return true
        fallbackTarget(navigationController, tabs, fallbackNavigationController)
            .push(newChatViewController(context, prompt, entryPoint))
        return false
    }

    fun newChatViewController(
        context: Context,
        prompt: String,
        entryPoint: AgentV2EntryPoint = AgentV2EntryPoint()
    ): WViewController = if (prompt.isBlank()) {
        AgentNewChatVC(context)
    } else {
        AgentVC(context, prompt = AgentPromptChatRequest(prompt, entryPoint))
    }

    /** Returns true when the thread opened in the Agent tab, false when it was pushed instead. */
    fun openThread(
        context: Context,
        navigationController: WNavigationController?,
        thread: AgentV2ThreadSummary,
        fallbackNavigationController: WNavigationController? = null
    ): Boolean {
        navigationController ?: return false
        val tabs = findTabs(navigationController)
        if (tabs?.switchToAgent(thread = thread) == true) return true
        fallbackTarget(navigationController, tabs, fallbackNavigationController)
            .push(AgentVC(context, thread))
        return false
    }

    private fun fallbackTarget(
        navigationController: WNavigationController,
        tabs: ITabsVC?,
        fallbackNavigationController: WNavigationController?
    ): WNavigationController = fallbackNavigationController
        ?: if (navigationController.tabBarController != null) {
            tabs?.mainNavigationController ?: navigationController
        } else {
            navigationController
        }

    private fun findTabs(navigationController: WNavigationController): ITabsVC? =
        navigationController.tabBarController
            ?: navigationController.viewControllers.firstOrNull() as? ITabsVC
            ?: navigationController.window.navigationControllers.firstOrNull()
                ?.viewControllers?.firstOrNull() as? ITabsVC
}
