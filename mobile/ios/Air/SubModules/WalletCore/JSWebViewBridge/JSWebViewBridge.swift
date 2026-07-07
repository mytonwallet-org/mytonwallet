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
private var sdkIndexFileURL: URL {
    Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "JS")!
}
private let sdkReadAccessURL = sdkIndexFileURL.deletingLastPathComponent()

// The bridge to use mytonwallet js logic in Swift applications.
public class JSWebViewBridge: UIViewController {
    
    private var webView: WKWebView?
    private let start = Date()
    private var isApiReady = false
    private var bridgeReadyWaiters: [CheckedContinuation<Void, Never>] = []

    private let updateQueue = DispatchQueue(label: "onUpdate", qos: .background, attributes: [.concurrent])

    public override func viewDidLoad() {
        super.viewDidLoad()
        StartupTrace.beginInterval("bridge.startup")
        StartupTrace.markOnce("bridge.viewDidLoad")
        
        recreateWebView()
        view.isUserInteractionEnabled = false
        view.alpha = 0.1

        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let webView = self?.webView else { return }
                _ = try? await webView.evaluateJavaScript(";")
            }
        }
    }

    private var onBridgeReady: (() -> Void)? = nil
    func recreateWebView(onCompletion: (() -> Void)? = nil) {
        StartupTrace.markOnce("bridge.recreateWebView")
        onBridgeReady = onCompletion
        isApiReady = false
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
        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1, height: 1),
            configuration: webViewConfiguration
        )
        webView?.navigationDelegate = self
        webView?.uiDelegate = self
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView?.isInspectable = true
        }
        #endif

        view.addSubview(webView!)
        if isViewAppeared {
            loadHtml()
        }
    }
    
    public func moveToViewController(_ parentViewController: UIViewController) {
        guard self.parent !== parentViewController else { return }
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
        parentViewController.addChild(self)
        parentViewController.view.addSubview(view)
        didMove(toParent: parentViewController)
    }
    
    var isViewAppeared = false
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !isViewAppeared {
            StartupTrace.markOnce("bridge.viewWillAppear.first")
            loadHtml()
            isViewAppeared = true
        }
    }
    
    private func loadHtml() {
        StartupTrace.markOnce("bridge.loadHtml")
        webView?.loadFileURL(sdkIndexFileURL, allowingReadAccessTo: sdkReadAccessURL)
    }
    
    private func _callApiImpl(methodName: String, args: [AnyEncodable?]) async throws -> String? {
        let jsonData = try! JSONEncoder().encode(args)
        let argsString = String(data: jsonData, encoding: .utf8)!
        
        if self.webView == nil { // app switched to legacy mode
            throw SdkError.sdkNotReady(methodName: methodName, reason: "Switched to legacy app")
        }
        if !isApiReady {
            await waitUntilBridgeIsReady()
        }
        guard self.webView != nil else {
            throw SdkError.sdkNotReady(methodName: methodName, reason: "Switched to legacy app")
        }
        
        let webView = self.webView!
        let rawResult: Any?
        do {
            rawResult = try await webView.callAsyncJavaScript(CALL_API, arguments: ["methodName": methodName, "argsString": argsString], contentWorld: .page)
        } catch {
            try _parseError(error, methodName: methodName)
        }
        guard let rawResult else {
            return nil
        }
        guard let responseString = rawResult as? String else {
            throw SdkError.invalidResponse(
                methodName: methodName,
                reason: "SDK returned unsupported response type \(type(of: rawResult))",
                data: String(describing: rawResult)
            )
        }
        return responseString
    }
    
    private func _parseError(_ error: any Error, methodName: String) throws -> Never {
        log.fault("callAsyncJavaScript callApi(\(methodName, .public)) error \(error, .public)")
        if let error = error as? SdkError {
            throw error
        }
        if error is CancellationError || Task.isCancelled {
            throw CancellationError()
        }
        if let error = error as? WKError {
            switch error.code {
            case .javaScriptExceptionOccurred:
                if let message = error.errorUserInfo["WKJavaScriptExceptionMessage"] as? String {
                    let exception = SdkJavaScriptException(methodName: methodName, exceptionMessage: message)
                    if exception.message == "err! callApi not found!" {
                        throw SdkError.sdkNotReady(methodName: methodName, reason: exception.message)
                    }
                    throw SdkError.javaScriptException(exception)
                }
            case .javaScriptResultTypeIsUnsupported:
                log.fault("javaScriptResultTypeIsUnsupported")
                throw SdkError.invalidResponse(
                    methodName: methodName,
                    reason: error.localizedDescription,
                    data: nil
                )
            default:
                break
            }
        }
        throw SdkError.unexpected(
            message: error.localizedDescription,
            context: String(describing: error)
        )
    }
    
    nonisolated(nonsending) func callApiRaw<each E: Encodable>(_ methodName: String, _ args: repeat each E) async throws -> sending Any? {
        if let responseString = try await _callApiImpl(methodName: methodName, args: asAnyEncodables(repeat each args)) {
            do {
                return try JSONSerialization.jsonObject(withString: responseString)
            } catch {
                try SdkError.tryToParseStringAsErrorAndThrow(dataString: responseString)
                throw SdkError.decoding(SdkDecodingError(
                    methodName: methodName,
                    responseType: "Any",
                    underlyingError: error,
                    data: responseString
                ))
            }
        } else {
            return nil
        }
    }
    
    nonisolated(nonsending) func callApi<each E: Encodable & Sendable, T: Decodable & Sendable>(_ methodName: String, _ args: repeat each E, decoding: T.Type) async throws -> T {
        let responseString = try await _callApiImpl(methodName: methodName, args: asAnyEncodables(repeat each args))
        guard let responseString else {
            throw SdkError.invalidResponse(
                methodName: methodName,
                reason: "SDK returned no response for \(T.self)",
                data: nil
            )
        }
        do {
            return try JSONDecoder().decode(T.self, fromString: responseString)
        } catch {
            try SdkError.tryToParseStringAsErrorAndThrow(dataString: responseString)
            throw SdkError.decoding(SdkDecodingError(
                methodName: methodName,
                responseType: String(describing: T.self),
                underlyingError: error,
                data: responseString
            ))
        }
    }
    
    nonisolated(nonsending) func callApiOptional<each E: Encodable, T: Decodable>(_ methodName: String, _ args: repeat each E, decodingOptional: T.Type) async throws -> T? {
        let responseString = try await _callApiImpl(methodName: methodName, args: asAnyEncodables(repeat each args))
        if let responseString {
            do {
                return try JSONDecoder().decode(T.self, fromString: responseString)
            } catch {
                try SdkError.tryToParseStringAsErrorAndThrow(dataString: responseString)
                throw SdkError.decoding(SdkDecodingError(
                    methodName: methodName,
                    responseType: "\(T.self)?",
                    underlyingError: error,
                    data: responseString
                ))
            }
        } else {
            return nil
        }
    }
    
    nonisolated(nonsending) func callApiVoid<each E: Encodable>(_ methodName: String, _ args: repeat each E, tryToParseError: Bool = true, assertIsNil: Bool = true) async throws {
        let responseString = try await _callApiImpl(methodName: methodName, args: asAnyEncodables(repeat each args))
        if tryToParseError, let responseString {
            try SdkError.tryToParseStringAsErrorAndThrow(dataString: responseString)
        }
        if assertIsNil, let responseString {
            throw SdkError.invalidResponse(
                methodName: methodName,
                reason: "SDK returned a response for a void API call",
                data: responseString
            )
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
                self?.isApiReady = true
                let waiters = self?.bridgeReadyWaiters ?? []
                self?.bridgeReadyWaiters.removeAll()
                waiters.forEach { $0.resume() }
                StartupTrace.markOnce("bridge.injected")
                StartupTrace.endInterval("bridge.startup", details: "result=ready")
                WalletContextManager.delegate?.bridgeIsReady()
                self?.onBridgeReady?()
                self?.onBridgeReady = nil
            }
        }
    }

    private func waitUntilBridgeIsReady() async {
        guard !isApiReady else { return }
        await withCheckedContinuation { continuation in
            bridgeReadyWaiters.append(continuation)
        }
    }
    
    func stop() {
        isApiReady = false
        let waiters = bridgeReadyWaiters
        bridgeReadyWaiters.removeAll()
        waiters.forEach { $0.resume() }
        webView?.removeFromSuperview()
        webView = nil
    }
}

