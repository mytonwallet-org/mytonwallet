package org.mytonwallet.app_air.walletcore

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewCompat
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.JsonReader
import com.squareup.moshi.Types
import java.lang.reflect.Type
import java.math.BigInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okio.Buffer
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.native_enclave.EnclaveManager
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.utils.decodeUrlOrNull
import org.mytonwallet.app_air.walletbasecontext.utils.takeIfNotBlank
import org.mytonwallet.app_air.walletbasecontext.utils.toHashMapLong
import org.mytonwallet.app_air.walletbasecontext.utils.toHashMapString
import org.mytonwallet.app_air.walletbasecontext.utils.toJSONString
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.sdkStorage.WSdkStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcontext.utils.ensureMainThread
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.MUpdateStaking
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ActivityStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.EnvironmentStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

val INIT_SCRIPT
    get() =
        "window.airBridge.initApi((data) => {androidApp.onUpdate(JSON.stringify(data))}, {isAndroidApp: true, langCode: '${LocaleController.activeLanguage.langCode}'})"

@SuppressLint("SetJavaScriptEnabled")
class JSWebViewBridge(context: Context) : WebView(context) {

    init {
        id = generateViewId()
    }

    internal fun setupBridge(onBridgeReady: () -> Unit) {
        setWebContentsDebuggingEnabled(DEBUG_MODE)
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.allowFileAccessFromFileURLs = false
        settings.allowUniversalAccessFromFileURLs = false
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW

        settings.setRenderPriority(WebSettings.RenderPriority.LOW)
        val webViewVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WebViewCompat.getCurrentWebViewPackage(context)?.versionName
        } else {
            ""
        }

        Logger.d(
            Logger.LogTag.JS_WEBVIEW_BRIDGE,
            "setupBridge: bridgeId=$id WebViewVersion=$webViewVersion"
        )

        loadUrl("file:///android_asset/js/index.html")

