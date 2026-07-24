import UIKit
import WebKit
import UIDapp
import WalletCore
import WalletContext

private let log = Log("DappMessageHandler")
private let badRequestMessage = "Bad request"

private enum InAppBrowserFunctionResponseStatus: String, Encodable {
    case fulfilled
    case rejected
}

private struct InAppBrowserFunctionResponse<T: Encodable>: Encodable {
    let type: String
    let invocationId: String
    let status: InAppBrowserFunctionResponseStatus
    let data: T
}

private struct InAppBrowserMessageContext {
    let frameInfo: WKFrameInfo
    let origin: String
    let urlTrustStatus: ApiDappUrlTrustStatus
}

@MainActor final class InAppBrowserMessageHandler: NSObject, WKScriptMessageHandler {
    
    var config: InAppBrowserPageConfig
    weak var webView: WKWebView?
    var onOpenWindow: ((URL) -> Void)?
    var onCloseWindow: (() -> Void)?
    
    init(config: InAppBrowserPageConfig) {
        self.config = config
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let context = makeMessageContext(message) else { return }

        Task {
            do {
                try await handleMessage(message, context: context)
            } catch {
                log.error("unexpected error: \(error, .public)")
            }
        }
    }
    
    private func makeMessageContext(_ message: WKScriptMessage) -> InAppBrowserMessageContext? {
        guard config.injectDappConnect,
              let webView,
              let sourceWebView = message.webView,
              sourceWebView === webView,
              message.frameInfo.isMainFrame,
              let origin = resolveInAppBrowserMessageOrigin(
                  scheme: message.frameInfo.securityOrigin.protocol,
                  host: message.frameInfo.securityOrigin.host,
                  port: message.frameInfo.securityOrigin.port
              ) else {
            return nil
        }
        let urlTrustStatus: ApiDappUrlTrustStatus = origin.hasPrefix("https://") && webView.hasOnlySecureContent
            ? .verified
            : .unknown
        return InAppBrowserMessageContext(
            frameInfo: message.frameInfo,
            origin: origin,
            urlTrustStatus: urlTrustStatus
        )
    }

    private func handleMessage(_ message: WKScriptMessage, context: InAppBrowserMessageContext) async throws {
        guard
            let body = message.body as? String,
            let dict = try? JSONSerialization.jsonObject(withString: body) as? [String: Any]
        else { return }
        
        switch dict["type"] as? String {
        case DappConnectMessageType.invokeFunc:
            try await handleInvokeFunc(dict: dict, context: context)
        default:
            break
        }
    }
    
    private func handleInvokeFunc(dict: [String: Any], context: InAppBrowserMessageContext) async throws {
        let name = dict["name"] as? String
        switch name {
        case "tonConnect:connect":
            try await handleTonConnectConnect(dict: dict, context: context)
            
        case "tonConnect:restoreConnection":
            try await handleTonConnectReconnect(dict: dict, context: context)

        case "tonConnect:disconnect":
            try await handleTonConnectDisconnect(dict: dict, context: context)

        case "tonConnect:send":
            try await handleTonConnectSend(dict: dict, context: context)

        case "walletConnect:connect":
            try await handleWalletConnectConnect(dict: dict, context: context)

        case "walletConnect:reconnect":
            try await handleWalletConnectReconnect(dict: dict, context: context)

        case "walletConnect:disconnect":
            try await handleWalletConnectDisconnect(dict: dict, context: context)

        case "walletConnect:sendTransaction":
            try await handleWalletConnectSendTransaction(dict: dict, context: context)

        case "walletConnect:signData":
            try await handleWalletConnectSignData(dict: dict, context: context)

        case "walletConnect:proxyEvmRpc":
            try await handleWalletConnectProxyEvmRpc(dict: dict, context: context)

        case "window:open":
            await acknowledgeInvocation(dict: dict, context: context)
            if let args = dict["args"] as? [String: Any],
               let urlString = args["url"] as? String,
               let url = URL(string: urlString, relativeTo: config.url)?.absoluteURL {
                handleWindowOpen(url)
            }
            
        case "window:close":
            await acknowledgeInvocation(dict: dict, context: context)
            onCloseWindow?()
            
        default:
            assertionFailure("Unexpected invokeFunc: name=\(dict["name"] as Any)")
        }
    }
    
