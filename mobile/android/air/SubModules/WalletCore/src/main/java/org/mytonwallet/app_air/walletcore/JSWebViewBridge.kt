package org.mytonwallet.app_air.walletcore

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewCompat
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Types
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import okio.IOException
import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.DEBUG_MODE
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.logger.Logger
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcontext.utils.toHashMapLong
import org.mytonwallet.app_air.walletcontext.utils.toHashMapString
import org.mytonwallet.app_air.walletcontext.utils.toJSONString
import org.mytonwallet.app_air.walletcore.api.setBaseCurrency
import org.mytonwallet.app_air.walletcore.models.MBaseCurrency
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.MUpdateStaking
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ActivityStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.reflect.Type
import java.math.BigInteger
import java.util.concurrent.Executors

/*const val CONSOLE_OVERRIDE_SCRIPT = """
    (function() {
        const originalConsole = {
            log: console.log,
            error: console.error,
            warn: console.warn,
            info: console.info,
            debug: console.debug
        };

        console.log = function(...args) {
            androidApp.consoleLog('LOG', JSON.stringify(args));
            originalConsole.log.apply(console, args);
        };

        console.error = function(...args) {
            androidApp.consoleLog('ERROR', JSON.stringify(args));
            originalConsole.error.apply(console, args);
        };

        console.warn = function(...args) {
            androidApp.consoleLog('WARN', JSON.stringify(args));
            originalConsole.warn.apply(console, args);
        };

        console.info = function(...args) {
            androidApp.consoleLog('INFO', JSON.stringify(args));
            originalConsole.info.apply(console, args);
        };

        console.debug = function(...args) {
            androidApp.consoleLog('DEBUG', JSON.stringify(args));
            originalConsole.debug.apply(console, args);
        };
    })();
"""*/

const val INIT_SCRIPT =
    "window.airBridge.initApi((data) => {androidApp.onUpdate(JSON.stringify(data))}, {isAndroidApp: true})"

@SuppressLint("SetJavaScriptEnabled")
class JSWebViewBridge(context: Context) : WebView(context) {

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

        Logger.d(Logger.LogTag.JS_WEBVIEW_BRIDGE, "WebView version: $webViewVersion")

        loadUrl("file:///android_asset/js/index.html")