        addJavascriptInterface(JsWebInterface(this), "androidApp")
        webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                post {
                    injectIfNeeded(onBridgeReady)
                }
            }

            override fun onRenderProcessGone(
                view: WebView?,
                detail: RenderProcessGoneDetail?
            ): Boolean {
                val didCrash = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    detail?.didCrash()
                } else {
                    null
                }
                val rendererPriorityAtExit =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        detail?.rendererPriorityAtExit()
                    } else {
                        null
                    }
                Logger.e(
                    Logger.LogTag.JS_WEBVIEW_BRIDGE,
                    "onRenderProcessGone: bridgeId=$id didCrash=$didCrash " +
                        "rendererPriorityAtExit=$rendererPriorityAtExit injecting=$injecting " +
                        "injected=$injected pendingCallbacks=${callbackRegistry.pendingCount} " +
                        getMemoryStateForLog()
                )
                isRenderProcessGone = true
                injecting = false
                injected = false
                failPendingCallbacks(MBridgeError.Type.BRIDGE_INTERRUPTED)
                WalletCore.onBridgeRenderProcessGone(this@JSWebViewBridge)
                return true
            }
        }
    }

    var isRenderProcessGone: Boolean = false
        private set

    private var isDisposed: Boolean = false

    private var injecting: Boolean = false
    var injected: Boolean = false
        private set

    private fun injectIfNeeded(onBridgeReady: () -> Unit) {
        if (isRenderProcessGone || isDisposed || injecting || injected) return
        injecting = true

        // Inject the init script
        evaluateJavascript(INIT_SCRIPT) { res ->
            if (isRenderProcessGone || isDisposed) {
                Logger.e(
                    Logger.LogTag.JS_WEBVIEW_BRIDGE,
                    "injectIfNeeded: ignored completion for unavailable bridgeId=$id"
                )
                return@evaluateJavascript
            }
            if (res.equals("null")) {
                injected = true
                onBridgeReady()
                EnvironmentStore.loadEnvVariable()
            } else {
                injecting = false
                Handler(context.mainLooper).postDelayed({
                    injectIfNeeded(onBridgeReady)
                }, 500)
            }
        }
    }

    internal fun dispose() {
        if (isDisposed) return
        isDisposed = true
        injecting = false
        injected = false
        failPendingCallbacks(MBridgeError.Type.BRIDGE_INTERRUPTED)
        (parent as? ViewGroup)?.removeView(this)
        destroy()
    }

    private fun getMemoryStateForLog(): String {
        return try {
            val activityManager =
                context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                    ?: return "systemMemory=unavailable"
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            val bytesPerMegabyte = 1024L * 1024L
            "systemLowMemory=${memoryInfo.lowMemory} " +
                "availableMemoryMb=${memoryInfo.availMem / bytesPerMegabyte} " +
                "lowMemoryThresholdMb=${memoryInfo.threshold / bytesPerMegabyte}"
        } catch (e: Exception) {
            "systemMemory=unavailable error=${e.javaClass.simpleName}"
        }
    }

    private var callIdentifier: Int = 0
    private val callbackRegistry = BridgeCallbackRegistry()

    private fun failPendingCallbacks(error: MBridgeError) {
        callbackRegistry.failAll(error)
    }

    internal fun callApi(
        methodName: String,
        args: String,
        callback: (result: String?, error: MBridgeError?) -> Unit
    ) {
        callIdentifier += 1
        val thisCallIdentifier = callIdentifier
        callbackRegistry.register(thisCallIdentifier, callback)
        val script = "if (!window.airBridge?.callApi) {\n" +
            "androidApp.callback($thisCallIdentifier, false, 'airBridge not working!');" +
            "} else {" +
            "   let call = window.airBridge.callApi('$methodName',...JSON.parse(${
                JSONObject.quote(args)
            }, window.airBridge.bigintReviver));" +
            "   if (call?.then) {" +
            "       call.then((res) => {" +
            "           if (res?.error || res?.err) {" +
            "               androidApp.callback($thisCallIdentifier, false, JSON.stringify(res))" +
            "           } else {" +
            "               androidApp.callback($thisCallIdentifier, true, JSON.stringify(res))" +
            "       }})" +
            "       .catch((e) => {" +
            "console.log(e);" +
            "androidApp.callback($thisCallIdentifier, false, JSON.stringify(e))" +
            "})" +
            "   } else {" +
            "       androidApp.callback($thisCallIdentifier, true, JSON.stringify(call))" +
            "   }" +
            "}"
        evaluateJavascript(script) { }
    }

    class JsWebInterface(val bridge: JSWebViewBridge) {
        companion object {
            private val sdkStorageKeys = setOf(
                "agentMessages",
                "agentConversationId",
                "headlessBalanceSnapshots",
                "walletOperationIntents",
                "activeCexSwapReconciliationState",
                "knownTonAggregatorTraceIds",
                "knownTonAggregatorTraceProjections"
            )

            internal fun usesSecureStorage(key: String): Boolean = key !in sdkStorageKeys
        }

        @JavascriptInterface
        fun logDebugError(tag: String, args: String) {
            Logger.e(Logger.LogTag.JS_DEBUG_ERROR, "[$tag] $args")
        }

        @JavascriptInterface
        fun callback(identifier: Int, success: Boolean, result: String) {
            bridge.post {
                bridge.callbackRegistry.complete(identifier, success, result)
            }
        }

        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

        private fun getStorageValue(key: String): String {
            if (usesSecureStorage(key)) return WSecureStorage.getSecValue(key)

            val sdkValue = WSdkStorage.getValue(key)
            if (sdkValue.isNotEmpty() || WSdkStorage.contains(key)) return sdkValue

            val legacyValue = WSecureStorage.getSecValue(key)
            if (legacyValue.isNotEmpty() && WSdkStorage.migrateValue(key, legacyValue)) {
                WSecureStorage.removeSecValue(key)
            }
            return legacyValue
        }

        private fun setStorageValue(key: String, value: String) {
            if (usesSecureStorage(key)) {
                WSecureStorage.setSecValue(key, value)
            } else {
                WSdkStorage.setValue(key, value)
                WSecureStorage.removeSecValue(key)
            }
        }

        private fun removeStorageValue(key: String) {
            if (usesSecureStorage(key)) {
                WSecureStorage.setSecValue(key, "")
            } else {
                WSdkStorage.removeValue(key)
                WSecureStorage.removeSecValue(key)
            }
        }

        private fun peekUpdateType(updateString: String): String? {
            val reader = JsonReader.of(Buffer().writeUtf8(updateString))
            return try {
                if (reader.peek() != JsonReader.Token.BEGIN_OBJECT) return null
                reader.beginObject()
                while (reader.hasNext()) {
                    if (reader.nextName() == "type") {
                        return if (reader.peek() ==
                            JsonReader.Token.STRING
                        ) {
                            reader.nextString()
                        } else {
                            null
                        }
                    }
                    reader.skipValue()
                }
                null
            } catch (_: Exception) {
                null
            } finally {
                try {
                    reader.close()
                } catch (_: Exception) {
                }
            }
        }

        private fun streamUpdateTokens(updateString: String) {
            val reader = JsonReader.of(Buffer().writeUtf8(updateString))
            try {
                reader.beginObject()
                while (reader.hasNext()) {
                    if (reader.nextName() != "tokens") {
                        reader.skipValue()
                        continue
                    }
                    if (reader.peek() != JsonReader.Token.BEGIN_OBJECT) {
                        reader.skipValue()
                        continue
                    }
                    reader.beginObject()
                    while (reader.hasNext()) {
                        val slug = reader.nextName()
                        val tokenJsonString = reader.nextSource().readUtf8()
                        try {
                            val token = MToken(JSONObject(tokenJsonString))
                            TokenStore.setToken(slug, token)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            Logger.w(
                                Logger.LogTag.JS_WEBVIEW_BRIDGE,
                                "updateTokens: skipped invalid token slug=$slug error=${e.javaClass.simpleName}"
                            )
                        }
                    }
                    reader.endObject()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Logger.e(
                    Logger.LogTag.JS_WEBVIEW_BRIDGE,
                    "updateTokens: failed to parse update error=${e.javaClass.simpleName}"
                )
            } finally {
                try {
                    reader.close()
                } catch (_: Exception) {
                }
            }
            TokenStore.updateTokensCache()
            BalanceStore.resetBalanceInBaseCurrency()
            Handler(Looper.getMainLooper()).post {
                WalletCore.notifyEvent(WalletEvent.TokensChanged)
            }
        }

        private fun streamUpdateSwapTokens(updateString: String) {
            val reader = JsonReader.of(Buffer().writeUtf8(updateString))
            val tokens = ArrayList<MToken>()
            try {
                reader.beginObject()
                while (reader.hasNext()) {
                    if (reader.nextName() != "tokens") {
                        reader.skipValue()
                        continue
                    }
                    if (reader.peek() != JsonReader.Token.BEGIN_OBJECT) {
                        reader.skipValue()
                        continue
                    }
                    reader.beginObject()
                    while (reader.hasNext()) {
                        reader.nextName()
                        val tokenJsonString = reader.nextSource().readUtf8()
                        try {
                            tokens.add(MToken(JSONObject(tokenJsonString)))
                        } catch (e: Exception) {
                            Logger.w(
                                Logger.LogTag.JS_WEBVIEW_BRIDGE,
                                "updateSwapTokens: skipped invalid token error=${e.javaClass.simpleName}"
                            )
                        }
                    }
                    reader.endObject()
                }
            } catch (e: Exception) {
                Logger.e(
                    Logger.LogTag.JS_WEBVIEW_BRIDGE,
                    "updateSwapTokens: failed to parse update error=${e.javaClass.simpleName}"
                )
                return
            } finally {
                try {
                    reader.close()
                } catch (_: Exception) {
                }
            }
            TokenStore.setSwapAssets(tokens)
            TokenStore.updateSwapCache()
            Handler(Looper.getMainLooper()).post {
                TokenStore.isLoadingSwapAssets = false
                WalletCore.notifyEvent(WalletEvent.TokensChanged)
            }
        }

        @Deprecated("Use moshi ApiUpdate")
        private fun parseUpdate(updateString: String) {
            val updateType = peekUpdateType(updateString) ?: return
            when (updateType) {
                "updateTokens" -> {
                    streamUpdateTokens(updateString)
                    return
                }

                "updateSwapTokens" -> {
                    streamUpdateSwapTokens(updateString)
                    return
                }
            }
            val objectJSONObject = JSONObject(updateString)
            when (updateType) {
                "updateBalances" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    Handler(Looper.getMainLooper()).post {
                        val balances = HashMap<String, BigInteger>()
                        scope.launch {
                            val balancesToUpdate =
                                objectJSONObject.optJSONObject("balances")
                                    ?: return@launch
                            for (token in balancesToUpdate.keys()) {
                                val valueString: String =
                                    balancesToUpdate.optString(token).substringAfter("bigint:")
                                val value =
                                    if (valueString.isNotEmpty()) {
                                        valueString.toBigInteger()
                                    } else {
                                        BigInteger.valueOf(
                                            0
                                        )
                                    }
                                balances[token] = value
                            }
                            withContext(Dispatchers.Main) {
                                BalanceStore.setBalances(accountId, balances, false) {
                                    if (AccountStore.activeAccount?.accountId != accountId) {
                                        WalletCore.notifyEvent(
                                            WalletEvent.NotActiveAccountBalanceChanged
                                        )
                                    } else {
                                        WalletCore.notifyEvent(WalletEvent.BalanceChanged)
                                    }
                                }
                            }
                        }
                    }
                }

                "updatingStatus" -> {
                    val kind = objectJSONObject.optString("kind")
                    Handler(Looper.getMainLooper()).post {
                        when (kind) {
                            "activities" -> {
                                AccountStore.updatingActivities =
                                    objectJSONObject.optBoolean("isUpdating")
                            }

                            "balance" -> {
                                AccountStore.updatingBalance =
                                    objectJSONObject.optBoolean("isUpdating")
                            }
                        }
                        Handler(Looper.getMainLooper()).post {
                            WalletCore.notifyEvent(WalletEvent.UpdatingStatusChanged)
                        }
                    }
                }

                "newLocalActivities" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    if (AccountStore.activeAccount?.accountId != accountId) {
                        return
                    }
                    val transactionJSONArray = objectJSONObject.optJSONArray("activities") ?: return
                    val localTransactions = ArrayList<MApiTransaction>()
                    for (index in 0..<transactionJSONArray.length()) {
                        val transactionObj = transactionJSONArray.getJSONObject(index)
                        val transaction = MApiTransaction.fromJson(transactionObj)
                        if (transaction == null) {
                            Logger.e(
                                Logger.LogTag.JS_WEBVIEW_BRIDGE,
                                "newLocalActivities: dropped unparsable activity"
                            )
                            throw Exception()
                        }
                        localTransactions.add(transaction)
                    }
                    ActivityStore.receivedLocalTransactions(
                        accountId,
                        localTransactions.toTypedArray()
                    )
                    WalletCore.notifyEvent(
                        WalletEvent.NewLocalActivities(
                            accountId,
                            localTransactions
                        )
                    )
                }

                "newActivities" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    if (AccountStore.activeAccount?.accountId != accountId) {
                        return
                    }
                    val transactionJSONArray =
                        objectJSONObject.optJSONArray("activities") ?: JSONArray()
                    val pendingTransactionsJSONArray =
                        objectJSONObject.optJSONArray("pendingActivities")
                    val chain = objectJSONObject.optString("chain")
                        .takeIfNotBlank()
                        ?.let { runCatching { MBlockchain.valueOf(it) }.getOrNull() }
                    try {
                        val transactions = ArrayList<MApiTransaction>()
                        for (index in 0..<transactionJSONArray.length()) {
                            val transactionObj = transactionJSONArray.getJSONObject(index)
                            val transaction = MApiTransaction.fromJson(transactionObj)
                            if (transaction == null) {
                                Logger.e(
                                    Logger.LogTag.JS_WEBVIEW_BRIDGE,
                                    "newActivities: dropped unparsable activity"
                                )
                                throw Exception()
                            }
                            transactions.add(transaction)
                        }
                        val pendingTransactions = pendingTransactionsJSONArray?.let { jsonArray ->
                            ArrayList<MApiTransaction>().apply {
                                for (index in 0..<jsonArray.length()) {
                                    val transactionObj = jsonArray.getJSONObject(index)
                                    val transaction = MApiTransaction.fromJson(transactionObj)
                                    if (transaction == null) {
                                        Logger.e(
                                            Logger.LogTag.JS_WEBVIEW_BRIDGE,
                                            "newActivities: dropped unparsable pending activity"
                                        )
                                        throw Exception()
                                    }
                                    add(transaction)
                                }
                            }
                        }
                        pendingTransactions?.takeIf { it.isNotEmpty() }?.let {
                            Handler(Looper.getMainLooper()).post {
                                WalletCore.notifyEvent(
                                    WalletEvent.ReceivedPendingActivities(
                                        accountId,
                                        it
                                    )
                                )
                            }
                        }
                        ActivityStore.newActivities(
                            context = bridge.context,
                            accountId = accountId,
                            newActivities = transactions,
                            pendingActivities = pendingTransactions,
                            chain = chain
                        )
                    } catch (e: Exception) {
                        Logger.e(
                            Logger.LogTag.JS_WEBVIEW_BRIDGE,
                            "newActivities: failed to process update error=${e.javaClass.simpleName}"
                        )
                    }
                }

                "updateStaking" -> {
                    val accountId = objectJSONObject.optString("accountId")

                    val stakingAdapter: JsonAdapter<MUpdateStaking> =
                        WalletCore.moshi.adapter(MUpdateStaking::class.java)
                    val stakingData = stakingAdapter.fromJson(updateString)
                    StakingStore.setStakingState(accountId, stakingData)

                    ensureMainThread {
                        WalletCore.notifyEvent(WalletEvent.StakingDataUpdated)
                    }
                }

                "updateNfts" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    val collectionAddress = objectJSONObject.optString("collectionAddress")
                    val chainRaw = objectJSONObject.optString("chain")
                    val chain = MBlockchain.valueOfOrNull(chainRaw)
                    val isFullLoading = objectJSONObject.opt("isFullLoading") as? Boolean
                    val streamedAddresses =
                        objectJSONObject.optJSONArray("streamedAddresses")?.let { array ->
                            buildSet {
                                for (index in 0 until array.length()) {
                                    add(array.optString(index))
                                }
                            }
                        }
                    val shouldAppend = collectionAddress.isNotEmpty() || isFullLoading == true
                    ensureMainThread {
                        NftStore.checkCardNftOwnership(accountId)
                    }
                    val nftsJSONArray =
                        objectJSONObject.optJSONArray("nfts") ?: return
                    val nfts = ArrayList<ApiNft>()
                    for (index in 0..<nftsJSONArray.length()) {
                        val nft = ApiNft.fromJson(nftsJSONArray.getJSONObject(index))
                        if (nft == null) {
                            Logger.e(
                                Logger.LogTag.JS_WEBVIEW_BRIDGE,
                                "nfts: dropped unparsable nft"
                            )
                            throw Exception()
                        }
                        nfts.add(nft)
                    }
                    if (collectionAddress.isNotEmpty()) {
                        ensureMainThread {
                            WalletCore.notifyEvent(
                                WalletEvent.CollectionNftsReceived(
                                    accountId,
                                    collectionAddress,
                                    nfts
                                )
                            )
                        }
                        return
                    }
                    if (AccountStore.activeAccount?.accountId != accountId) {
                        return
                    }
                    ensureMainThread {
                        NftStore.setNfts(
                            chain,
                            nfts,
                            accountId = accountId,
                            notifyObservers = true,
                            isReorder = false,
                            shouldAppend = shouldAppend,
                            preserveExistingOnConflict = shouldAppend,
                            streamedAddresses = streamedAddresses
                        )
                    }
                }

                "nftReceived" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    val nft = objectJSONObject
                        .optJSONObject("nft")
                        ?.let(ApiNft::fromJson)
                        ?: return
                    ensureMainThread {
                        NftStore.checkCardNftOwnership(accountId)
                        NftStore.applyIncomingMtwCard(accountId, nft)
                        if (AccountStore.activeAccount?.accountId != accountId) {
                            return@ensureMainThread
                        }
                        NftStore.add(accountId, nft)
                    }
                }

                "nftSent" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    val nftAddress = objectJSONObject.optString("nftAddress")
                    ensureMainThread {
                        NftStore.checkCardNftOwnership(accountId)
                        NftStore.pruneOwnedMtwCardAddress(accountId, nftAddress)
                        if (AccountStore.activeAccount?.accountId != accountId) {
                            return@ensureMainThread
                        }
                        NftStore.removeByAddress(accountId, nftAddress)
                    }
                }

                "updateConfig" -> {
                    val configAdapter: JsonAdapter<Map<String, Any>> =
                        WalletCore.moshi.adapter(
                            Types.newParameterizedType(
                                Map::class.java,
                                String::class.java,
                                Any::class.java
                            )
                        )
                    val configMapString = configAdapter.fromJson(updateString)
                    ConfigStore.init(configMapString)
                    ensureMainThread {
                        WalletCore.notifyEvent(WalletEvent.ConfigReceived)
                    }
                }

                "updateAccountConfig" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    val accountConfig = objectJSONObject.optJSONObject("accountConfig") ?: return
                    ensureMainThread {
                        WGlobalStorage.setAccountConfig(accountId, accountConfig)
                        WalletCore.notifyEvent(WalletEvent.AccountConfigReceived)
                    }
                }

                "updateAccountDomainData" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    if (AccountStore.activeAccount?.accountId != accountId) {
                        return
                    }
                    val expirationByAddress =
                        objectJSONObject.optJSONObject("expirationByAddress")?.toHashMapLong()
                    val linkedAddresses =
                        objectJSONObject.optJSONObject("linkedAddressByAddress")?.toHashMapString()
                    ensureMainThread {
                        NftStore.setExpirationByAddress(
                            accountId,
                            expirationByAddress
                        )
                        NftStore.setLinkedAddressByAddress(
                            accountId,
                            linkedAddresses
                        )
                        WalletCore.notifyEvent(WalletEvent.NftDomainDataUpdated)
                    }
                }

                "openUrl" -> {
                    val rawUrl = objectJSONObject.optString("url").takeIfNotBlank() ?: return
                    val url = rawUrl.decodeUrlOrNull() ?: return
                    val isExternal = objectJSONObject.optBoolean("isExternal", false)
                    ensureMainThread {
                        WalletCore.notifyEvent(WalletEvent.OpenUrl(url, isExternal))
                    }
                }

                "showError" -> {
                    val error = objectJSONObject.optString("error").takeIfNotBlank()
                    ensureMainThread {
                        WalletContextManager.delegate?.get()?.showError(error)
                    }
                }

                else -> {}
            }
        }

        @JavascriptInterface
        fun onUpdate(updateString: String) {
            scope.launch {
                parseUpdate(updateString)

                // New Approach
                val adapter = WalletCore.moshi.adapter(ApiUpdate::class.java)
                try {
                    val update = adapter.fromJson(updateString) ?: return@launch
                    WalletCore.notifyApiUpdate(update)
                    // return@execute
                } catch (e: Exception) {
                    Logger.w(
                        Logger.LogTag.JS_WEBVIEW_BRIDGE,
                        "onUpdate: Moshi rejected type=${peekUpdateType(
                            updateString
                        )} error=${e.javaClass.simpleName}"
                    )
                }
            }
        }

        @JavascriptInterface
        fun nativeCall(requestNumber: Int, methodName: String, arg0: String, arg1: String?) {
            when (methodName) {
                "airStorageGetItem" -> {
                    val result = getStorageValue(arg0)
                    val resultInJs =
                        if (result.isEmpty()) "null" else JSONObject.quote(result)
                    val script =
                        "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true, result: $resultInJs})"
                    bridge.post {
                        bridge.evaluateJavascript(script) {}
                    }
                }

                "airStorageSetItem" -> {
                    setStorageValue(arg0, arg1 ?: "")
                    val script =
                        "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true})"
                    bridge.post {
                        bridge.evaluateJavascript(script) {}
                    }
                }

                "airStorageRemoveItem" -> {
                    removeStorageValue(arg0)
                    val script =
                        "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true})"
                    bridge.post {
                        bridge.evaluateJavascript(script) {}
                    }
                }

                "airStorageClear" -> {
                    WSdkStorage.clearStorage()
                    WSecureStorage.clearStorage()
                    val script =
                        "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true})"
                    bridge.post {
                        bridge.evaluateJavascript(script) {}
                    }
                }

                "airStorageKeys" -> {
                    val resultInJs = (WSecureStorage.getKeys() + WSdkStorage.getKeys())
                        .distinct()
                        .toTypedArray()
                        .toJSONString
                    val script =
                        "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true, result: $resultInJs})"
                    bridge.post {
                        bridge.evaluateJavascript(script) {}
                    }
                }

                "getLedgerDeviceModel" -> {
                    WalletCore.notifyEvent(
                        WalletEvent.LedgerDeviceModelRequest { responseJsonObject ->
                            val script =
                                "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true, result: $responseJsonObject})"
                            bridge.post {
                                bridge.evaluateJavascript(script) {}
                            }
                        }
                    )
                }

                "exchangeWithLedger" -> {
                    WalletCore.notifyEvent(
                        WalletEvent.LedgerWriteRequest(arg0) { response ->
                            val quotedResponse = JSONObject.quote(response)
                            val script =
                                "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true, result: $quotedResponse})"
                            bridge.post {
                                bridge.evaluateJavascript(script) {}
                            }
                        }
                    )
                }

                "exportSecret" -> {
                    try {
                        val token = arg1 ?: throw IllegalArgumentException("Missing token")
                        val secret = EnclaveManager.sharedInstance.exportSecret(arg0, token)
                        val quotedResult = JSONObject.quote(secret)
                        val script =
                            "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true, result: $quotedResult})"
                        bridge.post {
                            bridge.evaluateJavascript(script) {}
                        }
                    } catch (e: Exception) {
                        val errMsg = JSONObject.quote("exportSecret failed: ${e.message}")
                        val script =
                            "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: false, error: $errMsg})"
                        bridge.post {
                            bridge.evaluateJavascript(script) {}
                        }
                    }
                }

                else -> {
                    throw RuntimeException("nativeCall $methodName not defined.")
                }
            }
        }
    }

    class ApiError(
        val methodName: String,
        val raw: String?,
        val parsed: MBridgeError,
        val exception: Throwable? = null,
        val parsedResult: Any? = null
    ) : Exception("ApiError: $methodName", exception)

    suspend fun <T> callApiAsync(methodName: String, args: String, clazz: Type): T {
        val result = callApiAsyncRaw(methodName, args, clazz)
        return parseResult(methodName, args, result, clazz)
    }

    private suspend fun callApiAsyncRaw(methodName: String, args: String, clazz: Type): String =
        suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { }
            ensureMainThread {
                callApi(methodName, args) { res, err ->
                    if (continuation.isActive) {
                        if (err != null) {
                            continuation.resumeWith(
                                Result.failure(
                                    ApiError(
                                        methodName = methodName,
                                        raw = res,
                                        parsed = err,
                                        parsedResult = res?.let {
                                            try {
                                                parseResult(methodName, args, it, clazz)
                                            } catch (e: CancellationException) {
                                                continuation.cancel(e)
                                                return@callApi
                                            } catch (_: Exception) {
                                                null
                                            }
                                        }
                                    )
                                )
                            )
                        } else {
                            continuation.resumeWith(Result.success(res ?: ""))
                        }
                    }
                }
            }
        }

    fun <T> callApi(
        methodName: String,
        args: String,
        clazz: Type,
        callback: (String?, T?, ApiError?) -> Unit
    ) {
        callApi(methodName, args) { res, err ->
            if (err != null) {
                callback.invoke(
                    res,
                    null,
                    ApiError(
                        methodName = methodName,
                        raw = res,
                        parsed = err,
                        parsedResult = try {
                            parseResult<T>(methodName, args, res ?: "", clazz)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (_: Exception) {
                            null
                        }
                    )
                )
            } else {
                val parsed = try {
                    parseResult<T>(methodName, args, res ?: "", clazz)
                } catch (e: ApiError) {
                    callback.invoke(res, null, e)
                    return@callApi
                }
                callback.invoke(res, parsed, null)
            }
        }
    }

    private fun <T> parseResult(methodName: String, args: String, result: String, clazz: Type): T {
        if (result == "undefined") {
            return null as T
        }

        val adapter: JsonAdapter<T> = WalletCore.moshi.adapter(clazz)

        val parsed = try {
            adapter.fromJson(result) as T
        } catch (e: Exception) {
            if (e is CancellationException) {
                throw e
            }
            throw ApiError(
                methodName = methodName,
                raw = result,
                parsed = MBridgeError.Type.PARSE_ERROR,
                exception = e
            )
        }

        return parsed
    }
}
