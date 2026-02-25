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

@MainActor final class InAppBrowserMessageHandler: NSObject, WKScriptMessageHandler {
    
    var config: InAppBrowserPageConfig
    weak var webView: WKWebView?
    
    init(config: InAppBrowserPageConfig) {
        self.config = config
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task {
            do {
                try await handleMessage(message)
            } catch {
                log.error("unexpected error: \(error, .public)")
            }
        }
    }
    
    private func handleMessage(_ message: WKScriptMessage) async throws {
        guard
            let body = message.body as? String,
            let dict = try? JSONSerialization.jsonObject(withString: body) as? [String: Any]
        else { return }
        
        switch dict["type"] as? String {
        case DappConnectMessageType.invokeFunc:
            try await handleInvokeFunc(dict: dict)
        default:
            break
        }
    }
    
    private func handleInvokeFunc(dict: [String: Any]) async throws {
        let name = dict["name"] as? String
        switch name {
        case "tonConnect:connect":
            try await handleTonConnectConnect(dict: dict)
            
        case "tonConnect:restoreConnection":
            try await handleTonConnectReconnect(dict: dict)

        case "tonConnect:disconnect":
            try await handleTonConnectDisconnect(dict: dict)

        case "tonConnect:send":
            try await handleTonConnectSend(dict: dict)

        case "walletConnect:connect":
            try await handleWalletConnectConnect(dict: dict)

        case "walletConnect:reconnect":
            try await handleWalletConnectReconnect(dict: dict)

        case "walletConnect:disconnect":
            try await handleWalletConnectDisconnect(dict: dict)

        case "walletConnect:sendTransaction":
            try await handleWalletConnectSendTransaction(dict: dict)

        case "walletConnect:signData":
            try await handleWalletConnectSignData(dict: dict)

        case "window:open":
            if let args = dict["args"] as? [String: Any], let urlString = args["url"] as? String, let url = URL(string: urlString) {
                if WalletContextManager.delegate?.handleDeeplink(url: url) ?? false {
                    return
                }
                AppActions.openInBrowser(url, title: nil, injectDappConnect: true)
            }
            
        case "window:close":
            log.error("window:close not implemented")
            
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

    private func makeDappRequest(accountId: String?) -> ApiDappRequest? {
        guard let accountId, let origin = config.url.origin else { return nil }
        let isUrlEnsured = webView?.hasOnlySecureContent
        return ApiDappRequest(url: origin, isUrlEnsured: isUrlEnsured, accountId: accountId, identifier: JSBRIDGE_IDENTIFIER, sseOptions: nil)
    }
    
    // MARK: - TonConnect
    
    private func handleTonConnectConnect(dict: [String: Any]) async throws {
        guard let connectArgs = dict["args"] as? [Any],
              let invocationId = dict["invocationId"] as? String,
              let tcVersion = connectArgs.first as? Int,
              connectArgs.count > 1,
              let tonConnectArgs = connectArgs[1] as? [String: Any]
        else { return }
        if tcVersion > supportedTonConnectVersion {
            return
        }
        guard let dappArg = makeDappRequest(accountId: AccountStore.accountId),
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
            try await injectDappConnectResult(invocationId: invocationId, result: event)
        } catch {
            let event = buildTonConnectConnectError(requestId: requestId, message: error.localizedDescription)
            try await injectDappConnectResult(invocationId: invocationId, result: event)
        }
    }
    
    private func handleTonConnectReconnect(dict: [String: Any]) async throws {
        guard let invocationId = dict["invocationId"] as? String else {
            return
        }
        guard let dappArg = makeDappRequest(accountId: AccountStore.accountId) else { return }
        let requestId = Api.tonConnectRequestId
        do {
            let result = try await Api.tonConnect_reconnect(request: dappArg, requestId: requestId)
            let event = buildTonConnectConnectEvent(from: result, requestId: requestId)
            try await injectDappConnectResult(invocationId: invocationId, result: event)
        } catch {
            let event = buildTonConnectConnectError(requestId: requestId, message: error.localizedDescription)
            try await injectDappConnectResult(invocationId: invocationId, result: event)
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
    
    private func handleTonConnectDisconnect(dict: [String: Any]) async throws {
        guard let invocationId = dict["invocationId"] as? String else {
            return
        }
        guard let dappArg = makeDappRequest(accountId: AccountStore.accountId) else { return }
        let requestId = String(Api.tonConnectRequestId)
        let message = ApiDappDisconnectRequest(requestId: requestId)
        do {
            let response = try await Api.tonConnect_disconnect(request: dappArg, message: message)
            try await handleDappMethodResult(response, invocationId: invocationId)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage)
        }
    }
    
    private func handleTonConnectSend(dict: [String: Any]) async throws {
        guard let invocationId = dict["invocationId"] as? String else {
            return
        }
        do {
            let requests = try decodeWalletActionRequestsArray(args: dict["args"])
            guard let accountId = AccountStore.account?.id else { throw TonConnectError(code: .badRequestError) }
            let request = try requests.first.orThrow()
            guard let dapp = makeDappRequest(accountId: accountId) else { throw TonConnectError(code: .badRequestError) }
            
            switch request.method {
            case .sendTransaction:
                let payload: TonConnectTransactionPayload = try decodeJsonString(request.params.first)
                let message = ApiTonConnectSendTransactionRequest(id: request.id, chain: .ton, payload: payload)
                let response = try await Api.tonConnect_sendTransaction(request: dapp, message: message)
                try await handleDappMethodResult(response, invocationId: invocationId)

            case .signData:
                let payload: SignDataPayload = try decodeJsonString(request.params.first)
                let message = ApiTonConnectSignDataRequest(id: request.id, chain: .ton, payload: payload)
                let response = try await Api.tonConnect_signData(request: dapp, message: message)
                try await handleDappMethodResult(response, invocationId: invocationId)
                
            case .disconnect:
                throw TonConnectError(code: .methodNotSupported)
            }
        } catch let error as TonConnectError {
            let message = TonConnectErrorCodes[error.code.rawValue] ?? badRequestMessage
            try await injectDappConnectError(invocationId: invocationId, message: message)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage)
        }
    }
    
    // MARK: - WalletConnect
    
    private func handleWalletConnectConnect(dict: [String: Any]) async throws {
        guard let invocationId = dict["invocationId"] as? String,
              let args = dict["args"] as? [Any],
              let payload = args.first,
              let message = try? JSONSerialization.decode(ApiDappConnectionRequest<AnyCodable>.self, from: payload)
        else { return }
        guard let dappArg = makeDappRequest(accountId: AccountStore.accountId) else { return }
        let requestId = Api.walletConnectRequestId
        do {
            let response = try await Api.walletConnect_connect(request: dappArg, message: message, requestId: requestId)
            try await injectDappConnectResult(invocationId: invocationId, result: response)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage)
        }
    }
    
