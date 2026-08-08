package org.mytonwallet.app_air.walletcore

import android.content.Context
import android.net.ConnectivityManager
import android.net.ConnectivityManager.NetworkCallback
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import androidx.core.view.isVisible
import com.squareup.moshi.Moshi
import java.lang.ref.WeakReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager.setDefaultAccentColor
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager.setNftAccentColor
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcontext.utils.ensureMainThread
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.api.requestDAppList
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MAssetsAndActivityData
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MoshiBuilder
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ActivityStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import org.mytonwallet.app_air.walletcore.stores.AgentMessageStore
import org.mytonwallet.app_air.walletcore.stores.AuthStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.DappsStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import org.mytonwallet.app_air.walletcore.stores.IStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.walletcore.stores.PortfolioStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

val TESTNET_SLUGS = setOf(TON_USDT_TESTNET_SLUG, TRON_USDT_TESTNET_SLUG)

const val TON_CHAIN = "ton"

const val MFA_BOT_URL = "https://t.me/tgmfabot/auth"

fun buildMfaStartParam(id: String): String {
    val appPrefix = if (ApplicationContextHolder.isGramApp) "g" else "m"
    return "${appPrefix}_$id"
}

const val TONCOIN_SLUG = "toncoin"
const val MYCOIN_SLUG = "ton-eqcfvnlrbn"
const val USDE_SLUG = "ton-eqaib6kmdf"
const val STAKE_SLUG = "ton-eqcqc6ehrj"
const val STAKED_MYCOIN_SLUG = "ton-eqcbzvsfwq"
const val STAKED_USDE_SLUG = "ton-eqdq5uuyph"
const val TON_USDT_SLUG = "ton-eqcxe6mutq"
const val TON_USDT_TESTNET_SLUG = "ton-kqd0gkbm8z"
const val TRON_SLUG = "trx"
const val TRON_USDT_SLUG = "tron-tr7nhqjekq"
const val TRON_USDT_TESTNET_SLUG = "tron-tg3xxyexbk"
const val SOLANA_SLUG = "sol"
const val SOLANA_USDT_SLUG = "solana-es9vmfrzac"
const val SOLANA_USDC_SLUG = "solana-epjfwdd5au"
const val ETH_SLUG = "eth"
const val ETH_USDT_MAINNET_SLUG = "ethereum-0xdac17f95"
const val ETH_USDC_MAINNET_SLUG = "ethereum-0xa0b86991"
const val BASE_SLUG = "base"
const val BASE_USDT_MAINNET_SLUG = "base-0xfde4c96c"
const val BASE_USDC_MAINNET_SLUG = "base-0x833589fc"
const val BNB_SLUG = "bnb"
const val BSC_USDT_MAINNET_SLUG = "bnb-0x55d39832"
const val POLYGON_SLUG = "pol"
const val ARBITRUM_SLUG = "arb"
const val MONAD_SLUG = "mon"
const val AVALANCHE_SLUG = "ava"
const val AVALANCHE_USDT_MAINNET_SLUG = "avalanche-0x9702230a"
const val HYPERLIQUID_SLUG = "hyperliquid"
const val HYPERLIQUID_USDC_MAINNET_SLUG = "hyperliquid-0xb88339cb"
const val ROBINHOOD_SLUG = "robinhood"
const val VIRTUAL_STAKING_SLUG_PREFIX = "staking-"
const val TON_DNS_COLLECTION = "EQC3dNlesgVD8YbAazcauIrXBPfiVhMMr5YYk2in0Mtsz0Bz"
const val TELEGRAM_USERNAMES_COLLECTION = "EQCA14o1-VWhS2efqoh_9M1b_A9DtKTuoqfmkn83AbJzwnPi"
const val MTW_CARDS_COLLECTION = "EQCQE2L9hfwx1V8sgmF9keraHx1rNK9VmgR1ctVvINBGykyM"
const val MTW_CARDS_MINT_BASE_URL = "https://static.mytonwallet.org/mint-cards/"
const val MINT_CARD_ADDRESS = "EQBpst3ZWJ9Dqq5gE2YH-yPsFK_BqMOmgi7Z_qK6v7WbrPWv"
const val MINT_CARD_COMMENT = "Mint card"
const val MINT_CARD_REFUND_COMMENT = "Refund"

