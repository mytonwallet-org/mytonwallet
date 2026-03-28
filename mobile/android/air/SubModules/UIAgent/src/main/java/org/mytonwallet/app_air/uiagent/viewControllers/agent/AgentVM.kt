package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.uiagent.processors.AgentHint
import org.mytonwallet.app_air.uiagent.processors.AgentProcessor
import org.mytonwallet.app_air.uiagent.processors.AgentResult
import org.mytonwallet.app_air.uiagent.processors.AgentStreamEvent
import org.mytonwallet.app_air.uiagent.processors.AgentUserAddress
import org.mytonwallet.app_air.uiagent.processors.MockAgentProcessor
import org.mytonwallet.app_air.uiagent.processors.RealAgentProcessor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.stores.AgentMessageStore
import org.mytonwallet.app_air.walletcore.stores.StoredAgentMessage
import org.mytonwallet.app_air.walletcore.stores.StoredDeeplink
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import java.util.Date

class AgentVM(delegate: Delegate) :
    WalletCore.EventObserver {

    interface Delegate {
        fun onMessageAdded(message: AgentMessage)
        fun onMessagesLoaded(messages: List<AgentMessage>)
        fun onStreamingUpdate(messageId: String, text: String)
        fun onStreamingFinished(messageId: String)
        fun onResultsReceived(messageId: String, results: List<AgentResult>)
        fun onError(error: String)
        fun onHintsUpdated(hints: List<AgentHint>)
    }

    enum class ProcessorType { MOCK, REAL }

    val delegate: WeakReference<Delegate> = WeakReference(delegate)
    private var processor: AgentProcessor = RealAgentProcessor()
    var processorType = ProcessorType.REAL
        private set
    private val supervisorJob = SupervisorJob()
    private val vmScope = CoroutineScope(supervisorJob + Dispatchers.Main)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var streamJob: Job? = null

    private val _messages = mutableListOf<AgentMessage>()
    val messages: List<AgentMessage> get() = _messages

    private var availableHints = listOf<AgentHint>()
    private var showHintsInConversation = true
    private var hintsJob: Job? = null

    val visibleHints: List<AgentHint>
        get() = if (shouldShowHints) availableHints else emptyList()

    val hasHints: Boolean
        get() = availableHints.isNotEmpty()

    private val shouldShowHints: Boolean
        get() = availableHints.isNotEmpty() && showHintsInConversation

    var isActive = false
    private var currentAccountId: String? = AccountStore.activeAccountId

    init {
        WalletCore.registerObserver(this)
        loadHints()
        loadStoredMessages()
    }

    fun setProcessor(type: ProcessorType) {
        processorType = type
        processor = when (type) {
            ProcessorType.MOCK -> MockAgentProcessor()
            ProcessorType.REAL -> RealAgentProcessor()
        }
        val label = when (type) {
            ProcessorType.MOCK -> "Mock"
            ProcessorType.REAL -> "Real"
        }
        addSystemMessage("Switched to $label processor")
        loadHints()
    }

    fun checkAccountChanged() {
        if (messages.isEmpty()) return
        val newAccountId = AccountStore.activeAccountId
        if (newAccountId != null && newAccountId != currentAccountId) {
            currentAccountId = newAccountId
            val account = AccountStore.accountById(newAccountId)
            val name = account?.name?.takeIf { it.isNotEmpty() } ?: "Account"
            addSystemMessage("Switched to $name")
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        if (walletEvent is WalletEvent.AccountChanged && isActive) {
            checkAccountChanged()
        }
    }

    private fun addSystemMessage(text: String) {
        val message = AgentMessage(role = AgentMessageRole.SYSTEM, text = text)
        _messages.add(message)
        persistMessage(message)
        delegate.get()?.onMessageAdded(message)
    }

    fun clearChat() {
        streamJob?.cancel()
        _messages.clear()
        showHintsInConversation = false
        processor.resetClientId()
        AgentMessageStore.clearMessages()
        loadHints()
    }

    fun sendMessage(text: String) {
        val wasShowingHints = visibleHints.isNotEmpty()
        val hideHints = wasShowingHints && _messages.isEmpty()
        if (hideHints)
            showHintsInConversation = false
        val userMessage = AgentMessage(role = AgentMessageRole.USER, text = text)
        _messages.add(userMessage)
        persistMessage(userMessage)
        delegate.get()?.onMessageAdded(userMessage)
        if (wasShowingHints) {
            delegate.get()?.onHintsUpdated(visibleHints)
        }

        requestReply(text)
    }

    fun toggleHintsVisibility() {
        showHintsInConversation = !showHintsInConversation
        delegate.get()?.onHintsUpdated(visibleHints)
    }

    private fun loadHints() {
        hintsJob?.cancel()
        hintsJob = vmScope.launch {
            val langCode = LocaleController.activeLanguage.langCode
            val hints = processor.loadHints(langCode)
            availableHints = hints
            if (hints.isEmpty()) showHintsInConversation = false
            delegate.get()?.onHintsUpdated(visibleHints)
        }
    }

    private fun loadStoredMessages() {
        vmScope.launch {
            val stored = withContext(Dispatchers.IO) {
                AgentMessageStore.loadMessages()
            }
            if (stored.isEmpty()) return@launch
            val loaded = stored.map { it.toAgentMessage() }
            _messages.addAll(loaded)
            delegate.get()?.onMessagesLoaded(_messages)
        }
    }

    private fun requestReply(userText: String) {
        val assistantMessage = AgentMessage(
            role = AgentMessageRole.ASSISTANT,
            text = "",
            isStreaming = true
        )
        _messages.add(assistantMessage)
        delegate.get()?.onMessageAdded(assistantMessage)

        val userAddresses = buildUserAddresses()
        val userId = AccountStore.activeAccountId ?: "unknown"
        val messageId = assistantMessage.id

        streamJob = vmScope.launch {
            val textBuilder = StringBuilder()

            processor.streamMessage(
                userId = userId,
                message = userText,
                userAddresses = userAddresses,
                onEvent = { event ->
                    when (event) {
                        is AgentStreamEvent.Metadata -> {
                            // Streaming started, typing indicator already shown
                        }

                        is AgentStreamEvent.Chunk -> {
                            textBuilder.append(event.text)
                            mainHandler.post {
                                updateMessage(messageId) {
                                    it.copy(text = textBuilder.toString())
                                }
                                delegate.get()?.onStreamingUpdate(messageId, textBuilder.toString())
                            }
                        }

                        is AgentStreamEvent.Results -> {
                            val rawText = event.results
                                .mapNotNull { it.message }
                                .joinToString("\n\n")
                            val resultsDeeplinks = event.results
                                .flatMap { it.deeplinks }
                                .map { AgentDeeplink(title = it.title, url = it.url) }
                            mainHandler.post {
                                updateMessage(messageId) { msg ->
                                    val baseText = if (rawText.isNotEmpty()) rawText else msg.text
                                    val (cleanedText, inlineDeeplinks) = extractMarkdownDeeplinks(
                                        baseText
                                    )
                                    val updated = msg.copy(
                                        text = cleanedText,
                                        isStreaming = false,
                                        deeplinks = msg.deeplinks + resultsDeeplinks + inlineDeeplinks
                                    )
                                    persistMessage(updated)
                                    updated
                                }
                                delegate.get()?.onResultsReceived(messageId, event.results)
                            }
                        }

                        is AgentStreamEvent.Error -> {
                            mainHandler.post {
                                updateMessage(messageId) {
                                    val updated = it.copy(text = event.message, isStreaming = false)
                                    persistMessage(updated)
                                    updated
                                }
                                delegate.get()?.onStreamingFinished(messageId)
                                delegate.get()?.onError(event.message)
                            }
                        }
                    }
                },
                onDone = {
                    mainHandler.post {
                        updateMessage(messageId) { msg ->
                            val (cleanedText, inlineDeeplinks) = extractMarkdownDeeplinks(msg.text)
                            val updated = msg.copy(
                                text = cleanedText,
                                isStreaming = false,
                                deeplinks = msg.deeplinks + inlineDeeplinks
                            )
                            persistMessage(updated)
                            updated
                        }
                        delegate.get()?.onStreamingFinished(messageId)
                    }
                },
                onError = { e ->
                    mainHandler.post {
                        val errorText = textBuilder.toString().ifEmpty {
                            "Something went wrong. Please try again."
                        }
                        updateMessage(messageId) {
                            val updated = it.copy(text = errorText, isStreaming = false)
                            persistMessage(updated)
                            updated
                        }
                        delegate.get()?.onStreamingFinished(messageId)
                        delegate.get()?.onError(e.message ?: "Unknown error")
                    }
                }
            )
        }
    }

    private fun extractMarkdownDeeplinks(text: String): Pair<String, List<AgentDeeplink>> {
        val regex = Regex("""\[([^\]]+)\]\(([a-zA-Z][a-zA-Z0-9+\-.]*://[^)]+)\)""")
        val deeplinks = mutableListOf<AgentDeeplink>()
        val cleaned = regex.replace(text) { match ->
            deeplinks.add(AgentDeeplink(title = match.groupValues[1], url = match.groupValues[2]))
            ""
        }.trim()
        return Pair(cleaned, deeplinks)
    }

    private fun updateMessage(messageId: String, transform: (AgentMessage) -> AgentMessage) {
        val idx = messages.indexOfFirst { it.id == messageId }
        if (idx >= 0) {
            _messages[idx] = transform(messages[idx])
        }
    }

    private fun persistMessage(message: AgentMessage) {
        AgentMessageStore.insertMessage(message.toStored())
    }

    private fun buildUserAddresses(): List<AgentUserAddress> {
        val account = AccountStore.accountById(AccountStore.activeAccountId) ?: return emptyList()
        val addresses = account.byChain.map { (chain, chainData) -> "$chain:${chainData.address}" }
        return listOf(AgentUserAddress(name = account.name, addresses = addresses))
    }

    fun onDestroy() {
        streamJob?.cancel()
        hintsJob?.cancel()
        supervisorJob.cancel()
        WalletCore.unregisterObserver(this)
    }
}

private fun AgentMessage.toStored() = StoredAgentMessage(
    id = id,
    role = role.name,
    text = text,
    dateMs = date.time,
    deeplinks = deeplinks.map { StoredDeeplink(it.title, it.url) }
)

private fun StoredAgentMessage.toAgentMessage() = AgentMessage(
    id = id,
    role = AgentMessageRole.valueOf(role),
    text = text,
    date = Date(dateMs),
    isStreaming = false,
    deeplinks = deeplinks.map { AgentDeeplink(it.title, it.url) }
)
