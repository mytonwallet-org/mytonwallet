//
//  JSWebViewBridge.swift
//  WalletCore
//
//  Created by Sina on 3/19/24.
//

import Foundation
import WebKit
import WalletContext

let NATIVE_CALL_OK = """
    if (result === null) {
        result = undefined
    }
    window.airBridge.nativeCallCallbacks[requestNumber]?.({
        ok: true, 
        result: result
    })
"""
let NATIVE_CALL_OK_VOID = """
    window.airBridge.nativeCallCallbacks[requestNumber]?.({
        ok: true 
    })
"""

#if DEBUG
let logStringIfRequired = "console.log(`${methodName}`);"
//let logStringIfRequired = "console.log(`${methodName} ${argsString}`);"
#else
let logStringIfRequired = "console.log(`${methodName}`);"
//let logStringIfRequired = ""
#endif

let CALL_API = """
    try {
        if (!window.airBridge) {
            throw new Error('err! callApi not found!');
        }
        \(logStringIfRequired)
        const args = JSON.parse(argsString, window.airBridge.bigintReviver);
        args.forEach((v, i, a) => { if (v === null) a[i] = undefined });
        const result = await window.airBridge.callApi(methodName, ...args);
        return JSON.stringify(result);
    } catch (e) {
        if (e instanceof Error) {
            // For actual Error objects, include stack trace if available
            throw JSON.stringify({
                message: e.message,
                name: e.name,
                stack: e.stack,
                additionalData: Object.getOwnPropertyNames(e).reduce((acc, key) => {
                    acc[key] = e[key];
                    return acc;
                }, {})
            });
        } else {
            throw JSON.stringify(e);
        }
    }
"""

let INIT_API = """
    window.airBridge.initApi(
        (data) => {
            window.webkit.messageHandlers.onUpdate.postMessage({ update: JSON.stringify(data) })
        }, 
        {
            isElectron: false,
            isNativeBottomSheet: false,
            isIosApp: true,
            isAndroidApp: false
        }
    )
"""

let LOGGING_FETCH = """
    const originalFetch = window.fetch;
    window.fetch = async function(...args) {
        let [input, init] = args;
        let method, url, body;
        if (input instanceof Request) {
            method = input.method;
            url = input.url;
            body = init?.body || '[Request body]';
        } else {
            url = input;
            method = init?.method || 'GET';
            body = init?.body || '';
        }
        console.log(method, url, body);
        const startTime = performance.now();
        const response = await originalFetch.apply(this, args);
        const endTime = performance.now();
        const durationSeconds = ((endTime - startTime) / 1000).toFixed(3);
        console.log(`time=${durationSeconds} status=${response.status} @ ${method} ${url}`);
        return response;
    };
"""

private let log = Log("JSWebViewBridge")
private let console = Log("console")
private let logUpdate = Log("update")


// The bridge to use mytonwallet js logic in Swift applications.
class JSWebViewBridge: UIViewController {
    
    private var webView: WKWebView?
    private let start = Date()

    let webViewQueue = DispatchQueue(label: "org.mytonwallet.app.webViewBridge_background", attributes: .concurrent)
    
    private let updateQueue = DispatchQueue(label: "onUpdate", qos: .background, attributes: [.concurrent])

