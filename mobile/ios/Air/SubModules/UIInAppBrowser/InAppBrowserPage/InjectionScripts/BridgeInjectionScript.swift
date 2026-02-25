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
                const timeoutId = timeoutMs ? setTimeout(() => reject(new Error(`bridge timeout for function with name: ${name}`)), timeoutMs) : null;
                window._mtwAir_promises[invocationId] = { resolve: resolve, reject: reject, timeoutId: timeoutId };
                window.webkit.messageHandlers.inAppBrowserHandler.postMessage(JSON.stringify({
                    type: '\(DappConnectMessageType.invokeFunc)',
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
                            listener(message.event);
                        });
                    }
                } catch (err) {}
            });
        })();
        """
}
