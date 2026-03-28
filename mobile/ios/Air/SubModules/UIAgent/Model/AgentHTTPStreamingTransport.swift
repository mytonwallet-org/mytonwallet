import Foundation
import WalletContext

private enum AgentHTTPStreamingTransportMetrics {
    static let requestTimeout: TimeInterval = 120
}

private let log = Log("AgentHTTPStream")

struct AgentRealBackendRequest: Encodable {
    let clientId: String
    let text: String
    let context: AgentRequestContext?
}

private struct AgentHintsResponse: Decodable {
    let items: [AgentHint]
}

protocol AgentRealBackendTransport {
    func streamReply(request: AgentRealBackendRequest) -> AsyncThrowingStream<String, Error>
    func loadHints(langCode: String?) async throws -> [AgentHint]
}

enum AgentHTTPStreamingTransportError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The Agent returned an invalid response."
        case .httpStatus(let statusCode, let body):
            if let body, !body.isEmpty {
                return body
            }
            return "The Agent request failed with status \(statusCode)."
        }
    }
}

final class AgentHTTPStreamingTransport: AgentRealBackendTransport {
    private let endpoint: URL

    init(endpoint: URL) {
        self.endpoint = endpoint
    }

    func streamReply(request: AgentRealBackendRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            do {
                var urlRequest = URLRequest(url: endpoint)
                urlRequest.httpMethod = "POST"
                urlRequest.timeoutInterval = AgentHTTPStreamingTransportMetrics.requestTimeout
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.setValue("text/plain", forHTTPHeaderField: "Accept")
                urlRequest.httpBody = try JSONEncoder().encode(request)

                log.info(
                    "start clientId=\(request.clientId, .public) endpoint=\(endpoint.absoluteString, .public) textChars=\(request.text.count) text=\(request.text, .redacted)"
                )

                let requestHandler = AgentHTTPStreamRequestHandler(
                    request: urlRequest,
                    continuation: continuation
                )
                requestHandler.start()
                continuation.onTermination = { _ in
                    requestHandler.cancel()
                }
            } catch {
                log.error("failed to create request error=\(error, .public)")
                continuation.finish(throwing: error)
            }
        }
    }

    func loadHints(langCode: String?) async throws -> [AgentHint] {
        var components = URLComponents(url: hintsEndpoint, resolvingAgainstBaseURL: false)
        if let langCode, !langCode.isEmpty {
            components?.queryItems = [
                URLQueryItem(name: "langCode", value: langCode)
            ]
        }

        guard let url = components?.url else {
            throw AgentHTTPStreamingTransportError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = AgentHTTPStreamingTransportMetrics.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        log.info("load hints endpoint=\(url.absoluteString, .public) langCode=\(langCode ?? "nil", .public)")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentHTTPStreamingTransportError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentHTTPStreamingTransportError.httpStatus(httpResponse.statusCode, body)
        }

        let decodedResponse = try JSONDecoder().decode(AgentHintsResponse.self, from: data)
        log.info("loaded hints count=\(decodedResponse.items.count)")
        return decodedResponse.items
    }

    private var hintsEndpoint: URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return endpoint.deletingLastPathComponent().appendingPathComponent("hints")
        }

        let messagePathSuffix = "/message"
        var path = components.path
        if path.hasSuffix(messagePathSuffix) {
            path.removeLast(messagePathSuffix.count)
            path.append("/hints")
        } else if path.hasSuffix("/") {
            path.append("hints")
        } else {
            path.append("/hints")
        }
        components.path = path
        components.query = nil
        components.fragment = nil

        return components.url ?? endpoint.deletingLastPathComponent().appendingPathComponent("hints")
    }
}