val STAKING_SLUGS = setOf(
    STAKE_SLUG,
    STAKED_MYCOIN_SLUG,
    STAKED_USDE_SLUG
)

fun tokenSlugToStakingSlug(slug: String): String? = when (slug) {
    TONCOIN_SLUG -> STAKE_SLUG
    MYCOIN_SLUG -> STAKED_MYCOIN_SLUG
    USDE_SLUG -> STAKED_USDE_SLUG
    else -> null
}

fun stakingSlugToTokenSlug(stakingSlug: String): String? = when (stakingSlug) {
    STAKE_SLUG, TONCOIN_SLUG -> TONCOIN_SLUG
    STAKED_MYCOIN_SLUG, MYCOIN_SLUG -> MYCOIN_SLUG
    STAKED_USDE_SLUG, USDE_SLUG -> USDE_SLUG
    else -> null
}

fun buildVirtualStakingSlug(baseSlug: String): String = "$VIRTUAL_STAKING_SLUG_PREFIX$baseSlug"

val POPULAR_WALLET_VERSIONS = listOf(
    "v3R1",
    "v3R2",
    "v4R2",
    "W5"
)

val PRICELESS_TOKEN_HASHES = setOf(
    // FIVA SY tsTON
    // EQAxGi9Al7hamLAORroxGkvfap6knGyzI50ThkP3CLPLTtOZ
    "173e31eee054cb0c76f77edc7956bed766bf48a1f63bd062d87040dcd3df700f",
    // FIVA PT tsTON
    // EQAkxIRGXgs2vD2zjt334MBjD3mXg2GsyEZHfzuYX_trQkFL
    "5226dd4e6db9af26b24d5ca822bc4053b7e08152f923932abf25030c7e38bb42",
    // FIVA YT tsTON
    // EQAcy60qg22RCq87A_qgYK8hooEgjCZ44yxhdnKYdlWIfKXL
    "fea2c08a704e5192b7f37434927170440d445b87aab865c3ea2a68abe7168204",
    // FIVA LP tsTON
    // EQD3BjCjxuf8mu5kvxajVbe-Ila1ScZZlAi03oS7lMmAJjM3
    "e691cf9081a8aeb22ed4d94829f6626c9d822752e035800b5543c43f83d134b5",
    // FIVA SY eUSDT
    // EQDi9blCcyT-k8iMpFMYY0t7mHVyiCB50ZsRgyUECJDuGvIl
    "301ce25925830d713b326824e552e962925c4ff45b1e3ea21fc363a459a49b43",
    // FIVA PT eUSDT
    // EQBzVrYkYPHx8D_HPfQacm1xONa4XSRxl826vHkx_laP2HOe
    "02250f83fbb8624d859c2c045ac70ee2b3b959688c3d843aec773be9b36dbfc3",
    // FIVA YT eUSDT
    // EQCwUSc2qrY5rn9BfFBG9ARAHePTUvITDl97UD0zOreWzLru
    "dba3adb2c917db80fd71a6a68c1fc9e12976491a8309d5910f9722efc084ce4d",
    // FIVA LP eUSDT
    // EQBNlIZxIbQGQ78cXgG3VRcyl8A0kLn_6BM9kabiHHhWC4qY
    "7da9223b90984d6a144e71611a8d7c65a6298cad734faed79438dc0f7a8e53d1",
    // tsUSDe
    // EQDQ5UUyPHrLcQJlPAczd_fjxn8SLrlNQwolBznxCdSlfQwr
    "ddf80de336d580ab3c11d194f189c362e2ca1225cae224ea921deeaba7eca818"
)

private val TRUSTED_USDT_TOKENS = mapOf(
    MBlockchainNetwork.MAINNET to setOf(
        TON_USDT_SLUG,
        TRON_USDT_SLUG,
        SOLANA_USDT_SLUG,
        SOLANA_USDC_SLUG,
        ETH_USDT_MAINNET_SLUG,
        ETH_USDC_MAINNET_SLUG,
        BASE_USDT_MAINNET_SLUG,
        BASE_USDC_MAINNET_SLUG,
        BSC_USDT_MAINNET_SLUG,
        AVALANCHE_USDT_MAINNET_SLUG,
        HYPERLIQUID_USDC_MAINNET_SLUG
    ),
    MBlockchainNetwork.TESTNET to setOf(
        TON_USDT_TESTNET_SLUG,
        TRON_USDT_TESTNET_SLUG,
        ETH_USDT_MAINNET_SLUG,
        BASE_USDT_MAINNET_SLUG,
        BASE_USDC_MAINNET_SLUG,
        BSC_USDT_MAINNET_SLUG,
        AVALANCHE_USDT_MAINNET_SLUG,
        HYPERLIQUID_USDC_MAINNET_SLUG
    )
)

