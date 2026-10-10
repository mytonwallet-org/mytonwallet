package org.mytonwallet.app_air.uiagent.viewControllers.agent

object AgentSession {
    private var viewModel: AgentVM? = null
    private var ownerCount = 0
    private var scrollPosition: AgentVM.ScrollPosition? = null

    fun acquire(): AgentVM {
        ownerCount++
        return viewModel?.also { it.onSessionIdle = null }
            ?: AgentVM(scrollPosition).also { viewModel = it }
    }

    fun release(viewModel: AgentVM) {
        if (this.viewModel !== viewModel || ownerCount == 0) return
        ownerCount--
        if (ownerCount != 0) return
        scrollPosition = viewModel.scrollPosition
        if (viewModel.shouldRetainSession) {
            viewModel.onSessionIdle = { destroyIfUnused(viewModel) }
            return
        }
        destroyIfUnused(viewModel)
    }

    private fun destroyIfUnused(viewModel: AgentVM) {
        if (this.viewModel !== viewModel || ownerCount != 0 || viewModel.shouldRetainSession) {
            return
        }
        viewModel.onSessionIdle = null
        scrollPosition = viewModel.scrollPosition
        viewModel.onDestroy()
        this.viewModel = null
    }
}
