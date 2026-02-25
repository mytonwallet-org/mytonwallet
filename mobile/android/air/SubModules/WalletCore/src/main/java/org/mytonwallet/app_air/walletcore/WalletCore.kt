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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager.setDefaultAccentColor
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager.setNftAccentColor
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcontext.utils.ensureMainThread
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.api.requestDAppList
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MAssetsAndActivityData
import org.mytonwallet.app_air.walletcore.moshi.MoshiBuilder
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ActivityStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import org.mytonwallet.app_air.walletcore.stores.AuthStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.DappsStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import org.mytonwallet.app_air.walletcore.stores.IStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference

const val TON_CHAIN = "ton"

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
const val VIRTUAL_STAKING_SLUG_PREFIX = "staking-"
const val TON_DNS_COLLECTION = "EQC3dNlesgVD8YbAazcauIrXBPfiVhMMr5YYk2in0Mtsz0Bz"
const val MTW_CARDS_COLLECTION = "EQCQE2L9hfwx1V8sgmF9keraHx1rNK9VmgR1ctVvINBGykyM"

val STAKING_SLUGS = listOf(
    STAKE_SLUG, STAKED_MYCOIN_SLUG, STAKED_USDE_SLUG
)

fun tokenSlugToStakingSlug(slug: String): String? {
    return when (slug) {
        TONCOIN_SLUG -> STAKE_SLUG
        MYCOIN_SLUG -> STAKED_MYCOIN_SLUG
        USDE_SLUG -> STAKED_USDE_SLUG
        else -> null
    }
}

fun stakingSlugToTokenSlug(stakingSlug: String): String? {
    return when (stakingSlug) {
        STAKE_SLUG, TONCOIN_SLUG -> TONCOIN_SLUG
        STAKED_MYCOIN_SLUG, MYCOIN_SLUG -> MYCOIN_SLUG
        STAKED_USDE_SLUG, USDE_SLUG -> USDE_SLUG
        else -> null
    }
}

fun buildVirtualStakingSlug(baseSlug: String): String {
    return "$VIRTUAL_STAKING_SLUG_PREFIX$baseSlug"
}

val POPULAR_WALLET_VERSIONS = listOf(
    "v3R1", "v3R2", "v4R2", "W5"
)

val PRICELESS_TOKEN_HASHES = setOf(
    "173e31eee054cb0c76f77edc7956bed766bf48a1f63bd062d87040dcd3df700f", // FIVA SY tsTON EQAxGi9Al7hamLAORroxGkvfap6knGyzI50ThkP3CLPLTtOZ
    "5226dd4e6db9af26b24d5ca822bc4053b7e08152f923932abf25030c7e38bb42", // FIVA PT tsTON EQAkxIRGXgs2vD2zjt334MBjD3mXg2GsyEZHfzuYX_trQkFL
    "fea2c08a704e5192b7f37434927170440d445b87aab865c3ea2a68abe7168204", // FIVA YT tsTON EQAcy60qg22RCq87A_qgYK8hooEgjCZ44yxhdnKYdlWIfKXL
    "e691cf9081a8aeb22ed4d94829f6626c9d822752e035800b5543c43f83d134b5", // FIVA LP tsTON EQD3BjCjxuf8mu5kvxajVbe-Ila1ScZZlAi03oS7lMmAJjM3
    "301ce25925830d713b326824e552e962925c4ff45b1e3ea21fc363a459a49b43", // FIVA SY eUSDT EQDi9blCcyT-k8iMpFMYY0t7mHVyiCB50ZsRgyUECJDuGvIl
    "02250f83fbb8624d859c2c045ac70ee2b3b959688c3d843aec773be9b36dbfc3", // FIVA PT eUSDT EQBzVrYkYPHx8D_HPfQacm1xONa4XSRxl826vHkx_laP2HOe
    "dba3adb2c917db80fd71a6a68c1fc9e12976491a8309d5910f9722efc084ce4d", // FIVA YT eUSDT EQCwUSc2qrY5rn9BfFBG9ARAHePTUvITDl97UD0zOreWzLru
    "7da9223b90984d6a144e71611a8d7c65a6298cad734faed79438dc0f7a8e53d1", // FIVA LP eUSDT EQBNlIZxIbQGQ78cXgG3VRcyl8A0kLn_6BM9kabiHHhWC4qY
    "ddf80de336d580ab3c11d194f189c362e2ca1225cae224ea921deeaba7eca818", // tsUSDe EQDQ5UUyPHrLcQJlPAczd_fjxn8SLrlNQwolBznxCdSlfQwr
)