fun getTrustedUsdtTokens(network: MBlockchainNetwork?): Set<String> = network?.let {
    TRUSTED_USDT_TOKENS[it]
} ?: TRUSTED_USDT_TOKENS.values.flatten().toSet()

val ALL_DEFAULT_TOKENS = mapOf(
    MBlockchainNetwork.MAINNET to MBlockchain.supportedChains.map { it.nativeSlug } +
        getTrustedUsdtTokens(MBlockchainNetwork.MAINNET),
    MBlockchainNetwork.TESTNET to MBlockchain.supportedChains.map { it.nativeSlug } +
        getTrustedUsdtTokens(MBlockchainNetwork.TESTNET)
)

private val CHAIN_DEFAULT_USDT_SLUGS: Map<MBlockchain, Map<MBlockchainNetwork, String>> = mapOf(
    MBlockchain.ton to mapOf(
        MBlockchainNetwork.MAINNET to TON_USDT_SLUG,
        MBlockchainNetwork.TESTNET to TON_USDT_TESTNET_SLUG
    ),
    MBlockchain.tron to mapOf(
        MBlockchainNetwork.MAINNET to TRON_USDT_SLUG,
        MBlockchainNetwork.TESTNET to TRON_USDT_TESTNET_SLUG
    ),
    MBlockchain.solana to mapOf(
        MBlockchainNetwork.MAINNET to SOLANA_USDT_SLUG
    ),
    MBlockchain.ethereum to mapOf(
        MBlockchainNetwork.MAINNET to ETH_USDT_MAINNET_SLUG,
        MBlockchainNetwork.TESTNET to ETH_USDT_MAINNET_SLUG
    ),
    MBlockchain.base to mapOf(
        MBlockchainNetwork.MAINNET to BASE_USDT_MAINNET_SLUG,
        MBlockchainNetwork.TESTNET to BASE_USDT_MAINNET_SLUG
    ),
    MBlockchain.bnb to mapOf(
        MBlockchainNetwork.MAINNET to BSC_USDT_MAINNET_SLUG,
        MBlockchainNetwork.TESTNET to BSC_USDT_MAINNET_SLUG
    ),
    MBlockchain.avalanche to mapOf(
        MBlockchainNetwork.MAINNET to AVALANCHE_USDT_MAINNET_SLUG,
        MBlockchainNetwork.TESTNET to AVALANCHE_USDT_MAINNET_SLUG
    )
)

private fun defaultSlugsForChain(chain: MBlockchain, network: MBlockchainNetwork): List<String> {
    val slugs = mutableListOf(chain.nativeSlug)
    CHAIN_DEFAULT_USDT_SLUGS[chain]?.get(network)?.let { slugs.add(it) }
    return slugs
}

fun defaultShownSlugs(account: MAccount): Set<String> {
    val network = account.network
    val supportedChains = MBlockchain.supportedChains.filter { account.isChainSupported(it.name) }
    if (ApplicationContextHolder.isGramApp) {
        return if (account.tonAddress != null) {
            defaultSlugsForChain(MBlockchain.ton, network).toSet()
        } else {
            defaultSlugsForChain(supportedChains.first(), network).toSet()
        }
    }
    return if (supportedChains.size == 1) {
        defaultSlugsForChain(supportedChains.first(), network).toSet()
    } else {
        supportedChains.map { it.nativeSlug }.toSet()
    }
}

const val DEFAULT_SWAP_VERSION = 3
const val MAX_PRICE_IMPACT_VALUE = 5.0

object WalletCore {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    val moshi: Moshi by lazy {
        MoshiBuilder.build()
    }

    val stores = listOf<IStore>(
        AccountStore, ActivityStore, AddressStore, AgentMessageStore, AuthStore, BalanceStore,
        ConfigStore, DappsStore, ExploreHistoryStore, NftStore, PortfolioStore, StakingStore,
        TokenStore
    )