    private func decodeJsonString<T: Decodable>(_ jsonString: String?) throws -> T {
        guard let jsonString, let data = jsonString.data(using: .utf8) else {
            throw TonConnectError(code: .badRequestError)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func makeDappRequest(accountId: String?, context: InAppBrowserMessageContext) -> ApiDappRequest? {
        guard let accountId else { return nil }
        return ApiDappRequest(
            url: context.origin,
            urlTrustStatus: context.urlTrustStatus,
            accountId: accountId,
            identifier: JSBRIDGE_IDENTIFIER,
            sseOptions: nil
        )
    }

    private func handleWindowOpen(_ url: URL) {
        switch resolveInAppBrowserWindowOpenUrlRouting(url) {
        case .consume, .allow, .ignore:
            return
        case .handleDeeplink(let source):
            _ = WalletContextManager.delegate?.handleDeeplink(url: url, source: source)
        case .openSystemUrl:
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:])
            }
        case .openNewPage:
            onOpenWindow?(url)
        }
    }
    
    // MARK: - TonConnect
    
    private func handleTonConnectConnect(dict: [String: Any], context: InAppBrowserMessageContext) async throws {
        guard let connectArgs = dict["args"] as? [Any],
              let invocationId = dict["invocationId"] as? String,
              let tcVersion = connectArgs.first as? Int,
              connectArgs.count > 1,
              let tonConnectArgs = connectArgs[1] as? [String: Any]
        else { return }
        if tcVersion > supportedTonConnectVersion {
            return
        }
        guard let dappArg = makeDappRequest(accountId: AccountStore.accountId, context: context),
              let connectRequest = try? JSONSerialization.decode(TonConnectConnectRequest.self, from: tonConnectArgs)
        else { return }
        let unifiedMessage = ApiDappConnectionRequest(
            protocolType: .tonConnect,
            transport: .inAppBrowser,
            requestedChains: [ApiDappRequestedChain(chain: .ton, network: AccountStore.activeNetwork)],
            permissions: ApiDappPermissions(isAddressRequired: true, isPasswordRequired: false),
            protocolData: connectRequest
        )
        let requestId = Api.tonConnectRequestId
        do {
            let result = try await Api.tonConnect_connect(request: dappArg, message: unifiedMessage, requestId: requestId)
            let event = buildTonConnectConnectEvent(from: result, requestId: requestId)
            try await injectDappConnectResult(invocationId: invocationId, result: event, context: context)
        } catch {
            let event = buildTonConnectConnectError(requestId: requestId, message: error.localizedDescription)
            try await injectDappConnectResult(invocationId: invocationId, result: event, context: context)
        }
    }
    
    private func handleTonConnectReconnect(dict: [String: Any], context: InAppBrowserMessageContext) async throws {
        guard let invocationId = dict["invocationId"] as? String else {
            return
        }
        guard let dappArg = makeDappRequest(accountId: AccountStore.accountId, context: context) else { return }
        let requestId = Api.tonConnectRequestId
        do {
            let result = try await Api.tonConnect_reconnect(request: dappArg, requestId: requestId)
            let event = buildTonConnectConnectEvent(from: result, requestId: requestId)
            try await injectDappConnectResult(invocationId: invocationId, result: event, context: context)
        } catch {
            let event = buildTonConnectConnectError(requestId: requestId, message: error.localizedDescription)
            try await injectDappConnectResult(invocationId: invocationId, result: event, context: context)
        }
    }
    
    private func buildTonConnectConnectEvent(from result: ApiDappConnectionResult<TonConnectConnectEvent>, requestId: Int) -> TonConnectConnectEvent {
        if result.success, let session = result.session, let protocolData = session.protocolData {
            return protocolData
        }
        let code = result.error?.code ?? TonConnectErrorCode.unknownError.rawValue
        let message = result.error?.message ?? "Unhandled error"
        return buildTonConnectConnectError(requestId: requestId, message: message, code: code)
    }

    private func buildTonConnectConnectError(requestId: Int, message: String, code: Int = TonConnectErrorCode.unknownError.rawValue) -> TonConnectConnectEvent {
        let payload = TonConnectConnectErrorPayload(code: code, message: message)
        return TonConnectConnectEvent.connectError(id: requestId, payload: payload)
    }
    
    private func handleTonConnectDisconnect(dict: [String: Any], context: InAppBrowserMessageContext) async throws {
        guard let invocationId = dict["invocationId"] as? String else {
            return
        }
        guard let dappArg = makeDappRequest(accountId: AccountStore.accountId, context: context) else { return }
        let requestId = String(Api.tonConnectRequestId)
        let message = ApiDappDisconnectRequest(requestId: requestId)
        do {
            let response = try await Api.tonConnect_disconnect(request: dappArg, message: message)
            try await handleDappMethodResult(response, invocationId: invocationId, context: context)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage, context: context)
        }
    }
    
    private func handleTonConnectSend(dict: [String: Any], context: InAppBrowserMessageContext) async throws {
        guard let invocationId = dict["invocationId"] as? String else {
            return
        }
        do {
            let requests = try decodeWalletActionRequestsArray(args: dict["args"])
            guard let accountId = AccountStore.account?.id else { throw TonConnectError(code: .badRequestError) }
            let request = try requests.first.orThrow()
            guard let dapp = makeDappRequest(accountId: accountId, context: context) else { throw TonConnectError(code: .badRequestError) }
            
            switch request.method {
            case .sendTransaction:
                let payload: TonConnectTransactionPayload = try decodeJsonString(request.params.first)
                let message = ApiTonConnectSendTransactionRequest(id: request.id, chain: .ton, payload: payload)
                let response = try await Api.tonConnect_sendTransaction(request: dapp, message: message)
                try await handleDappMethodResult(response, invocationId: invocationId, context: context)

            case .signData:
                let payload: SignDataPayload = try decodeJsonString(request.params.first)
                let message = ApiTonConnectSignDataRequest(id: request.id, chain: .ton, payload: payload)
                let response = try await Api.tonConnect_signData(request: dapp, message: message)
                try await handleDappMethodResult(response, invocationId: invocationId, context: context)
                
            case .disconnect:
                throw TonConnectError(code: .methodNotSupported)
            }
        } catch let error as TonConnectError {
            let message = TonConnectErrorCodes[error.code.rawValue] ?? badRequestMessage
            try await injectDappConnectError(invocationId: invocationId, message: message, context: context)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage, context: context)
        }
    }
    
    // MARK: - WalletConnect
    
    private func handleWalletConnectConnect(dict: [String: Any], context: InAppBrowserMessageContext) async throws {
        guard let invocationId = dict["invocationId"] as? String else { return }
        do {
            guard let args = dict["args"] as? [Any],
                  let payload = args.first
            else { throw TonConnectError(code: .badRequestError) }
            let message = try JSONSerialization.decode(ApiDappConnectionRequest<AnyCodable>.self, from: payload)
            guard let dappArg = makeDappRequest(accountId: AccountStore.accountId, context: context) else { throw TonConnectError(code: .badRequestError) }
            let requestId = Api.walletConnectRequestId
            let response = try await Api.walletConnect_connect(request: dappArg, message: message, requestId: requestId)
            try await injectDappConnectResult(invocationId: invocationId, result: response, context: context)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage, context: context)
        }
    }
    
    private func handleWalletConnectReconnect(dict: [String: Any], context: InAppBrowserMessageContext) async throws {
        guard let invocationId = dict["invocationId"] as? String else {
            return
        }
        do {
            guard let dappArg = makeDappRequest(accountId: AccountStore.accountId, context: context) else { throw TonConnectError(code: .badRequestError) }
            let requestId = Api.walletConnectRequestId
            let response = try await Api.walletConnect_reconnect(request: dappArg, requestId: requestId)
            try await injectDappConnectResult(invocationId: invocationId, result: response, context: context)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage, context: context)
        }
    }
    
    private func handleWalletConnectDisconnect(dict: [String: Any], context: InAppBrowserMessageContext) async throws {
        guard let invocationId = dict["invocationId"] as? String else { return }
        do {
            guard let args = dict["args"] as? [Any],
                  let payload = args.first
            else { throw TonConnectError(code: .badRequestError) }
            let message = try JSONSerialization.decode(ApiDappDisconnectRequest.self, from: payload)
            guard let dappArg = makeDappRequest(accountId: AccountStore.accountId, context: context) else { throw TonConnectError(code: .badRequestError) }
            let response = try await Api.walletConnect_disconnect(request: dappArg, message: message)
            try await handleDappMethodResult(response, invocationId: invocationId, context: context)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage, context: context)
        }
    }
    
    private func handleWalletConnectSendTransaction(dict: [String: Any], context: InAppBrowserMessageContext) async throws {
        guard let invocationId = dict["invocationId"] as? String else { return }
        do {
            guard let args = dict["args"] as? [Any],
                  let payload = args.first
            else { throw TonConnectError(code: .badRequestError) }
            let message = try JSONSerialization.decode(ApiDappTransactionRequest<AnyCodable>.self, from: payload)
            guard let dappArg = makeDappRequest(accountId: AccountStore.accountId, context: context) else { throw TonConnectError(code: .badRequestError) }
            let response = try await Api.walletConnect_sendTransaction(request: dappArg, message: message)
            try await injectDappConnectResult(invocationId: invocationId, result: response, context: context)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage, context: context)
        }
    }

    private func handleWalletConnectSignData(dict: [String: Any], context: InAppBrowserMessageContext) async throws {
        guard let invocationId = dict["invocationId"] as? String else { return }
        do {
            guard let args = dict["args"] as? [Any],
                  let payload = args.first
            else { throw TonConnectError(code: .badRequestError) }
            let message = try JSONSerialization.decode(ApiDappSignDataRequest<AnyCodable>.self, from: payload)
            guard let dappArg = makeDappRequest(accountId: AccountStore.accountId, context: context) else { throw TonConnectError(code: .badRequestError) }
            let response = try await Api.walletConnect_signData(request: dappArg, message: message)
            try await injectDappConnectResult(invocationId: invocationId, result: response, context: context)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage, context: context)
        }
    }

    private func handleWalletConnectProxyEvmRpc(dict: [String: Any], context: InAppBrowserMessageContext) async throws {
        guard let invocationId = dict["invocationId"] as? String else { return }
        do {
            guard let args = dict["args"] as? [Any],
                  let payload = args.first
            else { throw TonConnectError(code: .badRequestError) }
            let message = try JSONSerialization.decode(ApiDappEvmRpcProxyRequest.self, from: payload)
            guard let dappArg = makeDappRequest(accountId: AccountStore.accountId, context: context) else { throw TonConnectError(code: .badRequestError) }
            let response = try await Api.walletConnect_proxyEvmRpc(request: dappArg, message: message)
            try await injectDappConnectResult(invocationId: invocationId, result: response, context: context)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage, context: context)
        }
    }

    // MARK: - Utils
    
    private func handleDappMethodResult<T: Encodable>(
        _ response: ApiDappMethodResult<T>,
        invocationId: String,
        context: InAppBrowserMessageContext
    ) async throws {
        if response.success, let result = response.result {
            try await injectDappConnectResult(invocationId: invocationId, result: result, context: context)
        } else {
            let message = response.error?.message ?? badRequestMessage
            try await injectDappConnectError(invocationId: invocationId, message: message, context: context)
        }
    }

    private func acknowledgeInvocation(dict: [String: Any], context: InAppBrowserMessageContext) async {
        guard let invocationId = dict["invocationId"] as? String else { return }
        do {
            try await injectDappConnectResult(invocationId: invocationId, result: true, context: context)
        } catch {
            log.error("failed to acknowledge invocation: \(error, .public)")
        }
    }

    private func injectDappConnectResult<T: Encodable>(
        invocationId: String,
        result: T,
        context: InAppBrowserMessageContext
    ) async throws {
        try await injectDappConnectResponse(
            invocationId: invocationId,
            status: .fulfilled,
            data: result,
            context: context
        )
    }

    private func injectDappConnectError(
        invocationId: String,
        message: String,
        context: InAppBrowserMessageContext
    ) async throws {
        try await injectDappConnectResponse(
            invocationId: invocationId,
            status: .rejected,
            data: message,
            context: context
        )
    }

    private func injectDappConnectResponse<T: Encodable>(
        invocationId: String,
        status: InAppBrowserFunctionResponseStatus,
        data: T,
        context: InAppBrowserMessageContext
    ) async throws {
        let response = InAppBrowserFunctionResponse(
            type: DappConnectMessageType.functionResponse,
            invocationId: invocationId,
            status: status,
            data: data
        )
        let jsonData = try JSONEncoder().encode(response)
        guard let resultInJSON = String(data: jsonData, encoding: .utf8) else { return }
        _ = try await webView?.callAsyncJavaScript(
            """
            if (window.location.origin !== expectedOrigin) {
              throw new Error('The dApp page changed while the request was pending');
            }
            window.dispatchEvent(new MessageEvent('message', {
              data: resultInJSON
            }));
            """,
            arguments: [
              "expectedOrigin": context.origin,
              "resultInJSON": resultInJSON,
            ],
            in: context.frameInfo,
            contentWorld: .page
        )
    }
}
