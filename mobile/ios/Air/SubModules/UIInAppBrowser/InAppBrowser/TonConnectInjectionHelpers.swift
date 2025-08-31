//
//  InAppBrowserTonConnectInjectionHelpers.swift
//  UIInAppBrowser
//
//  Created by Sina on 8/29/24.
//

import Foundation
import UIKit
import WalletContext

class InAppBrowserTonConnectInjectionHelpers {
    static let TONCONNECT_WALLET_JSBRIDGE_KEY = "mytonwallet"
    
    enum WebViewBridgeMessageType: String {
        case invokeFunc = "invokeFunc"
        case functionResponse = "functionResponse"
        case event = "event"
    }
    
    struct WebViewBridgeMessage {
        let type: String
        let invocationId: String
        let name: String
        let args: [Any]
    }
    
    static func objectToInject() -> String {
        let funcs = ["connect", "restoreConnection", "disconnect", "send", "window:open", "window:close"].reduce("") { acc, funcName in
            return acc + """
            '\(funcName)': (...args) => {
                return new Promise((resolve, reject) => window._mtwAir_invokeFunc('\(funcName)', args, resolve, reject))
            },
            
            """
        }

        return """
        (function() {
            if (window.\(TONCONNECT_WALLET_JSBRIDGE_KEY)) return;
            window._mtwAir_promises = {};
            window._mtwAir_eventListeners = [];
            window._mtwAir_invokeFunc = function(name, args, resolve, reject) {
                const invocationId = btoa(Math.random()).substring(0, 12);
                const timeoutMs = undefined;
                const timeoutId = timeoutMs ? setTimeout(() => reject(new Error(`bridge timeout for function with name: ${name}`)), timeoutMs) : null;
                window._mtwAir_promises[invocationId] = { resolve: resolve, reject: reject, timeoutId: timeoutId };
                window.webkit.messageHandlers.inAppBrowserHandler.postMessage(JSON.stringify({
                    type: '\(WebViewBridgeMessageType.invokeFunc)',
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
                    if (message.type === '\(WebViewBridgeMessageType.functionResponse)') {
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
                    if (message.type === '\(WebViewBridgeMessageType.event)') {
                        window._mtwAir_eventListeners.forEach(function(listener) {
                            listener(message.event);
                        });
                    }
                } catch (err) {}
            });
            function listen(cb) {
                window._mtwAir_eventListeners.push(cb);
                return function() {
                    const index = window._mtwAir_eventListeners.indexOf(cb);
                    if (index > -1) {
                        window._mtwAir_eventListeners.splice(index, 1);
                    }
                };
            }
            window.\(TONCONNECT_WALLET_JSBRIDGE_KEY) = {
                tonconnect: Object.assign(
                    {
                        deviceInfo: {
                            platform: '\(devicePlatform)',
                            appName: '\(appName)',
                            appVersion: '\(appVersion)',
                            maxProtocolVersion: \(supportedTonConnectVersion),
                            features: [
                              'SendTransaction',
                              { name: 'SendTransaction', maxMessages: 4 },
                            ],
                        },
                        protocolVersion: \(supportedTonConnectVersion),
                        isWalletBrowser: true
                    },
                    {\(funcs)},
                    { listen: listen }
                )
            };
        })();
        """
    }
}
