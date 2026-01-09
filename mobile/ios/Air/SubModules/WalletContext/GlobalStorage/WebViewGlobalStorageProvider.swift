
import Foundation
import WebKit

private let log = Log("WebViewGlobalStorageProvider")
private let capacitorUrl = URL(string: "capacitor://mytonwallet.local")!
private let globalStateKey = "mytonwallet-global-state"


@MainActor
final class WebViewGlobalStorageProvider: NSObject, WKNavigationDelegate {
    
    @MainActor internal var webView: WKWebView?
    private var loadNavigation: WKNavigation?
    private var loadContinuation: CheckedContinuation<(), any Error>?
    private let capacitorSchemeHander = CapacitorSchemeHandler()
    
    func prepareWebView() async throws(GlobalStorageError) {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(capacitorSchemeHander, forURLScheme: "capacitor")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        webView.navigationDelegate = self
        
        do {
            try await withCheckedThrowingContinuation { continuation in
                self.loadContinuation = continuation
                log.info("[wv] navigation started")
                self.loadNavigation = webView.load(URLRequest(url: capacitorUrl))
            }
        } catch {
            throw .navigationError(error)
        }
    }
    
    func loadFromWebView() async throws(GlobalStorageError) -> Any {
        log.info("[wv] load started")
        try await prepareWebView()
        
        let result: Any
        do {
            log.info("[wv] getItem called")
            result = try await webView!.evaluateJavaScript("localStorage.getItem('\(globalStateKey)')") as Any
            log.info("[wv] getItem result received")
        } catch {
            throw .javaScriptError(error)
        }
        
        if result is NSNull {
            throw .localStorageIsNull
        }
        guard let string = result as? String else {
            throw .localStorageIsNotAString(result)
        }
        let data = string.data(using: .utf8)!
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [.mutableContainers, .mutableLeaves])
        } catch {
            throw .localStorageIsInvalidJson(string)
        }
        return json
    }
    
    func saveToWebView(_ globalDict: Any) async throws(GlobalStorageError) {
        try await prepareWebView()
        guard let webView, webView.url == capacitorUrl, webView.isLoading == false else {
            throw .notReady
        }
        let jsonString: String
        do {
            let data = try JSONSerialization.data(withJSONObject: globalDict, options: [])
            jsonString = String(data: data, encoding: .utf8)!
        } catch {
            throw .serializationError(error)
        }
        let script = """
            try {
                return localStorage.setItem('\(globalStateKey)', jsonString);
            } catch (e) {
                return JSON.stringify(e);
            }
            """
        let maybeError: Any?
        do {
            maybeError = try await webView.callAsyncJavaScript(script, arguments: ["jsonString": jsonString], contentWorld: .page)
        } catch {
            throw .javaScriptError(error)
        }
        if let error = maybeError as? String {
            throw .localStorageSetItemError(error)
        }
    }
    
    func deleteAll() async throws {
        log.info("deleteAll")
        try await prepareWebView()
        let script = """
            localStorage.removeItem('\(globalStateKey)');
            """
        try await webView.orThrow().evaluateJavaScript(script)
    }
    
    func getStoredSize() async throws(GlobalStorageError) -> Int {
        guard let webView, webView.url == capacitorUrl, webView.isLoading == false else {
            throw .notReady
        }
        let result: Any?
        do {
            log.info("[wv] getItem called")
            result = try await webView.evaluateJavaScript("localStorage.getItem('\(globalStateKey)')")
            log.info("[wv] getItem result received")
        } catch {
            throw .javaScriptError(error)
        }
        if result is NSNull {
            throw .localStorageIsNull
        }
        guard let string = result as? String else {
            throw .localStorageIsNotAString(result as Any)
        }
        return string.count
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if navigation === loadNavigation {
            log.info("[wv] navigation finished")
            loadContinuation?.resume()
            loadNavigation = nil
            loadContinuation = nil
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if navigation === loadNavigation {
            log.error("[wv] navigation did fail with error \(error, .public)")
            loadContinuation?.resume(throwing: error)
            loadNavigation = nil
            loadContinuation = nil
        }
    }
    
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.fault("webViewWebContentProcessDidTerminate")
        log.error("trying to reload")
        Task {
            await _retryReload(count: 3)
        }
    }
    
    func _retryReload(count: Int) async {
        do {
            try? await Task.sleep(for: .seconds(max(1, 4 - count)))
            _ = try await loadFromWebView()
            log.error("loadFromWebView returned value")
        } catch {
            log.fault("loadFromWebView error \(error, .public). local")
            LogStore.shared.syncronize()
            if count > 0 {
                await _retryReload(count: count - 1)
            } else {
                fatalError("loadFromWebView continues to fail \(error)")
            }
        }
    }
}

private final class CapacitorSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let emptyHTML = "<html><head><title>GlobalStorage</title></head><body></body></html>"
        let data = emptyHTML.data(using: .utf8)!
        let response = URLResponse(url: urlSchemeTask.request.url!,
                                   mimeType: "text/html",
                                   expectedContentLength: data.count,
                                   textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    }
}
