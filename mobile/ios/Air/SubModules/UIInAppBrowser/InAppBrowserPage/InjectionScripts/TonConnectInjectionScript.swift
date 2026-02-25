import Foundation
import WalletContext

private let tonConnectWalletJsBridgeKey = "mytonwallet"

struct TonConnectInjectionScript {
    private static let funcs: [(String, String)] = [
        ("connect", "tonConnect:connect"),
        ("restoreConnection", "tonConnect:restoreConnection"),
        ("disconnect", "tonConnect:disconnect"),
        ("send", "tonConnect:send"),
        ("window:open", "window:open"),
        ("window:close", "window:close"),
    ]
    private static let funcsBody: String = {
        funcs.reduce("") { acc, pair in
            let funcName = pair.0
            let invokeName = pair.1
            return acc + """
            '\(funcName)': (...args) => {
                return new Promise((resolve, reject) => window._mtwAir_invokeFunc('\(invokeName)', args, resolve, reject))
            },
            
            """
        }
    }()
    static let source = """
        (function() {
            if (window.\(tonConnectWalletJsBridgeKey)) return;
            function listen(cb) {
                window._mtwAir_eventListeners.push(cb);
                return function() {
                    const index = window._mtwAir_eventListeners.indexOf(cb);
                    if (index > -1) {
                        window._mtwAir_eventListeners.splice(index, 1);
                    }
                };
            }
            window.\(tonConnectWalletJsBridgeKey) = {
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
                              { name: 'SignData', types: ['text', 'binary', 'cell'] },
                            ],
                        },
                        protocolVersion: \(supportedTonConnectVersion),
                        isWalletBrowser: true
                    },
                    {
                        \(funcsBody)
                    },
                    { listen: listen }
                )
            };
        })();
        """
}