        addJavascriptInterface(JsWebInterface(this), "androidApp")
        webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                post {
                    injectIfNeeded(onBridgeReady)
                }
            }
        }
    }

    private var injecting: Boolean = false
    var injected: Boolean = false
        private set

    private fun injectIfNeeded(onBridgeReady: () -> Unit) {
        if (injecting || injected)
            return
        injecting = true

        //evaluateJavascript(CONSOLE_OVERRIDE_SCRIPT) {
        // Inject the init script
        evaluateJavascript(INIT_SCRIPT) { res ->
            if (res.equals("null")) {
                injected = true
                onBridgeReady()
            } else {
                Handler(context.mainLooper).postDelayed({
                    injectIfNeeded(onBridgeReady)
                }, 500)
            }
        }
        //}
    }

    private var callIdentifier: Int = 0
    private var callbacks: HashMap<Int, (result: String?, error: MBridgeError?) -> Unit> =
        hashMapOf()

    internal fun callApi(
        methodName: String,
        args: String,
        callback: (result: String?, error: MBridgeError?) -> Unit
    ) {
        callIdentifier += 1
        val thisCallIdentifier = callIdentifier
        callbacks[thisCallIdentifier] = callback
        val script = "if (!window.airBridge?.callApi) {\n" +
            "androidApp.callback(${thisCallIdentifier}, false, 'airBridge not working!');" +
            "} else {" +
            "   let call = window.airBridge.callApi('$methodName',...JSON.parse(${
                JSONObject.quote(args)
            }, window.airBridge.bigintReviver));" +
            "   if (call?.then) {" +
            "       call.then((res) => {" +
            "           if (res?.error || res?.err) {" +
            "               androidApp.callback(${thisCallIdentifier}, false, JSON.stringify(res))" +
            "           } else {" +
            "               androidApp.callback(${thisCallIdentifier}, true, JSON.stringify(res))" +
            "       }})" +
            "       .catch((e) => {console.log(e);androidApp.callback(${thisCallIdentifier}, false, JSON.stringify(e))})" +
            "   } else {" +
            "       androidApp.callback(${thisCallIdentifier}, true, JSON.stringify(call))" +
            "   }" +
            "}"
        evaluateJavascript(script) { }
    }

    class JsWebInterface(val bridge: JSWebViewBridge) {
        /*@JavascriptInterface
        fun consoleLog(level: String, args: String) {
            try {
                val tag = Logger.LogTag.JS_LOG
                val message = "[$level] $args"

                when (level) {
                    "ERROR" -> Logger.e(tag, message)
                    "WARN" -> Logger.w(tag, message)
                    "INFO" -> Logger.i(tag, message)
                    "DEBUG" -> Logger.d(tag, message)
                    else -> Logger.i(tag, message)
                }
            } catch (e: Exception) {
                Logger.e(Logger.LogTag.JS_LOG, "Error logging console message: ${e.message}")
            }
        }*/

        @JavascriptInterface
        fun callback(identifier: Int, success: Boolean, result: String) {
            bridge.post {
                val callback = bridge.callbacks[identifier]
                if (success) {
                    bridge.callbacks[identifier]?.invoke(result, null)
                } else {
                    try {
                        val obj = JSONObject(result)
                        val errorObj = obj.optJSONObject("error")
                            ?: obj.optJSONObject("err")
                        val errorName = errorObj?.optString("name")
                            ?: obj.optString("error").takeIf { it.isNotBlank() }
                            ?: obj.optString("name")
                        if (errorName != null) {
                            val bridgeError =
                                MBridgeError.entries.firstOrNull { it.errorName == errorName }
                            if (bridgeError != null) {
                                callback?.invoke(result, bridgeError)
                                return@post
                            }
                        }
                        val displayError = errorObj?.optString("displayError")
                        if (displayError != null) {
                            val err = MBridgeError.UNKNOWN
                            err.customMessage = displayError
                            callback?.invoke(result, err)
                            return@post
                        }
                    } catch (_: Error) {
                    }
                    callback?.invoke(result, MBridgeError.UNKNOWN)
                }
                bridge.callbacks.remove(identifier)
            }
        }

        @Deprecated("Use moshi ApiUpdate")
        private fun parseUpdate(updateString: String) {
            val executor = Executors.newSingleThreadExecutor()
            val objectJSONObject = JSONObject(updateString)
            val updateType = objectJSONObject.optString("type")
            when (updateType) {
                "updateBalances" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    Handler(Looper.getMainLooper()).post {
                        val balances = HashMap<String, BigInteger>()
                        executor.execute {
                            val balancesToUpdate =
                                objectJSONObject.optJSONObject("balances")
                                    ?: return@execute
                            for (token in balancesToUpdate.keys()) {
                                val valueString: String =
                                    balancesToUpdate.optString(token).substringAfter("bigint:")
                                val value =
                                    if (valueString.isNotEmpty()) valueString.toBigInteger() else BigInteger.valueOf(
                                        0
                                    )
                                balances[token] = value
                            }
                            Handler(Looper.getMainLooper()).post {
                                BalanceStore.setBalances(accountId, balances, false) {
                                    if (AccountStore.activeAccount?.accountId != accountId) {
                                        WalletCore.notifyEvent(WalletEvent.NotActiveAccountBalanceChanged)
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

                "updateTokens" -> {
                    val baseCurrency = objectJSONObject.optString("baseCurrency")
                    if (WGlobalStorage.getBaseCurrency() != baseCurrency) {
                        Handler(Looper.getMainLooper()).post {
                            WalletCore.setBaseCurrency(WGlobalStorage.getBaseCurrency()) { _, _ -> }
                        }
                        return
                    }
                    WalletCore.baseCurrency = MBaseCurrency.valueOf(baseCurrency)
                    val tokensJSONObject =
                        objectJSONObject.optJSONObject("tokens") ?: return
                    if (tokensJSONObject.length() < 6) {
                        return
                    }
                    val tokensObject = HashMap<String, MToken>()
                    for (tokenSlug in tokensJSONObject.keys()) {
                        tokensObject[tokenSlug] =
                            MToken(tokensJSONObject.getJSONObject(tokenSlug))
                    }
                    for (it in tokensObject.keys) {
                        TokenStore.setToken(it, tokensObject[it]!!)
                    }
                    TokenStore.updateTokensCache()
                    Handler(Looper.getMainLooper()).post {
                        if (tokensObject.size < 7)
                            return@post
                        WalletCore.notifyEvent(WalletEvent.TokensChanged)
                    }
                }

                "updateSwapTokens" -> {
                    val tokensJSONObject =
                        objectJSONObject.optJSONObject("tokens") ?: return
                    try {
                        val tokens = ArrayList<MToken>()
                        val tokenKeys = tokensJSONObject.keys()
                        for (key in tokenKeys) {
                            val tokenObj = tokensJSONObject.getJSONObject(key)
                            val token = MToken(tokenObj)
                            tokens.add(token)
                        }
                        TokenStore.swapAssets2 = tokens.map { MApiSwapAsset.from(it) }
                        TokenStore.swapAssetsMap =
                            TokenStore.swapAssets2?.associateBy { it.slug }
                        TokenStore._swapAssetsFlow.value = TokenStore.swapAssets2
                        TokenStore.swapAssets = tokens
                        TokenStore.updateSwapCache()
                        Handler(Looper.getMainLooper()).post {
                            TokenStore.isLoadingSwapAssets = false
                            WalletCore.notifyEvent(WalletEvent.TokensChanged)
                        }
                    } catch (e: Error) {
                        Handler(Looper.getMainLooper()).post {
                        }
                    }
                }

                "newLocalActivities" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    if (AccountStore.activeAccount?.accountId != accountId) {
                        return
                    }
                    val json = objectJSONObject.optJSONObject("activity") ?: return
                    val transaction = MApiTransaction.fromJson(json)!!
                    ActivityStore.receivedLocalTransaction(accountId, transaction)
                }

                "newActivities" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    if (AccountStore.activeAccount?.accountId != accountId) {
                        return
                    }
                    val transactionJSONArray =
                        objectJSONObject.optJSONArray("activities") ?: JSONArray()
                    val pendingTransactionsJSONArray =
                        objectJSONObject.optJSONArray("pendingActivities") ?: JSONArray()
                    try {
                        val transactions = ArrayList<MApiTransaction>()
                        for (index in 0..<transactionJSONArray.length()) {
                            val transactionObj = transactionJSONArray.getJSONObject(index)
                            val transaction = MApiTransaction.fromJson(transactionObj)!!
                            transactions.add(transaction)
                        }
                        val pendingTransactions = ArrayList<MApiTransaction>()
                        for (index in 0..<pendingTransactionsJSONArray.length()) {
                            val transactionObj = pendingTransactionsJSONArray.getJSONObject(index)
                            val transaction = MApiTransaction.fromJson(transactionObj)!!
                            pendingTransactions.add(transaction)
                        }
                        ActivityStore.newActivities(
                            context = bridge.context,
                            accountId = accountId,
                            newActivities = transactions,
                            pendingActivities = pendingTransactions
                        )
                    } catch (e: Error) {
                        e.printStackTrace()
                    }
                }

                "updateStaking" -> {
                    val accountId = objectJSONObject.optString("accountId")

                    val stakingAdapter: JsonAdapter<MUpdateStaking> =
                        WalletCore.moshi.adapter(MUpdateStaking::class.java)
                    val stakingData = stakingAdapter.fromJson(updateString)

                    Handler(Looper.getMainLooper()).post {
                        StakingStore.setStakingState(accountId, stakingData)
                        WalletCore.notifyEvent(WalletEvent.StakingDataUpdated)
                    }
                }

                "updateNfts" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    Handler(Looper.getMainLooper()).post {
                        NftStore.checkCardNftOwnership(accountId)
                    }
                    if (AccountStore.activeAccount?.accountId != accountId) {
                        return
                    }
                    val nftsJSONArray =
                        objectJSONObject.optJSONArray("nfts") ?: return
                    val nfts = ArrayList<ApiNft>()
                    for (index in 0..<nftsJSONArray.length()) {
                        nfts.add(ApiNft.fromJson(nftsJSONArray.getJSONObject(index))!!)
                    }
                    Handler(Looper.getMainLooper()).post {
                        NftStore.setNfts(
                            nfts,
                            accountId = accountId,
                            notifyObservers = true,
                            isReorder = false
                        )
                    }
                }

                "nftReceived" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    Handler(Looper.getMainLooper()).post {
                        NftStore.checkCardNftOwnership(accountId)
                        if (AccountStore.activeAccount?.accountId != accountId) {
                            return@post
                        }
                        NftStore.add(ApiNft.fromJson(objectJSONObject.optJSONObject("nft")!!)!!)
                    }
                }

                "nftSent" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    Handler(Looper.getMainLooper()).post {
                        NftStore.checkCardNftOwnership(accountId)
                        if (AccountStore.activeAccount?.accountId != accountId) {
                            return@post
                        }
                        NftStore.removeByAddress(objectJSONObject.optString("nftAddress"))
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
                    Handler(Looper.getMainLooper()).post {
                        WalletCore.notifyEvent(WalletEvent.ConfigReceived)
                    }
                }

                "updateAccountConfig" -> {
                    val accountId = objectJSONObject.optString("accountId")
                    val accountConfig = objectJSONObject.optJSONObject("accountConfig") ?: return
                    Handler(Looper.getMainLooper()).post {
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
                    Handler(Looper.getMainLooper()).post {
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

                else -> {}
            }
        }

        @JavascriptInterface
        fun onUpdate(updateString: String) {
            val executor = Executors.newSingleThreadExecutor()
            executor.execute {

                parseUpdate(updateString)

                // New Approach
                val adapter = WalletCore.moshi.adapter(ApiUpdate::class.java)
                try {
                    val update = adapter.fromJson(updateString) ?: throw IOException()
                    WalletCore.notifyApiUpdate(update)
                    // return@execute
                } catch (_: Throwable) {
                }
            }
        }

        @JavascriptInterface
        fun nativeCall(
            requestNumber: Int,
            methodName: String,
            arg0: String,
            arg1: String?
        ) {
            when (methodName) {
                "capacitorStorageGetItem" -> {
                    val result = WSecureStorage.getSecValue(arg0)
                    val resultInJs =
                        if (result.isEmpty()) "null" else JSONObject.quote(result)
                    val script =
                        "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true, result: ${resultInJs}})"
                    bridge.post {
                        bridge.evaluateJavascript(script) {}
                    }
                }

                "capacitorStorageSetItem" -> {
                    WSecureStorage.setSecValue(arg0, arg1 ?: "")
                    val script =
                        "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true})"
                    bridge.post {
                        bridge.evaluateJavascript(script) {}
                    }
                }

                "capacitorStorageRemoveItem" -> {
                    WSecureStorage.setSecValue(arg0, "")
                    val script =
                        "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true})"
                    bridge.post {
                        bridge.evaluateJavascript(script) {}
                    }
                }

                "capacitorStorageKeys" -> {
                    val resultInJs = WSecureStorage.getKeys().toJSONString
                    val script =
                        "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true, result: ${resultInJs}})"
                    bridge.post {
                        bridge.evaluateJavascript(script) {}
                    }
                }

                "exchangeWithLedger" -> {
                    WalletCore.notifyEvent(WalletEvent.LedgerWriteRequest(arg0) { response ->
                        val quotedResponse = JSONObject.quote(response)
                        val script =
                            "window.airBridge.nativeCallCallbacks[$requestNumber]?.({ok: true, result: $quotedResponse})"
                        bridge.post {
                            bridge.evaluateJavascript(script) {}
                        }
                    })
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
        val parsedResult: Any? = null,
    ) : Error("ApiError: $methodName-$raw")

    suspend fun <T> callApiAsync(methodName: String, args: String, clazz: Type): T {
        val result = callApiAsyncRaw<T>(methodName, args, clazz)
        return parseResult(methodName, args, result, clazz)
    }

    private suspend fun <T> callApiAsyncRaw(methodName: String, args: String, clazz: Type): String =
        suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { }
            Handler(Looper.getMainLooper()).post {
                callApi(methodName, args) { res, err ->
                    if (continuation.isActive) {
                        if (err != null) {
                            continuation.resumeWith(
                                Result.failure(
                                    ApiError(
                                        methodName = methodName,
                                        raw = res,
                                        parsed = err,
                                        parsedResult = try {
                                            parseResult(methodName, args, res!!, clazz)
                                        } catch (eee: Throwable) {
                                            null
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
                        } catch (_: Throwable) {
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
        } catch (e: Throwable) {
            if (e is CancellationException) {
                throw e
            }
            throw ApiError(
                methodName = methodName,
                raw = result,
                parsed = MBridgeError.PARSE_ERROR,
                exception = e
            )
        }

        return parsed
    }
}