extension JSWebViewBridge: WKScriptMessageHandler { // todo: move to a separate class
    public func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        assert(Thread.isMainThread)
        nonisolated(unsafe) let body = message.body
        let messageName = message.name
        updateQueue.async {
            assert(!Thread.isMainThread)
            nonisolated(unsafe) let data = body as? [String: Any]
            switch messageName {
            case "log":
                var body = body
                if let arr = body as? [Any] {
                    body = arr.map { String(describing: $0) }.joined(separator: " ")
                }
                let string = "\(body)"
                console.info("\(string, .public)", fileOnly: string.contains("POST") || string.contains("GET") || string.contains("toncenter: "))
                
            case "nativeCall":
                guard let requestNumber = data?["requestNumber"] as? Int,
                      let methodName = data?["methodName"] as? String else {
                    return
                }
                Task { @MainActor in
                    
                    func completeNativeCallVoid() async {
                        do {
                            _ = try await self.webView?.nativeCallOkVoid(requestNumber: requestNumber)
                        } catch {
                            log.fault("Error injecting \(methodName) response to JavaScript: \(error)")
                        }
                    }
                    
                    func completeNativeCallOk(result: sending Any?) async {
                        do {
                            _ = try await self.webView?.nativeCallOk(requestNumber: requestNumber, result: result)
                        } catch {
                            log.fault("Error injecting \(methodName) response to JavaScript: \(error)")
                        }
                    }
                    
                    switch methodName {
                    case "capacitorStorageGetItem":
                        guard let key = data?["arg0"] as? String
                        else {
                            await completeNativeCallVoid()
                            return
                        }
                        let result = KeychainHelper.getStorage(key: key)
                        await completeNativeCallOk(result: result)
                        
                    case "capacitorStorageSetItem":
                        if let key = data?["arg0"] as? String, let value = data?["arg1"] as? String {
                            KeychainHelper.saveStorage(key: key, value: value)
                        }
                        await completeNativeCallVoid()
                        
                    case "capacitorStorageRemoveItem":
                        if let key = data?["arg0"] as? String {
                            KeychainHelper.saveStorage(key: key, value: nil)
                        }
                        await completeNativeCallVoid()
                        
                    case "capacitorStorageKeys":
                        await completeNativeCallOk(result: KeychainHelper.keys())
                        
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
                        
                    case "getLedgerDeviceModel":
                        WalletCoreData.notify(event: .getLedgerDeviceModel(callback: { response in
                            do {
                                if response == nil {
                                    log.error("getLedgerDeviceModel error!")
                                }
                                let json = try? response?.json()
                                _ = try await self.webView?.callAsyncJavaScript(NATIVE_CALL_OK, arguments: [
                                    "requestNumber": requestNumber,
                                    "result": json as Any,
                                ], contentWorld: .page)
                            } catch {
                                log.fault("Error injecting isLedgerJettonIdSupported response to JavaScript: \(error)")
                            }
                        }))
                        
                    default:
                        fatalError("nativeCall (\(methodName)) not defined.")
                    }
                }
                
            case "onUpdate":
                
                guard let data = (data?["update"] as? String)?.toDictionary,
                      let updateType = data["type"] as? String
                else {
                    return
                }
//                log.info("\(updateType, .public)", fileOnly: updateType == "updatingStatus")
                #if DEBUG
//                if updateType != "updatingStatus" {
//                    log.debug("onUpdate: \(updateType)")
//                    //                log.debug("\(data)")
//                }
                #endif
                switch updateType {
                case "updateAccount":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.UpdateAccount.self, from: data)
                        WalletCoreData.notify(event: .updateAccount(update))
                    } catch {
                        log.fault("failed to decode updateAccount \(error, .public)")
                    }

                case "updateAccountConfig":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.UpdateAccountConfig.self, from: data)
                        WalletCoreData.notify(event: .updateAccountConfig(update))
                    } catch {
                        log.fault("failed to decode updateAccountConfig \(error, .public)")
                    }
                    break
                    
                case "initialActivities":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.InitialActivities.self, from: data)
                        log.info("initialActivities - \(update.accountId, .public)")
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
                
                case "updateCurrencyRates":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.UpdateCurrencyRates.self, from: data)
                        WalletCoreData.notify(event: .updateCurrencyRates(update))
                    } catch {
                        log.fault("failed to decode updateCurrencyRates \(error, .public)")
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
                    WalletCoreData.notify(event: .walletVersionsDataReceived)
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
//                        assertionFailure()
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
                    WalletCoreData.notify(event: .updatingStatusChanged)
                    break
                case "updateConfig":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.UpdateConfig.self, from: data)