val DEFAULT_SHOWN_TOKENS = mapOf(
    MBlockchainNetwork.MAINNET to setOf(
        TONCOIN_SLUG,
        TON_USDT_SLUG,
        TRON_SLUG,
        TRON_USDT_SLUG,
        SOLANA_SLUG,
        SOLANA_USDT_SLUG,
    ),
    MBlockchainNetwork.TESTNET to setOf(
        TONCOIN_SLUG,
        TON_USDT_TESTNET_SLUG,
        TRON_SLUG,
        TRON_USDT_TESTNET_SLUG,
        SOLANA_SLUG,
    ),
)

val TRUSTED_USDT_TOKENS = mapOf(
    MBlockchainNetwork.MAINNET to setOf(
        TON_USDT_SLUG,
        TRON_USDT_SLUG,
        SOLANA_USDT_SLUG,
    ),
    MBlockchainNetwork.TESTNET to setOf(
        TON_USDT_TESTNET_SLUG,
        TRON_USDT_TESTNET_SLUG,
    ),
)

fun getTrustedUsdtTokens(network: MBlockchainNetwork?): Set<String> {
    return network?.let {
        TRUSTED_USDT_TOKENS[it]
    } ?: TRUSTED_USDT_TOKENS.values.flatten().toSet()
}

val DEFAULT_SWAP_VERSION = 3
val MAX_PRICE_IMPACT_VALUE = 5.0

object WalletCore {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    val moshi: Moshi by lazy {
        MoshiBuilder.build()
    }

    val stores = listOf<IStore>(
        AccountStore, ActivityStore, AddressStore, AuthStore, BalanceStore,
        ConfigStore, DappsStore, ExploreHistoryStore, NftStore, StakingStore, TokenStore
    )

    var bridge: JSWebViewBridge? = null
        private set
    var nextAccountId: String? = null
    var nextAccountIsPushedTemporary: Boolean? = null

    var baseCurrency = MBaseCurrency.valueOf(WGlobalStorage.getBaseCurrency())

    var bridgeUsers = 0
    fun incBridgeUsers() {
        bridgeUsers++
    }

