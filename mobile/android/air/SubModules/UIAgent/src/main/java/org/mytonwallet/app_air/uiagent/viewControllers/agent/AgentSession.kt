package org.mytonwallet.app_air.uiagent.viewControllers.agent

object AgentSession {
    private var viewModel: AgentVM? = null
    private var ownerCount = 0
    private var scrollPosition: AgentVM.ScrollPosition? = null

    fun acquire(): AgentVM {
        ownerCount++
        return viewModel ?: AgentVM(scrollPosition).also { viewModel = it }
    }

    fun release(viewModel: AgentVM) {
        if (this.viewModel !== viewModel || ownerCount == 0) return
        ownerCount--
        if (ownerCount == 0) {
            scrollPosition = viewModel.scrollPosition
            viewModel.onDestroy()
            this.viewModel = null
        }
    }
}
