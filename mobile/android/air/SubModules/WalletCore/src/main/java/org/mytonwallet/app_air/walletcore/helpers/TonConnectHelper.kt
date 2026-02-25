package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.DeviceInfo
import java.security.SecureRandom

object TonConnectHelper {
    const val TON_CONNECT_WALLET_JS_BRIDGE_KEY = "mytonwallet"
    const val TON_CONNECT_WALLET_JS_BRIDGE_INTERFACE = "_mytonwallet"

    val deviceInfo: DeviceInfo
        get() = DeviceInfo(
            platform = "android",
            appName = "MyTonWallet",
            appVersion = ApplicationContextHolder.getAppVersion ?: "",
            maxProtocolVersion = 2,
            features = listOf(
                "SendTransaction",
                DeviceInfo.Feature.SendTransaction(maxMessages = 4)
            )
        )
    val deviceInfoJson: String
        get() =
            WalletCore.moshi.adapter(DeviceInfo::class.java).toJson(deviceInfo)


    enum class WebViewBridgeMessageType(val key: String) {
        INVOKE_FUNC("invokeFunc"),
        FUNCTION_RESPONSE("functionResponse"),
        EVENT("event")
    }

    fun generateId(): String {
        val t = System.currentTimeMillis()
        val secureRandom = SecureRandom()
        return t.toString() + "_" + secureRandom.nextLong().toString()
    }

    fun injectBridge(): String {
        return """
        (function() {
            if (window._mtwAir_invokeFunc) return;
            window._mtwAir_promises = {};
            window._mtwAir_eventListeners = [];
            window._mtwAir_invokeFunc = function(name, args, resolve, reject) {
                const invocationId = btoa(Math.random()).substring(0, 12);
                const timeoutMs = undefined;
                const timeoutId = timeoutMs ? setTimeout(() => reject(new Error('bridge timeout for function with name: ' + name)), timeoutMs) : null;
                window._mtwAir_promises[invocationId] = { resolve: resolve, reject: reject, timeoutId: timeoutId };
                $TON_CONNECT_WALLET_JS_BRIDGE_INTERFACE.invokeFunc(JSON.stringify({
                    type: '${WebViewBridgeMessageType.INVOKE_FUNC.key}',
                    invocationId: invocationId,
                    name: name,
                    args: args
                }));
            };
            window.open = function(url) {
                window._mtwAir_invokeFunc('window:open', { url: url });
            };
            window.close = function() {
                window._mtwAir_invokeFunc('window:close');
            };
            window.addEventListener('click', function(e) {
                const href = e.target.closest('a')?.href;
                const target = e.target.closest('a')?.target;
                if (href && (target === '_blank' || !href.startsWith('http'))) {
                    e.preventDefault();
                    window._mtwAir_invokeFunc('window:open', { url: href });
                }
            }, false);
            window.addEventListener('message', function(e) {
                try {
                    const message = JSON.parse(e.data);
                    console.log(message)
                    if (message.type === '${WebViewBridgeMessageType.FUNCTION_RESPONSE.key}') {
                        console.log(window._mtwAir_promises)
                        const promise = window._mtwAir_promises[message.invocationId];
                        if (!promise) {
                            return;
                        }
                        if (promise.timeoutId) {
                            clearTimeout(promise.timeoutId);
                        }
                        if (message.status === 'fulfilled') {
                            promise.resolve(message.data);
                        } else {
                            promise.reject(new Error(message.data));
                        }
                        delete window._mtwAir_promises[message.invocationId];
                    }
                    if (message.type === '${WebViewBridgeMessageType.EVENT.key}') {
                        window._mtwAir_eventListeners.forEach(function(listener) {
                            listener(message.event);
                        });
                    }
                } catch (err) {}
            });
        })();
        """
    }

    fun inject(): String {
        val funcs = listOf(
            Pair("connect", "tonConnect:connect"),
            Pair("restoreConnection", "tonConnect:restoreConnection"),
            Pair("disconnect", "tonConnect:disconnect"),
            Pair("send", "tonConnect:send"),
        ).joinToString(separator = "") { (funcName, invokeName) ->
            """
            '$funcName': (...args) => {
                return new Promise((resolve, reject) => window._mtwAir_invokeFunc('$invokeName', args, resolve, reject))
            },
            """
        }

        return """
        (function() {
            if (window.$TON_CONNECT_WALLET_JS_BRIDGE_KEY) return;
            function listen(cb) {
                window._mtwAir_eventListeners.push(cb);
                return function() {
                    const index = window._mtwAir_eventListeners.indexOf(cb);
                    if (index > -1) {
                        window._mtwAir_eventListeners.splice(index, 1);
                    }
                };
            }

            window.$TON_CONNECT_WALLET_JS_BRIDGE_KEY = {
                tonconnect: Object.assign(
                    {
                        deviceInfo: ${deviceInfoJson},
                        protocolVersion: ${deviceInfo.maxProtocolVersion},
                        isWalletBrowser: true
                    },
                    { $funcs },
                    { listen: listen }
                )
            };
        })();
        """
    }
}