    override func viewDidLoad() {
        super.viewDidLoad()
        
        recreateWebView()
        view.isHidden = true

        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.webView?.evaluateJavaScript(";", completionHandler: nil)
        }
    }

    private var onBridgeReady: (() -> Void)? = nil
    func recreateWebView(onCompletion: (() -> Void)? = nil) {
        onBridgeReady = onCompletion
        webView?.removeFromSuperview()
        webView = nil

        let webViewConfiguration = WKWebViewConfiguration()
        
        // make logging possible to get results from js promise
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "onUpdate")
        // Save storage db data in keychain (swift side)
        userContentController.add(self, name: "nativeCall")
        
        let logSource = "function captureLog(...msg) { window.webkit.messageHandlers.log.postMessage(msg); } window.console.log = captureLog;"
        let logScript = WKUserScript(source: logSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        userContentController.addUserScript(logScript)
        userContentController.add(self, name: "log")
        
//        let logFetchScript = WKUserScript(source: LOGGING_FETCH, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
//        userContentController.addUserScript(logFetchScript)

        webViewConfiguration.userContentController = userContentController
        // create web view
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                            configuration: webViewConfiguration)
        webView?.navigationDelegate = self
        webView?.uiDelegate = self
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView?.isInspectable = true
        }
        #endif
        webView?.isHidden = true

        view.addSubview(webView!)
        if isViewAppeared {
            loadHtml()
        }
    }
    
    var isViewAppeared = false
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !isViewAppeared {
            loadHtml()
            isViewAppeared = true
        }
    }
    
    private func loadHtml() {
        let url = AirBundle.url(forResource: "index", withExtension: "html")!
        webView?.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    
    private func _callApiImpl(methodName: String, args: [AnyEncodable?]) async throws -> Any? {
        let jsonData = try! JSONEncoder().encode(args)
        let argsString = String(data: jsonData, encoding: .utf8)!
        
        if self.webView == nil { // app switched to legacy mode
            throw BridgeCallError.customMessage("Switched to legacy app", nil)
        }
        
        let webView = self.webView!
        do {
            let rawResult = try await webView.callAsyncJavaScript(CALL_API, arguments: ["methodName": methodName, "argsString": argsString], contentWorld: .page)
            if let rawResult {
                let string = try (rawResult as? String).orThrow()
                let obj = try JSONSerialization.jsonObject(withString: string)
                return obj
            } else {
                return nil
            }
        } catch {
            try _parseError(error)
        }
    }
    
    private func _parseError(_ error: any Error) throws -> Never {
        log.fault("callAsyncJavaScript callApi error \(error, .public)")
        if let error = error as? WKError {
            switch error.code {
            case .javaScriptExceptionOccurred:
                if let m = error.errorUserInfo["WKJavaScriptExceptionMessage"] as? String, let errorMessage = try? JSONSerialization.jsonObject(withString: m) {
                    if let message = errorMessage as? String {
                        throw BridgeCallError(message: message, payload: error)
                    } else if let dict = errorMessage as? [String: Any], let message = dict["message"] as? String {
                        throw BridgeCallError(message: message, payload: errorMessage)
                    } else {
                        throw BridgeCallError(message: error.localizedDescription, payload: errorMessage)
                    }
                }
            case .javaScriptResultTypeIsUnsupported:
                log.fault("javaScriptResultTypeIsUnsupported")
//                assertionFailure()
            default:
                break
            }
        }
        throw BridgeCallError(message: error.localizedDescription, payload: error)
    }
    
    func callApi(methodName: String, args: [AnyEncodable?], callback: @escaping (Result<Any?, BridgeCallError>) -> Void) {
        Task {
            do {
                let result = try await _callApiImpl(methodName: methodName, args: args)
                callback(.success(result))
            } catch let error as BridgeCallError {
                callback(.failure(error))
            } catch {
                callback(.failure(.unknown(baseError: error)))
            }
        }
    }
    
    func callApiRaw<each E: Encodable>(_ methodName: String, _ args: repeat each E) async throws -> Any? {
        try await _callApiImpl(methodName: methodName, args: asAnyEncodables(repeat each args))
    }
    
    func callApi<each E: Encodable, T: Decodable>(_ methodName: String, _ args: repeat each E, decoding: T.Type) async throws -> T {
        let data = try await _callApiImpl(methodName: methodName, args: asAnyEncodables(repeat each args))
        do {
            return try JSONSerialization.decode(T.self, from: data.orThrow())
        } catch {
            try BridgeCallError.tryToParseDataAsErrorAndThrow(data: data)
            throw error
        }
    }
    
    func callApiOptional<each E: Encodable, T: Decodable>(_ methodName: String, _ args: repeat each E, decodingOptional: T.Type) async throws -> T? {
        let data = try await _callApiImpl(methodName: methodName, args: asAnyEncodables(repeat each args))
        if let data {
            do {
                return try JSONSerialization.decode(T.self, from: data)
            } catch {
                try BridgeCallError.tryToParseDataAsErrorAndThrow(data: data)
                throw error
            }
        } else {
            return nil
        }
    }
    
    func callApiVoid<each E: Encodable>(_ methodName: String, _ args: repeat each E, tryToParseError: Bool = true, assertIsNil: Bool = true) async throws {
        let data = try await _callApiImpl(methodName: methodName, args: asAnyEncodables(repeat each args))
        if tryToParseError, let data {
            try BridgeCallError.tryToParseDataAsErrorAndThrow(data: data)
        }
        if assertIsNil {
            assert(data == nil, "no return value expected")
        }
    }
    
    private func injectIfNeeded() {
        // inject the js codes for mytonwallet logic here
        webView?.evaluateJavaScript(INIT_API) { [weak self] (result, error) in
            if let error = error {
                log.fault("Error injecting JavaScript: \(error.localizedDescription)")
                // retry after a second!
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                    self?.injectIfNeeded()
                })
            } else {
                //log.debug("JavaScript injected successfully")
                WalletContextManager.delegate?.bridgeIsReady()
                self?.onBridgeReady?()
                self?.onBridgeReady = nil
            }
        }
    }
    
    func stop() {
        webView = nil
    }
}

