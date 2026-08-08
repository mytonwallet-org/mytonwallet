package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.os.Handler
import android.os.Looper
import java.lang.ref.WeakReference
import java.util.Date
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
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import org.mytonwallet.app_air.walletcore.stores.AgentMessageStore
import org.mytonwallet.app_air.walletcore.stores.StoredAgentMessage
import org.mytonwallet.app_air.walletcore.stores.StoredDeeplink

class AgentVM(initialScrollPosition: ScrollPosition? = null) : WalletCore.EventObserver {

    interface Delegate {
        fun onMessageAdded(message: AgentMessage)
        fun onMessagesLoaded(messages: List<AgentMessage>)
        fun onStreamingUpdate(messageId: String, text: String)
        fun onStreamingFinished(messageId: String)
        fun onResultsReceived(messageId: String, results: List<AgentResult>)
        fun onError(error: String)
        fun onHintsUpdated(hints: List<AgentHint>)
    }

    sealed interface ScrollAnchor {
        data object Bottom : ScrollAnchor
        data class Message(val messageId: String) : ScrollAnchor
        data object Hints : ScrollAnchor
    }

    data class ScrollPosition(
        val anchor: ScrollAnchor,
        val offset: Int = 0,
        val pinnedMessageId: String? = null,
        val pinnedBottomPadding: Int = 0
    )

    enum class ProcessorType { MOCK, REAL }

    private val delegates = mutableListOf<WeakReference<Delegate>>()
    private val activeDelegates = mutableListOf<WeakReference<Delegate>>()
    private var processor: AgentProcessor = RealAgentProcessor()
    var processorType = ProcessorType.REAL
        private set
    private val supervisorJob = SupervisorJob()
    private val vmScope = CoroutineScope(supervisorJob + Dispatchers.Main)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var streamJob: Job? = null
    private var storedMessagesLoaded = false
    private val pendingMessages = mutableListOf<String>()

    private val _messages = mutableListOf<AgentMessage>()
    val messages: List<AgentMessage> get() = _messages

    var scrollPosition: ScrollPosition? = initialScrollPosition
        private set

    private var availableHints = listOf<AgentHint>()
    private var showHintsInConversation = true
    private var hintsJob: Job? = null

    val visibleHints: List<AgentHint>
        get() = if (shouldShowHints) availableHints else emptyList()

    val hasHints: Boolean
        get() = availableHints.isNotEmpty()

    private val shouldShowHints: Boolean
        get() = availableHints.isNotEmpty() && showHintsInConversation

    private var currentAccountId: String? = AccountStore.activeAccountId

    init {
        WalletCore.registerObserver(this)
        loadHints()
        loadStoredMessages()
    }

    fun attach(delegate: Delegate) {
        if (liveDelegates(delegates).none { it === delegate }) {
            delegates.add(WeakReference(delegate))
        }
        delegate.onMessagesLoaded(_messages.toList())
        delegate.onHintsUpdated(visibleHints)
    }

    fun detach(delegate: Delegate) {
        removeDelegate(delegates, delegate)
        removeDelegate(activeDelegates, delegate)
    }

    fun setActive(delegate: Delegate, active: Boolean) {
        removeDelegate(activeDelegates, delegate)
        if (active) {
            activeDelegates.add(WeakReference(delegate))
        }
    }

    fun updateScrollPosition(delegate: Delegate, position: ScrollPosition) {
        if (liveDelegates(activeDelegates).none { it === delegate }) return
        scrollPosition = position
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
        if (walletEvent is WalletEvent.AccountChanged &&
            liveDelegates(activeDelegates).isNotEmpty()
        ) {
            checkAccountChanged()
        }
    }

    private fun addSystemMessage(text: String) {
        val message = AgentMessage(role = AgentMessageRole.SYSTEM, text = text)
        _messages.add(message)
        persistMessage(message)
        notifyDelegates { it.onMessageAdded(message) }
    }

    fun clearChat() {
        streamJob?.cancel()
        _messages.clear()
        scrollPosition = ScrollPosition(ScrollAnchor.Bottom)
        showHintsInConversation = false
        processor.resetClientId()
        AgentMessageStore.clearMessages()
        notifyDelegates { it.onMessagesLoaded(emptyList()) }
        notifyDelegates { it.onHintsUpdated(visibleHints) }
        loadHints()
    }

    fun sendMessage(text: String) {
        if (!storedMessagesLoaded) {
            pendingMessages.add(text)
            return
        }
        sendMessageNow(text)
    }

    private fun sendMessageNow(text: String) {
        val wasShowingHints = visibleHints.isNotEmpty()
        if (wasShowingHints) showHintsInConversation = false
        val userMessage = AgentMessage(role = AgentMessageRole.USER, text = text)
        _messages.add(userMessage)
        persistMessage(userMessage)
        notifyDelegates { it.onMessageAdded(userMessage) }
        if (wasShowingHints) {
            notifyDelegates { it.onHintsUpdated(visibleHints) }
        }

        requestReply(text)
    }

    fun toggleHintsVisibility() {
        showHintsInConversation = !showHintsInConversation
        notifyDelegates { it.onHintsUpdated(visibleHints) }
    }