    var bridge: JSWebViewBridge? = null
        private set
    private var pendingBridge: JSWebViewBridge? = null
    private val pendingBridgeSetupCallbacks = mutableListOf<(Boolean) -> Unit>()

    val requiredBridge: JSWebViewBridge
        get() = bridge ?: throw IllegalStateException("JS bridge is not initialized")
    var nextAccountId: String? = null
    var nextAccountIsPushedTemporary: Boolean? = null

    var baseCurrency = MBaseCurrency.valueOf(WGlobalStorage.getBaseCurrency())

    var bridgeUsers = 0
    fun incBridgeUsers() {
        bridgeUsers++
    }

    fun decBridgeUsers() {
        bridgeUsers--
        if (bridgeUsers == 0) destroyBridge()
    }
    // Events //////////////////////////////////////////////////////////////////////////////////////

    // Event observers
    interface EventObserver {
        fun onWalletEvent(walletEvent: WalletEvent)
    }

    private val eventObservers = ArrayList<WeakReference<EventObserver>>()
    private var lock = false

    // Notify observers ////////////////////////////////////////////////////////////////////////////
    private val expiredItems = ArrayList<WeakReference<EventObserver>>()
    fun notifyEvent(walletEvent: WalletEvent) {
        ensureMainThread {
            lock = true
            for (eventObserver in eventObservers) {
                if (eventObserver.get() == null) expiredItems.add(eventObserver)
            }
            if (expiredItems.isNotEmpty()) {
                eventObservers.removeAll(expiredItems.toSet())
                expiredItems.clear()
            }
            lock = false
            // Converted to list to prevent concurrent modification exception
            eventObservers.toList().forEach { it.get()?.onWalletEvent(walletEvent) }
        }
    }

    fun notifyAccountChanged(activeAccount: MAccount, fromHome: Boolean) {
        val accountId = activeAccount.accountId
        if (nextAccountIsPushedTemporary == true) {
            WGlobalStorage.setTemporaryAccountId(accountId, true)
        } else {
            WGlobalStorage.setActiveAccountId(accountId, persistInstantly = !fromHome)
        }
        nextAccountIsPushedTemporary = null
        nextAccountId = null
        AccountStore.updateActiveAccount(accountId)
        AddressStore.loadFromCache(accountId)
        NftStore.loadCachedNfts(accountId)
        ExploreHistoryStore.loadBrowserHistory(accountId)
        AccountStore.walletVersionsData = null
        AccountStore.updateAssetsAndActivityData(
            MAssetsAndActivityData(accountId),
            notify = false,
            saveToStorage = false
        )
        WalletCore.requestDAppList(accountId)
        // WalletContextManager.delegate?.protectedModeChanged()
        notifyEvent(
            WalletEvent.AccountChanged(
                accountId = accountId,
                fromHome = fromHome
            )
        )
    }

    fun updateAccentColor(accountId: String?) {
        accountId?.let {
            WGlobalStorage.getNftAccentColorIndex(accountId)?.let {
                setNftAccentColor(it)
                return
            }
        }
        setDefaultAccentColor()
    }

    // Register to observers / Unregister
    fun registerObserver(observer: EventObserver) {
        if (lock) throw IllegalStateException()

        eventObservers.add(WeakReference(observer))
    }

    fun unregisterObserver(observer: EventObserver) {
        eventObservers.removeAll {
            it.get() == observer
        }
    }