private final class AgentHTTPStreamRequestHandler: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct StreamDataUpdate {
        let awaitingValidUTF8Bytes: Int?
        let delta: String?
        let continuation: AsyncThrowingStream<String, Error>.Continuation?
    }

    private let request: URLRequest
    private let stateLock = NSLock()
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?

    private var session: URLSession?
    private var task: URLSessionDataTask?

    private var statusCode: Int?
    private var successfulResponseData = Data()
    private var errorResponseData = Data()
    private var lastEmittedText = ""
    private var hasFinished = false

    init(
        request: URLRequest,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) {
        self.request = request
        self.continuation = continuation
        super.init()
    }

    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        withLockedState {
            self.session = session
            self.task = task
        }
        task.resume()
    }

    func cancel() {
        let taskToCancel = withLockedState { () -> URLSessionDataTask? in
            guard !hasFinished else { return nil }
            return task
        }
        taskToCancel?.cancel()
        finish(with: nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(with: AgentHTTPStreamingTransportError.invalidResponse)
            return
        }

        let shouldAllowResponse = withLockedState { () -> Bool in
            guard !hasFinished else { return false }
            statusCode = httpResponse.statusCode
            return true
        }
        guard shouldAllowResponse else {
            completionHandler(.cancel)
            return
        }

        log.info("response status=\(httpResponse.statusCode)")
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let rawChunk = String(decoding: data, as: UTF8.self)
        let update = withLockedState { () -> StreamDataUpdate? in
            guard !hasFinished else { return nil }

            if (statusCode ?? 0) >= 200 && (statusCode ?? 0) < 300 {
                successfulResponseData.append(data)
                guard let decodedText = String(data: successfulResponseData, encoding: .utf8),
                      decodedText.hasPrefix(lastEmittedText) else {
                    return StreamDataUpdate(
                        awaitingValidUTF8Bytes: successfulResponseData.count,
                        delta: nil,
                        continuation: nil
                    )
                }

                let delta = String(decodedText.dropFirst(lastEmittedText.count))
                guard !delta.isEmpty else {
                    return StreamDataUpdate(
                        awaitingValidUTF8Bytes: nil,
                        delta: nil,
                        continuation: nil
                    )
                }

                lastEmittedText = decodedText
                return StreamDataUpdate(
                    awaitingValidUTF8Bytes: nil,
                    delta: delta,
                    continuation: continuation
                )
            }

            errorResponseData.append(data)
            return StreamDataUpdate(
                awaitingValidUTF8Bytes: nil,
                delta: nil,
                continuation: nil
            )
        }

        guard let update else { return }

        log.info("raw chunk bytes=\(data.count) data=\(rawChunk, .redacted)")

        if let totalBytes = update.awaitingValidUTF8Bytes {
            log.info("buffer awaiting valid utf8 totalBytes=\(totalBytes)")
        }

        if let delta = update.delta {
            log.info("decoded delta chars=\(delta.count) delta=\(delta, .redacted)")
            update.continuation?.yield(delta)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let nsError = error as NSError? {
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                log.info("request cancelled")
                finish(with: nil)
                return
            }

            log.error("request failed error=\(nsError, .public)")
            finish(with: nsError)
            return
        }

        let statusAndBody = withLockedState { () -> (Int?, String?) in
            (
                statusCode,
                String(data: errorResponseData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        if let statusCode = statusAndBody.0, !(200...299).contains(statusCode) {
            let body = statusAndBody.1
            log.error("request failed status=\(statusCode) body=\(body ?? "", .public)")
            finish(with: AgentHTTPStreamingTransportError.httpStatus(statusCode, body))
            return
        }

        let finalDeltaResult = withLockedState { () -> (String?, AsyncThrowingStream<String, Error>.Continuation?) in
            guard let decodedText = String(data: successfulResponseData, encoding: .utf8),
                  decodedText.hasPrefix(lastEmittedText) else {
                return (nil, nil)
            }
            let finalDelta = String(decodedText.dropFirst(lastEmittedText.count))
            guard !finalDelta.isEmpty else { return (nil, nil) }
            lastEmittedText = decodedText
            return (finalDelta, continuation)
        }

        if let finalDelta = finalDeltaResult.0 {
            log.info("final decoded delta chars=\(finalDelta.count) delta=\(finalDelta, .redacted)")
            finalDeltaResult.1?.yield(finalDelta)
        }

        log.info("request completed successfully")
        finish(with: nil)
    }

    private func finish(with error: Error?) {
        let finishState = withLockedState { () -> (AsyncThrowingStream<String, Error>.Continuation?, URLSession?)? in
            guard !hasFinished else { return nil }
            hasFinished = true

            let continuation = self.continuation
            let session = self.session

            self.continuation = nil
            self.task = nil
            self.session = nil

            return (continuation, session)
        }

        guard let finishState else { return }

        if let error {
            finishState.0?.finish(throwing: error)
        } else {
            finishState.0?.finish()
        }

        finishState.1?.finishTasksAndInvalidate()
    }

    private func withLockedState<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