    private fun loadHints() {
        hintsJob?.cancel()
        hintsJob = vmScope.launch {
            val langCode = LocaleController.activeLanguage.langCode
            val hints = processor.loadHints(langCode)
            availableHints = hints
            if (hints.isEmpty()) showHintsInConversation = false
            notifyDelegates { it.onHintsUpdated(visibleHints) }
        }
    }

    private fun loadStoredMessages() {
        vmScope.launch {
            val stored = withContext(Dispatchers.IO) {
                AgentMessageStore.loadMessages()
            }
            if (stored.isEmpty()) {
                scrollPosition = ScrollPosition(ScrollAnchor.Bottom)
            } else {
                val loaded = stored.map { it.toAgentMessage() }
                _messages.addAll(loaded)
                notifyDelegates { it.onMessagesLoaded(_messages.toList()) }
            }
            storedMessagesLoaded = true
            val queued = pendingMessages.toList()
            pendingMessages.clear()
            queued.forEach(::sendMessageNow)
        }
    }

    private fun requestReply(userText: String) {
        val assistantMessage = AgentMessage(
            role = AgentMessageRole.ASSISTANT,
            text = "",
            isStreaming = true
        )
        _messages.add(assistantMessage)
        notifyDelegates { it.onMessageAdded(assistantMessage) }

        val userAddresses = buildUserAddresses()
        val savedAddresses = buildSavedAddresses()
        val userId = AccountStore.activeAccountId ?: "unknown"
        val messageId = assistantMessage.id

        streamJob = vmScope.launch {
            val textBuilder = StringBuilder()

            processor.streamMessage(
                userId = userId,
                message = userText,
                userAddresses = userAddresses,
                savedAddresses = savedAddresses,
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
                                notifyDelegates {
                                    it.onStreamingUpdate(messageId, textBuilder.toString())
                                }
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
                                        deeplinks =
                                            msg.deeplinks + resultsDeeplinks + inlineDeeplinks
                                    )
                                    persistMessage(updated)
                                    updated
                                }
                                notifyDelegates {
                                    it.onResultsReceived(messageId, event.results)
                                }
                            }
                        }

                        is AgentStreamEvent.Error -> {
                            mainHandler.post {
                                updateMessage(messageId) {
                                    val updated = it.copy(text = event.message, isStreaming = false)
                                    persistMessage(updated)
                                    updated
                                }
                                notifyDelegates { it.onStreamingFinished(messageId) }
                                notifyDelegates { it.onError(event.message) }
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
                        notifyDelegates { it.onStreamingFinished(messageId) }
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
                        notifyDelegates { it.onStreamingFinished(messageId) }
                        notifyDelegates { it.onError(e.message ?: "Unknown error") }
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
        val activeAccountId = AccountStore.activeAccountId ?: return emptyList()
        val allAccounts = WalletCore.getAllAccounts()

        // Take first 5 accounts in their natural order
        val firstFive = allAccounts.take(5)
        val activeInFirstFive = firstFive.any { it.accountId == activeAccountId }

        val result = mutableListOf<AgentUserAddress>()

        for (account in firstFive) {
            val isActive = account.accountId == activeAccountId
            val addresses =
                account.byChain.map { (chain, chainData) -> "$chain:${chainData.address}" }
            result.add(
                AgentUserAddress(
                    name = account.name,
                    addresses = addresses,
                    accountType = account.accountType.value,
                    isActive = isActive
                )
            )
        }

        // If active account is not among the first 5, append it
        if (!activeInFirstFive) {
            val account = AccountStore.accountById(activeAccountId)
            if (account != null) {
                val addresses =
                    account.byChain.map { (chain, chainData) -> "$chain:${chainData.address}" }
                result.add(
                    AgentUserAddress(
                        name = account.name,
                        addresses = addresses,
                        accountType = account.accountType.value,
                        isActive = true
                    )
                )
            }
        }

        return result
    }

    private fun buildSavedAddresses(): List<AgentUserAddress> {
        val savedAddresses = AddressStore.addressData?.savedAddresses ?: return emptyList()
        return savedAddresses.take(10).map { saved ->
            AgentUserAddress(
                name = saved.name,
                addresses = listOf("${saved.chain}:${saved.address}")
            )
        }
    }

    private fun liveDelegates(references: MutableList<WeakReference<Delegate>>): List<Delegate> {
        val result = mutableListOf<Delegate>()
        val iterator = references.iterator()
        while (iterator.hasNext()) {
            val delegate = iterator.next().get()
            if (delegate == null) {
                iterator.remove()
            } else {
                result.add(delegate)
            }
        }
        return result
    }

    private fun removeDelegate(
        references: MutableList<WeakReference<Delegate>>,
        delegate: Delegate
    ) {
        references.removeAll { reference ->
            val current = reference.get()
            current == null || current === delegate
        }
    }

    private inline fun notifyDelegates(callback: (Delegate) -> Unit) {
        liveDelegates(delegates).forEach(callback)
    }

    fun onDestroy() {
        streamJob?.cancel()
        hintsJob?.cancel()
        supervisorJob.cancel()
        delegates.clear()
        activeDelegates.clear()
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
