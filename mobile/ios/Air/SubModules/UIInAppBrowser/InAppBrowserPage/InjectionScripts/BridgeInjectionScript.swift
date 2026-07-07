import Foundation

struct DappConnectMessageType {
    static let invokeFunc = "invokeFunc"
    static let functionResponse = "functionResponse"
    static let event = "event"
}

struct BridgeInjectionScript {
    static let source = """
        (function() {
            if (window._mtwAir_invokeFunc) return;
            window._mtwAir_promises = {};
            window._mtwAir_eventListeners = [];
            window._mtwAir_invokeFunc = function(name, args, resolve, reject) {
                const invocationId = btoa(Math.random()).substring(0, 12);
                const timeoutMs = undefined;
                const onResolve = typeof resolve === 'function' ? resolve : function() {};
                const onReject = typeof reject === 'function' ? reject : function() {};
                const timeoutId = timeoutMs ? setTimeout(() => onReject(new Error(`bridge timeout for function with name: ${name}`)), timeoutMs) : null;
                window._mtwAir_promises[invocationId] = { resolve: onResolve, reject: onReject, timeoutId: timeoutId };
                window.webkit.messageHandlers.inAppBrowserHandler.postMessage(JSON.stringify({
                    type: '\(DappConnectMessageType.invokeFunc)',
                    invocationId: invocationId,
                    name: name,
                    args: args
                }));
            };
            const mtwOriginalWindowOpen = window.open.bind(window);
            window.open = function(url, target, features) {
                const openedWindow = mtwOriginalWindowOpen(url, target, features);
                if (!openedWindow && url) {
                    window._mtwAir_invokeFunc('window:open', { url: url });
                }
                return openedWindow;
            };
            window.close = function() {
                window._mtwAir_invokeFunc('window:close');
            };
            window.addEventListener('message', function(e) {
                try {
                    const message = JSON.parse(e.data);
                    if (message.type === '\(DappConnectMessageType.functionResponse)') {
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
                    if (message.type === '\(DappConnectMessageType.event)') {
                        window._mtwAir_eventListeners.forEach(function(listener) {
                            try {
                                listener(message.event);
                            } catch (e) {}
                        });
                    }
                } catch (err) {}
            });
        })();
        """
}