//                        update.isLimited = true
                        ConfigStore.shared.config = update
                    } catch {
                        log.error("failed to decode updateConfig: \(error, .public)")
                    }
                    break
                case "dappLoading":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.DappLoading.self, from: data)
                        WalletCoreData.notify(event: .dappLoading(update))
                    } catch {
                        log.error("dappLoading: \(error, .public)")
                    }
                    break
                case "dappAlreadyConnected":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.DappAlreadyConnected.self, from: data)
                        WalletCoreData.notify(event: .dappAlreadyConnected(update))
                    } catch {
                        log.error("dappAlreadyConnected: \(error, .public)")
                    }
                    break
                case "dappDisconnected":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.DappDisconnected.self, from: data)
                        WalletCoreData.notify(event: .dappDisconnected(update))
                    } catch {
                        log.error("dappDisconnected: \(error, .public)")
                    }
                    break
                case "dappConnect":
                    do {
                        let dappConnect = try JSONSerialization.decode(ApiUpdate.DappConnect.self, from: data)
                        WalletCoreData.notify(event: .dappConnect(request: dappConnect))
                    } catch {
                        log.error("dappConnect: \(error, .public)")
                    }
                case "dappConnectComplete":
                    DappsStore.updateDappCount()
                case "dappSendTransactions":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.DappSendTransactions.self, from: data)
                        WalletCoreData.notify(event: .dappSendTransactions(value))
                    } catch {
                        log.fault("dappSendTransactions decode failed: \(error, .public)")
                        assertionFailure("dappSendTransactions decode failed: \(error)")
                    }
                case "dappSignData":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.DappSignData.self, from: data)
                        WalletCoreData.notify(event: .dappSignData(value))
                    } catch {
                        log.fault("dappSignData decode failed: \(error, .public)")
                        assertionFailure("dappSignData decode failed: \(error)")
                    }

                case "walletConnectPayLoading":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.WalletConnectPayLoading.self, from: data)
                        WalletCoreData.notify(event: .walletConnectPayLoading(value))
                    } catch {
                        log.fault("walletConnectPayLoading decode failed: \(error, .public)")
                    }
                case "walletConnectPayCloseLoading":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.WalletConnectPayCloseLoading.self, from: data)
                        WalletCoreData.notify(event: .walletConnectPayCloseLoading(value))
                    } catch {
                        log.fault("walletConnectPayCloseLoading decode failed: \(error, .public)")
                    }
                case "walletConnectPaySignTransaction":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.WalletConnectPaySignTransaction.self, from: data)
                        WalletCoreData.notify(event: .walletConnectPaySignTransaction(value))
                    } catch {
                        log.fault("walletConnectPaySignTransaction decode failed: \(error, .public)")
                        assertionFailure("walletConnectPaySignTransaction decode failed: \(error)")
                    }
                case "walletConnectPaySignTransactionComplete":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.WalletConnectPaySignTransactionComplete.self, from: data)
                        WalletCoreData.notify(event: .walletConnectPaySignTransactionComplete(value))
                    } catch {
                        log.fault("walletConnectPaySignTransactionComplete decode failed: \(error, .public)")
                    }
                case "walletConnectPaySignData":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.WalletConnectPaySignData.self, from: data)
                        WalletCoreData.notify(event: .walletConnectPaySignData(value))
                    } catch {
                        log.fault("walletConnectPaySignData decode failed: \(error, .public)")
                        assertionFailure("walletConnectPaySignData decode failed: \(error)")
                    }
                case "walletConnectPaySignDataComplete":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.WalletConnectPaySignDataComplete.self, from: data)
                        WalletCoreData.notify(event: .walletConnectPaySignDataComplete(value))
                    } catch {
                        log.fault("walletConnectPaySignDataComplete decode failed: \(error, .public)")
                    }
                case "walletConnectPayDataCollection":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.WalletConnectPayDataCollection.self, from: data)
                        WalletCoreData.notify(event: .walletConnectPayDataCollection(value))
                    } catch {
                        log.fault("walletConnectPayDataCollection decode failed: \(error, .public)")
                        assertionFailure("walletConnectPayDataCollection decode failed: \(error)")
                    }
                case "walletConnectPayDataCollectionComplete":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.WalletConnectPayDataCollectionComplete.self, from: data)
                        WalletCoreData.notify(event: .walletConnectPayDataCollectionComplete(value))
                    } catch {
                        log.fault("walletConnectPayDataCollectionComplete decode failed: \(error, .public)")
                    }
                case "walletConnectPayOptionSelection":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.WalletConnectPayOptionSelection.self, from: data)
                        WalletCoreData.notify(event: .walletConnectPayOptionSelection(value))
                    } catch {
                        log.fault("walletConnectPayOptionSelection decode failed: \(error, .public)")
                        assertionFailure("walletConnectPayOptionSelection decode failed: \(error)")
                    }
                case "walletConnectPayOptionSelectionComplete":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.WalletConnectPayOptionSelectionComplete.self, from: data)
                        WalletCoreData.notify(event: .walletConnectPayOptionSelectionComplete(value))
                    } catch {
                        log.fault("walletConnectPayOptionSelectionComplete decode failed: \(error, .public)")
                    }
                case "walletConnectPayProcessing":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.WalletConnectPayProcessing.self, from: data)
                        WalletCoreData.notify(event: .walletConnectPayProcessing(value))
                    } catch {
                        log.fault("walletConnectPayProcessing decode failed: \(error, .public)")
                        assertionFailure("walletConnectPayProcessing decode failed: \(error)")
                    }
                case "walletConnectPayPaymentComplete":
                    do {
                        let value = try JSONSerialization.decode(ApiUpdate.WalletConnectPayPaymentComplete.self, from: data)
                        WalletCoreData.notify(event: .walletConnectPayPaymentComplete(value))
                    } catch {
                        log.fault("walletConnectPayPaymentComplete decode failed: \(error, .public)")
                        assertionFailure("walletConnectPayPaymentComplete decode failed: \(error)")
                    }

                case "dappDisconnect":
                    if let accountId = data["accountId"] as? String, let origin = data["url"] as? String {
                        WalletCoreData.notify(event: .dappDisconnect(accountId: accountId, origin: origin))
                    }
                case "updateDapps":
                    WalletCoreData.notify(event: .updateDapps)

                case "dappTransferComplete":
                    break

                case "dappSignDataComplete":
                    break

                case "dappCloseLoading":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.DappCloseLoading.self, from: data)
                        WalletCoreData.notify(event: .dappCloseLoading(update))
                    } catch {
                        log.error("dappCloseLoading: \(error, .public)")
                    }
                    
                case "updateAccountDomainData":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.UpdateAccountDomainData.self, from: data)
                        WalletCoreData.notify(event: .updateAccountDomainData(update))
                    } catch {
                        log.fault("failed to decode updateAccountDomainData \(error, .public)")
                    }

                case "showError":
                    if let error = data["error"] as? String {
                        let error = SdkError.apiReturnedError(error: error, context: nil)
                        Task { @MainActor in
                            AppActions.showError(error: error)
                        }
                    }

                case "tonConnectOnline":
                    break
                    
                case "incorrectTime":
                    break
                    
                case "openUrl":
                    do {
                        let update = try JSONSerialization.decode(ApiUpdate.OpenUrl.self, from: data)
                        if update.isExternal == true && update.url == "tg://resolve" {
                            DispatchQueue.main.async {
                                UIApplication.shared.open(URL(string: "tg://resolve")!)
                            }
                        }
                        break
                    } catch {
                        log.error("openUrl: \(error, .public)")
                    }
                    
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
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        WalletCoreData.setLockdownModeEnabled(webView.configuration.defaultWebpagePreferences.isLockdownModeEnabled)
        injectIfNeeded()
    }
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
    }
    public func webView(_ webView: WKWebView,
                        didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: any Error) {
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        return .allow
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        return .allow
    }
    
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
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
    func nativeCallOk(requestNumber: Int, result: sending Any?) async throws {
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