extension JSWebViewBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        assert(Thread.isMainThread)
        let body = message.body
        let messageName = message.name
        updateQueue.async {
            assert(!Thread.isMainThread)
            let data = body as? [String: Any]
            switch messageName {
            case "log":
                var body = body
                if let arr = body as? [Any] {
                    body = arr.map { String(describing: $0) }.joined(separator: " ")
                }
                let string = "\(body)"
                console.info("\(string, .public)", fileOnly: string.contains("POST") || string.contains("GET"))
                
            case "nativeCall":
                guard let requestNumber = data?["requestNumber"] as? Int,
                      let methodName = data?["methodName"] as? String else {
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    switch methodName {
                    case "capacitorStorageGetItem":
                        guard let key = data?["arg0"] as? String
                        else {
                            return
                        }
                        let result = KeychainHelper.getStorage(key: key)
                        Task {
                            do {
                                _ = try await self.webView?.nativeCallOk(requestNumber: requestNumber, result: result)
                            } catch {
                                log.fault("Error injecting getItem response to JavaScript: \(error)")
                            }
                        }
                        
                    case "capacitorStorageSetItem":
                        guard let key = data?["arg0"] as? String,
                              let value = data?["arg1"] as? String
                        else {
                            return
                        }
                        KeychainHelper.saveStorage(key: key, value: value)
                        Task {
                            do {
                                _ = try await self.webView?.nativeCallOkVoid(requestNumber: requestNumber)
                            } catch {
                                log.fault("Error injecting setItem response to JavaScript: \(error)")
                            }
                        }
                        
                    case "capacitorStorageRemoveItem":
                        guard let key = data?["arg0"] as? String
                        else {
                            return
                        }
                        KeychainHelper.saveStorage(key: key, value: nil)
                        Task {
                            do {
                                _ = try await self.webView?.nativeCallOkVoid(requestNumber: requestNumber)
                            } catch {
                                log.fault("Error injecting removeItem response to JavaScript: \(error)")
                            }
                        }
                        break
                        
                    case "capacitorStorageKeys":
                        Task {
                            do {
                                _ = try await self.webView?.nativeCallOk(requestNumber: requestNumber, result: KeychainHelper.keys())
                            } catch {
                                log.fault("Error injecting keys response to JavaScript: \(error)")
                            }
                        }
                        break
                        
                    case "exchangeWithLedger":
                        guard let apdu = data?["arg0"] as? String else {
                            assertionFailure()
                            return
                        }
                        WalletCoreData.notify(event: .exchangeWithLedger(apdu: apdu, callback: { response in
                            do {
                                if response == nil {
                                    log.error("exchangeWithLedger error!")
                                }
                                _ = try await self.webView?.nativeCallOk(requestNumber: requestNumber, result: response)
                            } catch {
                                log.fault("Error injecting exchangeWithLedger response to JavaScript: \(error)")
                            }
                        }))
                        
                    case "isLedgerJettonIdSupported":
                        WalletCoreData.notify(event: .isLedgerJettonIdSupported(callback: { response in
                            do {
                                if response == nil {
                                    log.error("isLedgerJettonIdSupported error!")
                                }
                                _ = try await self.webView?.nativeCallOk(requestNumber: requestNumber, result: response)
                            } catch {
                                log.fault("Error injecting isLedgerJettonIdSupported response to JavaScript: \(error)")
                            }
                        }))
                        
                    case "isLedgerUnsafeSupported":
                        WalletCoreData.notify(event: .isLedgerUnsafeSupported(callback: { response in
                            do {
                                if response == nil {
                                    log.error("isLedgerUnsafeSupported error!")
                                }
                                _ = try await self.webView?.callAsyncJavaScript(NATIVE_CALL_OK, arguments: [
                                    "requestNumber": requestNumber,
                                    "result": response as Any
                                ], contentWorld: .page)
                            } catch {
                                log.fault("Error injecting isLedgerJettonIdSupported response to JavaScript: \(error)")
                            }
                        }))
                        
                    default:
                        fatalError("nativeCall (\(methodName)) not defined.")
                        break
                    }
                }
                
            case "onUpdate":
                
                guard let data = (data?["update"] as? String)?.toDictionary,
                      let updateType = data["type"] as? String
                else {
                    return
                }
//                logUpdate.info("\(updateType, .public)", fileOnly: updateType == "updatingStatus")
                #if DEBUG
//                if updateType != "updatingStatus" {
//                    log.debug("onUpdate: \(updateType)")
//                    //                log.debug("\(data)")
//                }
                #endif
                switch updateType {
                case "updateAccount":
                    #warning("TODO: updateAccount")
                    break
                case "updateAccountConfig":
                    #warning("TODO: updateAccountConfig")
                    break
                    
                case "initialActivities":
                    guard let accountId = data["accountId"] as? String else {
                        return
                    }
                    logUpdate.info("initialActivities - \(accountId, .public)")
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.InitialActivities.self, from: data)
                        WalletCoreData.notify(event: .initialActivities(update))
                    } catch {
                        log.fault("failed to decode initialActivities \(error, .public)")
                    }
                    break
                    
                case "updateBalances":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.UpdateBalances.self, from: data)
                        WalletCoreData.notify(event: .updateBalances(update))
                    } catch {
                        log.fault("failed to decode updateBalances \(error, .public)")
                    }
                    
                case "updateTokens":
                    WalletCoreData.notify(event: .updateTokens(data))

                case "updateWalletVersions":
                    guard let accountId = data["accountId"] as? String else {
                        return
                    }
                    let walletVersionsData = MWalletVersionsData(dictionary: data)
                    if AccountStore.accountId != accountId {
                        return
                    }
                    AccountStore.walletVersionsData = walletVersionsData
                    WalletCoreData.notify(event: .walletVersionsDataReceived, for: accountId)
                    break
                case "updateSwapTokens":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.UpdateSwapTokens.self, from: data)
                        WalletCoreData.notify(event: .updateSwapTokens(update))
                    } catch {
                        log.fault("failed to decode updateSwapTokens \(error, .public)")
                    }
                    
                case "updateVesting":
                    break
                    
                case "newLocalActivities":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.NewLocalActivities.self, from: data)
                        WalletCoreData.notify(event: .newLocalActivity(update))
                    } catch {
                        log.fault("failed to decode newLocalActivities \(error, .public)")
                    }
                    
                case "newActivities":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.NewActivities.self, from: data)
                        WalletCoreData.notify(event: .newActivities(update))
                    } catch {
                        log.fault("failed to decode newActivities \(error, .public)")
                    }

                case "updateNfts":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.UpdateNfts.self, from: data)
                        WalletCoreData.notify(event: .updateNfts(update))
                    } catch {
                        log.error("failed to decode updateNfts: \(error, .public)")
                    }
                
                case "nftReceived":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.NftReceived.self, from: data)
                        WalletCoreData.notify(event: .nftReceived(update))
                    } catch {
                        log.error("failed to decode nftReceived: \(error, .public)")
                    }

                case "nftSent":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.NftSent.self, from: data)
                        WalletCoreData.notify(event: .nftSent(update))
                    } catch {
                        log.error("failed to decode nftSent: \(error, .public)")
                    }

                case "nftPutUpForSale":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.NftPutUpForSale.self, from: data)
                        WalletCoreData.notify(event: .nftPutUpForSale(update))
                    } catch {
                        log.error("failed to decode nftPutUpForSale: \(error, .public)")
                    }
                    
                case "updateRegion":
                    break

                case "updateStaking":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.UpdateStaking.self, from: data)
                        WalletCoreData.notify(event: .updateStaking(update))
                    } catch {
                        log.error("failed to decode updateStaking: \(error, .public)")
                        assertionFailure()
                    }

                case "updatingStatus":
                    guard let isUpdating = data["isUpdating"] as? Bool else { return }
                    switch data["kind"] as? String {
                    case "activities":
                        AccountStore.updatingActivities = isUpdating
                    case "balance":
                        AccountStore.updatingBalance = isUpdating
                    default:
                        return
                    }
                    log.info("updatingStatus \(data["kind"] ?? "?", .public)=\(isUpdating)", fileOnly: true)
                    WalletCoreData.notify(event: .updatingStatusChanged, for: nil)
                    break
                case "updateConfig":
                    do {
                        var update = try JSONSerialization.decode(ApiUpdate.UpdateConfig.self, from: data)
//                        update.isLimited = true
                        ConfigStore.shared.config = update
                    } catch {
                        log.error("failed to decode updateConfig: \(error, .public)")
                    }
                    break
                case "dappLoading":
                    break
                case "dappConnect":
                    guard let accountId = data["accountId"] as? String else {
                        return
                    }
                    if AccountStore.accountId != accountId {
                        return
                    }
                    DispatchQueue.global(qos: .background).async {
                        do {
                            let dappConnect = try JSONSerialization.decode(ApiUpdate.DappConnect.self, from: data)
                            WalletCoreData.notify(event: .dappConnect(request: dappConnect), for: nil)
                        } catch {
                            assertionFailure()
                        }
                    }
                case "dappConnectComplete":
                    DappsStore.updateDappCount()
                case "dappSendTransactions":
                    do {
                        let value = try JSONSerialization.decode(MDappSendTransactions.self, from: data)
                        WalletCoreData.notify(event: .dappSendTransactions(value), for: nil)
                    } catch {
                        assertionFailure()
                    }
                case "dappDisconnect":
                    if let accountId = data["acountId"] as? String, let origin = data["origin"] as? String {
                        WalletCoreData.notify(event: .dappDisconnect(accountId: accountId, origin: origin), for: nil)
                    }
                case "updateDapps":
                    WalletCoreData.notify(event: .updateDapps, for: nil)

                case "dappTransferComplete":
                    break

                case "dappCloseLoading":
                    break
                    
                case "updateAccountDomainData":
                    #warning("TODO: updateAccountDomainData")
                    break

                case "showError":
                    #warning("TODO: showError")
                    break

                default:
                    log.error("UNKNOWN UPDATE DATA TYPE: \(updateType, .public)")
                    assertionFailure()
                    break
                }
                break
            default:
                fatalError()
                break
            }
        }
    }
}

extension JSWebViewBridge: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectIfNeeded()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
    }
    func webView(_ webView: WKWebView,
                        didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: any Error) {
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        return .allow
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        return .allow
    }
    
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("WebView terminated, reloading...")
        recreateWebView {
            if let accountId = AccountStore.account?.id {
                Task {
                    try? await Api.activateAccount(accountId: accountId, newestActivityTimestamps: nil)
                }
            }
        }
    }
}


fileprivate extension WKWebView {
    func nativeCallOk(requestNumber: Int, result: Any?) async throws {
        _ = try await callAsyncJavaScript(NATIVE_CALL_OK, arguments: [
            "requestNumber": requestNumber,
            "result": result as Any
        ], contentWorld: .page)
    }
    
    func nativeCallOkVoid(requestNumber: Int) async throws {
        _ = try await callAsyncJavaScript(NATIVE_CALL_OK_VOID, arguments: [
            "requestNumber": requestNumber
        ], contentWorld: .page)
    }
}