    // BRIDGE SETUP ////////////////////////////////////////////////////////////////////////////////
    fun setupBridge(
        context: Context,
        bridgeHostView: ViewGroup,
        forcedRecreation: Boolean,
        isOnAirApp: Boolean = true,
        onComplete: (Boolean) -> Unit
    ) {
        Logger.d(
            Logger.LogTag.JS_WEBVIEW_BRIDGE,
            "setupBridge: requested forced=$forcedRecreation activeBridgeId=${bridge?.id} pendingBridgeId=${pendingBridge?.id}"
        )

        val existingPendingBridge = pendingBridge
        if (!forcedRecreation && bridge == null &&
            existingPendingBridge != null && !existingPendingBridge.isRenderProcessGone
        ) {
            moveBridgeToHostIfNeeded(existingPendingBridge, bridgeHostView, isOnAirApp)
            pendingBridgeSetupCallbacks.add(onComplete)
            Logger.d(
                Logger.LogTag.JS_WEBVIEW_BRIDGE,
                "setupBridge: joined pending bridgeId=${existingPendingBridge.id} callbacks=${pendingBridgeSetupCallbacks.size}"
            )
            return
        }

        if (forcedRecreation || bridge == null) {
            existingPendingBridge?.let {
                pendingBridge = null
                completePendingBridgeSetup(false)
                disposeBridge(it)
                Logger.d(
                    Logger.LogTag.JS_WEBVIEW_BRIDGE,
                    "setupBridge: superseded pending bridgeId=${it.id}"
                )
            }

            val newBridge = JSWebViewBridge(context)
            newBridge.isVisible = false
            bridgeHostView.addView(newBridge)
            pendingBridge = newBridge
            pendingBridgeSetupCallbacks.add(onComplete)
            Logger.d(
                Logger.LogTag.JS_WEBVIEW_BRIDGE,
                "setupBridge: created pending bridgeId=${newBridge.id}"
            )
            newBridge.setupBridge bridgeReady@{
                if (pendingBridge !== newBridge) {
                    Logger.e(
                        Logger.LogTag.JS_WEBVIEW_BRIDGE,
                        "setupBridge: ignored stale ready bridgeId=${newBridge.id} pendingBridgeId=${pendingBridge?.id}"
                    )
                    disposeBridge(newBridge)
                    return@bridgeReady
                }
                if (newBridge.isRenderProcessGone) {
                    Logger.e(
                        Logger.LogTag.JS_WEBVIEW_BRIDGE,
                        "setupBridge: ignored ready from crashed bridgeId=${newBridge.id}"
                    )
                    pendingBridge = null
                    completePendingBridgeSetup(false)
                    disposeBridge(newBridge)
                    return@bridgeReady
                }

                val previousBridge = bridge
                val readyCallbackCount = pendingBridgeSetupCallbacks.size
                pendingBridge = null
                bridge = newBridge
                previousBridge?.let(::disposeBridge)
                Logger.i(
                    Logger.LogTag.JS_WEBVIEW_BRIDGE,
                    "setupBridge: promoted bridgeId=${newBridge.id} previousBridgeId=${previousBridge?.id} callbacks=$readyCallbackCount"
                )
                setupWalletCore()
                completePendingBridgeSetup(true)
            }
        } else {
            bridge?.let { existingBridge ->
                moveBridgeToHostIfNeeded(existingBridge, bridgeHostView, isOnAirApp)
            }
            doOnBridgeReady {
                onComplete(true)
            }
        }
    }

    private fun moveBridgeToHostIfNeeded(
        bridge: JSWebViewBridge,
        bridgeHostView: ViewGroup,
        isOnAirApp: Boolean
    ) {
        if (bridge.parent != bridgeHostView && isOnAirApp) {
            (bridge.parent as? ViewGroup)?.removeView(bridge)
            bridgeHostView.addView(bridge)
        }
    }

    private fun disposeBridge(deadBridge: JSWebViewBridge) {
        deadBridge.dispose()
    }

    private fun completePendingBridgeSetup(isReady: Boolean) {
        val callbacks = pendingBridgeSetupCallbacks.toList()
        pendingBridgeSetupCallbacks.clear()
        callbacks.forEach { it(isReady) }
    }

    fun destroyBridge() {
        val activeBridge = bridge
        val loadingBridge = pendingBridge
        bridge = null
        pendingBridge = null
        completePendingBridgeSetup(false)
        activeBridge?.let(::disposeBridge)
        if (loadingBridge !== activeBridge) loadingBridge?.let(::disposeBridge)
        observers.clear()
        eventObservers.clear()
    }

    val isBridgeReady: Boolean
        get() {
            return bridge?.injected == true && bridge?.isRenderProcessGone != true
        }