    private func handleWalletConnectReconnect(dict: [String: Any]) async throws {
        guard let invocationId = dict["invocationId"] as? String else {
            return
        }
        guard let dappArg = makeDappRequest(accountId: AccountStore.accountId) else { return }
        let requestId = Api.walletConnectRequestId
        do {
            let response = try await Api.walletConnect_reconnect(request: dappArg, requestId: requestId)
            try await injectDappConnectResult(invocationId: invocationId, result: response)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage)
        }
    }
    
    private func handleWalletConnectDisconnect(dict: [String: Any]) async throws {
        guard let invocationId = dict["invocationId"] as? String,
              let args = dict["args"] as? [Any],
              let payload = args.first,
              let message = try? JSONSerialization.decode(ApiDappDisconnectRequest.self, from: payload)
        else { return }
        guard let dappArg = makeDappRequest(accountId: AccountStore.accountId) else { return }
        do {
            let response = try await Api.walletConnect_disconnect(request: dappArg, message: message)
            try await handleDappMethodResult(response, invocationId: invocationId)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage)
        }
    }
    
    private func handleWalletConnectSendTransaction(dict: [String: Any]) async throws {
        guard let invocationId = dict["invocationId"] as? String,
              let args = dict["args"] as? [Any],
              let payload = args.first,
              let message = try? JSONSerialization.decode(ApiDappTransactionRequest<AnyCodable>.self, from: payload)
        else { return }
        guard let dappArg = makeDappRequest(accountId: AccountStore.accountId) else { return }
        do {
            let response = try await Api.walletConnect_sendTransaction(request: dappArg, message: message)
            try await handleDappMethodResult(response, invocationId: invocationId)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage)
        }
    }
    
    private func handleWalletConnectSignData(dict: [String: Any]) async throws {
        guard let invocationId = dict["invocationId"] as? String,
              let args = dict["args"] as? [Any],
              let payload = args.first,
              let message = try? JSONSerialization.decode(ApiDappSignDataRequest<AnyCodable>.self, from: payload)
        else { return }
        guard let dappArg = makeDappRequest(accountId: AccountStore.accountId) else { return }
        do {
            let response = try await Api.walletConnect_signData(request: dappArg, message: message)
            try await handleDappMethodResult(response, invocationId: invocationId)
        } catch {
            try await injectDappConnectError(invocationId: invocationId, message: badRequestMessage)
        }
    }
    
    // MARK: - Utils
    
    private func handleDappMethodResult<T: Encodable>(_ response: ApiDappMethodResult<T>, invocationId: String) async throws {
        if response.success, let result = response.result {
            try await injectDappConnectResult(invocationId: invocationId, result: result)
        } else {
            let message = response.error?.message ?? badRequestMessage
            try await injectDappConnectError(invocationId: invocationId, message: message)
        }
    }

    private func injectDappConnectResult<T: Encodable>(invocationId: String, result: T) async throws {
        try await injectDappConnectResponse(invocationId: invocationId, status: .fulfilled, data: result)
    }

    private func injectDappConnectError(invocationId: String, message: String) async throws {
        try await injectDappConnectResponse(invocationId: invocationId, status: .rejected, data: message)
    }

    private func injectDappConnectResponse<T: Encodable>(invocationId: String, status: InAppBrowserFunctionResponseStatus, data: T) async throws {
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
            window.dispatchEvent(new MessageEvent('message', {
              data: resultInJSON
            }));
            """,
            arguments: [
              "resultInJSON": resultInJSON,
            ],
            contentWorld: .page
        )
    }
}