    fun decBridgeUsers() {
        bridgeUsers--
        if (bridgeUsers == 0)
            destroyBridge()
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
                if (eventObserver.get() == null)
                    expiredItems.add(eventObserver)
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
        if (nextAccountIsPushedTemporary == true)
            WGlobalStorage.setTemporaryAccountId(accountId, true)
        else
            WGlobalStorage.setActiveAccountId(accountId, persistInstantly = !fromHome)
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
        //WalletContextManager.delegate?.protectedModeChanged()
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

    fun switchingToLegacy() {
        WGlobalStorage.setTokenInfo(TokenStore.getTokenInfo())
        WGlobalStorage.clearPriceHistory()
        AccountStore.removeTemporaryAccounts()
        destroyBridge()
        WSecureStorage.clearCache()
        /*if (WGlobalStorage.getLangCode() == "fa")
            WGlobalStorage.setLangCode("en")*/
        WCacheStorage.clean(WGlobalStorage.accountIds())
        WCacheStorage.setInitialScreen(WCacheStorage.InitialScreen.INTRO)
        observers.clear()
        eventObservers.clear()
        stores.forEach { it.clearCache() }
    }

    // Register to observers / Unregister
    fun registerObserver(observer: EventObserver) {
        if (lock)
            throw IllegalStateException()

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
        onReady: () -> Unit
    ) {
        if (forcedRecreation || bridge == null) {
            val newBridge = JSWebViewBridge(context)
            newBridge.isVisible = false
            bridgeHostView.addView(newBridge)
            newBridge.setupBridge {
                bridge?.destroy()
                bridge = newBridge
                setupWalletCore()
                onReady()
            }
        } else {
            if (bridge!!.parent != bridgeHostView && isOnAirApp) {
                (bridge!!.parent as? ViewGroup)?.removeView(bridge)
                bridgeHostView.addView(bridge)
            }
            doOnBridgeReady {
                onReady()
            }
        }
    }

    fun destroyBridge() {
        bridge?.destroy()
        bridge = null
        observers.clear()
        eventObservers.clear()
    }

    val isBridgeReady: Boolean
        get() {
            return bridge?.injected == true
        }

    var pendingBridgeReady: MutableList<() -> Unit>? = null

    // Used to ensure sdk bridge is already ready
    fun doOnBridgeReady(callback: () -> Unit) {
        if (bridge?.injected == true) {
            callback()
            return
        }
        if (pendingBridgeReady == null)
            pendingBridgeReady = mutableListOf()
        pendingBridgeReady?.add(callback)
    }

    @Synchronized
    fun checkPendingBridgeTasks() {
        if (bridge?.injected != true)
            return
        pendingBridgeReady?.forEach {
            it()
        }
        pendingBridgeReady = null
    }

    private var setupDone = false
    private fun setupWalletCore() {
        if (setupDone)
            return
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
            bridge?.context?.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

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
                if (networkCapabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true) {
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
            bridge?.context?.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val networkCapabilities =
                connectivityManager.getNetworkCapabilities(connectivityManager.activeNetwork)
            return networkCapabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        } else {
            val activeNetworkInfo = connectivityManager.activeNetworkInfo
            return activeNetworkInfo?.isConnected == true
        }
    }

    fun getAllAccounts(): List<MAccount> {
        val allAccountsString = WSecureStorage.allAccounts()
        if (allAccountsString.isEmpty())
            return emptyList()
        val accountIds = WGlobalStorage.accountIds()
        val accounts = ArrayList<MAccount>()
        for (accountId in accountIds) {
            try {
                val account = MAccount(
                    accountId = accountId,
                    globalJSON = WGlobalStorage.getAccount(accountId)!!
                )
                accounts.add(account)
            } catch (_: Exception) {
            }
        }
        return accounts
    }

    object Swap
    object Transfer

    suspend fun <T> call(method: ApiMethod<T>): T {
        return bridge!!.callApiAsync(method.name, method.arguments, method.type)
    }

    fun <T> call(method: ApiMethod<T>, callback: (String?, T?, JSWebViewBridge.ApiError?) -> Unit) {
        bridge?.callApi(method.name, method.arguments, method.type, callback)
    }

    fun <T> call(method: ApiMethod<T>, callback: (T?, JSWebViewBridge.ApiError?) -> Unit) {
        call(method) { _, res, err -> callback.invoke(res, err) }
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
            is ApiUpdate.ApiUpdateDappDisconnect,
            is ApiUpdate.ApiUpdateDapps -> WalletCore.requestDAppList()

            is ApiUpdate.ApiUpdateTokens -> {
                TokenStore.setFlowValue(
                    TokenStore.Tokens(update.tokens)
                )
            }

            is ApiUpdate.ApiUpdateInitialActivities -> {
                if (AccountStore.activeAccountId != update.accountId)
                    return
                ActivityStore.initialActivities(
                    accountId = update.accountId,
                    chain = update.chain,
                    mainActivities = update.mainActivities,
                    bySlug = update.bySlug
                )
            }

            is ApiUpdate.ApiUpdateWalletVersions -> {
                if (AccountStore.activeAccountId != update.accountId)
                    return
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
        if (iterator.isNotEmpty())
            Handler(Looper.getMainLooper()).post {
                iterator.forEach { it.onBridgeUpdate(update) }
            }
    }

    fun ensureAccountActivated(
        accountId: String,
        onCompletion: (accountChanged: Boolean) -> Unit
    ) {
        if (AccountStore.activeAccountId == accountId) {
            onCompletion(false)
            return
        }
        WalletCore.activateAccount(
            accountId,
            notifySDK = true
        ) { res, err ->
            if (res == null || err != null) {
                // Should not happen!
                Logger.e(
                    Logger.LogTag.ACCOUNT,
                    LogMessage.Builder()
                        .append(
                            "activateAccount: Failed err=$err",
                            LogMessage.MessagePartPrivacy.PUBLIC
                        ).build()
                )
            } else {
                onCompletion(true)
            }
        }
    }
}