    fun onBridgeRenderProcessGone(goneBridge: JSWebViewBridge) {
        ensureMainThread {
            val role = when {
                bridge === goneBridge -> "active"
                pendingBridge === goneBridge -> "pending"
                else -> "stale"
            }
            Logger.e(
                Logger.LogTag.JS_WEBVIEW_BRIDGE,
                "onBridgeRenderProcessGone: bridgeId=${goneBridge.id} role=$role activeBridgeId=${bridge?.id} pendingBridgeId=${pendingBridge?.id}"
            )

            when (role) {
                "active" -> {
                    bridge = null
                    disposeBridge(goneBridge)
                    if (pendingBridge != null) {
                        Logger.i(
                            Logger.LogTag.JS_WEBVIEW_BRIDGE,
                            "onBridgeRenderProcessGone: waiting for pending bridgeId=${pendingBridge?.id}"
                        )
                        return@ensureMainThread
                    }
                }

                "pending" -> {
                    pendingBridge = null
                    completePendingBridgeSetup(false)
                    disposeBridge(goneBridge)
                }

                else -> {
                    disposeBridge(goneBridge)
                    return@ensureMainThread
                }
            }

            val delegate = WalletContextManager.delegate?.get()
            if (delegate == null) {
                Logger.e(
                    Logger.LogTag.JS_WEBVIEW_BRIDGE,
                    "onBridgeRenderProcessGone: no delegate for bridgeId=${goneBridge.id}, bridge not recreated"
                )
                return@ensureMainThread
            }
            Logger.i(
                Logger.LogTag.JS_WEBVIEW_BRIDGE,
                "onBridgeRenderProcessGone: recreating after bridgeId=${goneBridge.id} role=$role"
            )
            delegate.recreateBridge()
        }
    }

    var pendingBridgeReady: MutableList<() -> Unit>? = null

    // Used to ensure sdk bridge is already ready
    fun doOnBridgeReady(callback: () -> Unit) {
        if (isBridgeReady) {
            callback()
            return
        }
        if (pendingBridgeReady == null) pendingBridgeReady = mutableListOf()
        pendingBridgeReady?.add(callback)
    }

    @Synchronized
    fun checkPendingBridgeTasks() {
        if (!isBridgeReady) return
        pendingBridgeReady?.forEach {
            it()
        }
        pendingBridgeReady = null
    }

    private var setupDone = false
    private fun setupWalletCore() {
        if (setupDone) return
        setupDone = true
        registerConnectionChanges()
        StakingStore.loadCachedStates()
    }

    private fun registerConnectionChanges() {
        val networkCallback: NetworkCallback = object : NetworkCallback() {
            override fun onAvailable(network: Network) {
                Handler(Looper.getMainLooper()).post {
                    notifyEvent(WalletEvent.NetworkConnected)
                }
            }

            override fun onLost(network: Network) {
                Handler(Looper.getMainLooper()).post {
                    notifyEvent(WalletEvent.NetworkDisconnected)
                }
            }
        }

        val connectivityManager =
            (bridge?.context ?: ApplicationContextHolder.applicationContext)
                .getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            connectivityManager.registerDefaultNetworkCallback(networkCallback)
        } else {
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build()
            connectivityManager.registerNetworkCallback(request, networkCallback)
        }

        // Now check the current state and notify observers
        if (eventObservers.isNotEmpty()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val networkCapabilities =
                    connectivityManager.getNetworkCapabilities(connectivityManager.activeNetwork)
                if (networkCapabilities?.hasCapability(
                        NetworkCapabilities.NET_CAPABILITY_INTERNET
                    ) ==
                    true
                ) {
                    notifyEvent(WalletEvent.NetworkConnected)
                } else {
                    notifyEvent(WalletEvent.NetworkDisconnected)
                }
            } else {
                val activeNetworkInfo = connectivityManager.activeNetworkInfo
                if (activeNetworkInfo?.isConnected == true) {
                    notifyEvent(WalletEvent.NetworkConnected)
                } else {
                    notifyEvent(WalletEvent.NetworkDisconnected)
                }
            }
        }
    }

    fun isConnected(): Boolean {
        val connectivityManager =
            (bridge?.context ?: ApplicationContextHolder.applicationContext)
                .getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return false

        val networkCapabilities =
            connectivityManager.getNetworkCapabilities(connectivityManager.activeNetwork)
        return networkCapabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ==
            true
    }

    fun getAllAccounts(): List<MAccount> {
        val allAccountsString = WSecureStorage.allAccounts()
        if (allAccountsString.isEmpty()) return emptyList()
        val accountIds = WGlobalStorage.accountIds()
        val accounts = ArrayList<MAccount>()
        for (accountId in accountIds) {
            try {
                val globalJSON = WGlobalStorage.getAccount(accountId) ?: continue
                val account = MAccount(
                    accountId = accountId,
                    globalJSON = globalJSON
                )
                accounts.add(account)
            } catch (_: Exception) {
            }
        }
        return accounts
    }

    object Swap
    object Transfer

    suspend fun <T> call(method: ApiMethod<T>): T =
        requiredBridge.callApiAsync(method.name, method.arguments, method.type)

    fun <T> call(method: ApiMethod<T>, callback: (String?, T?, JSWebViewBridge.ApiError?) -> Unit) {
        bridge?.callApi(method.name, method.arguments, method.type, callback)
    }

    fun <T> call(method: ApiMethod<T>, callback: (T?, JSWebViewBridge.ApiError?) -> Unit) {
        call(method) { _, res, err -> callback.invoke(res, err) }
    }

    // Fire-and-forget TON Connect analytics event, called from the UI view controllers (single home for the
    // bridge call so the three UITonConnect screens do not each carry a copy of the helper).
    fun recordTonConnectEvent(eventName: String, promiseId: String) {
        call(ApiMethod.DApp.RecordTonConnectEvent(eventName, promiseId)) { _, _ -> }
    }

    /* This code allows to receive updates directly from the api bridge */

    private val observers = mutableMapOf<Class<out ApiUpdate>, MutableSet<UpdatesObserver>>()

    interface UpdatesObserver {
        fun onBridgeUpdate(update: ApiUpdate)
    }

    fun <T : ApiUpdate> subscribeToApiUpdates(type: Class<T>, observer: UpdatesObserver) {
        observers[type]?.add(observer) ?: run {
            observers[type] = mutableSetOf(observer)
        }
    }

    fun <T : ApiUpdate> unsubscribeFromApiUpdates(type: Class<T>, observer: UpdatesObserver) {
        observers[type]?.remove(observer)
    }

    fun <T : ApiUpdate> notifyApiUpdate(update: T) {
        when (update) {
            is ApiUpdate.ApiUpdateDappConnectComplete,
            is ApiUpdate.ApiUpdateDapps -> WalletCore.requestDAppList()

            is ApiUpdate.ApiUpdateDappDisconnect -> {
                WalletCore.requestDAppList()
                notifyEvent(WalletEvent.DappDisconnect(update.accountId, update.url))
            }

            is ApiUpdate.ApiUpdateTokens -> {
                TokenStore.setFlowValue(
                    TokenStore.Tokens(update.tokens)
                )
            }

            is ApiUpdate.ApiUpdateInitialActivities -> {
                if (AccountStore.activeAccountId != update.accountId) return
                ActivityStore.initialActivities(
                    accountId = update.accountId,
                    chain = update.chain,
                    mainActivities = update.mainActivities,
                    bySlug = update.bySlug
                )
            }

            is ApiUpdate.ApiUpdateWalletVersions -> {
                if (AccountStore.activeAccountId != update.accountId) return
                AccountStore.walletVersionsData = update
            }

            is ApiUpdate.ApiUpdateCurrencyRates -> {
                TokenStore.updateCurrencyRates(update)
                BalanceStore.resetBalanceInBaseCurrency()
            }

            is ApiUpdate.ApiUpdateUpdateAccount -> {
                AccountStore.updateAccountData(update)
            }

            else -> {}
        }

        val iterator = observers[update::class.java] ?: return
        if (iterator.isNotEmpty()) {
            Handler(Looper.getMainLooper()).post {
                iterator.forEach { it.onBridgeUpdate(update) }
            }
        }
    }

    fun ensureAccountActivated(accountId: String, onCompletion: (accountChanged: Boolean) -> Unit) {
        if (AccountStore.activeAccountId == accountId) {
            onCompletion(false)
            return
        }
        WalletCore.activateAccount(
            accountId,
            notifySDK = true
        ) { res, err ->
            if (res == null || err != null) {
                // Should not happen! Continuing with a half-switched account context is
                // unsafe, so fail (same as switchToDisplayedAccountId).
                Logger.e(
                    Logger.LogTag.ACCOUNT,
                    LogMessage.Builder()
                        .append(
                            "activateAccount: Failed err=$err",
                            LogMessage.MessagePartPrivacy.PUBLIC
                        ).build()
                )
                throw Error("activateAccount failed: $err")
            } else {
                onCompletion(true)
            }
        }
    }
}
