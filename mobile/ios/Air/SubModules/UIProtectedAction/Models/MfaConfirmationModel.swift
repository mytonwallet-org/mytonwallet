import Foundation
import WalletContext
import WalletCore

private let mfaConfirmationModelLog = Log("MfaConfirmationModel")

enum MfaConfirmationModelEvent: Sendable {
    case confirmed(ApiMfaRequest)
    case failed(any Error)
}

@MainActor
final class MfaConfirmationModel {
    typealias FetchRequest = @MainActor (String) async throws -> ApiMfaRequest

    var onEvent: ((MfaConfirmationModelEvent) -> Void)?

    private let requestHash: String
    private let pollInterval: Duration
    private let fetchRequest: FetchRequest
    private var pollingTask: Task<Void, Never>?
    private var didResolve = false

    var confirmationURL: URL? {
        let url = buildMfaBotUrl(startApp: requestHash)
        if url == nil {
            mfaConfirmationModelLog.error(
                "Failed to build MFA bot url for requestHash: \(requestHash, .public)"
            )
        }
        return url
    }

    init(
        requestHash: String,
        pollInterval: Duration = .seconds(1),
        fetchRequest: @escaping FetchRequest = Api.fetchMfaRequest
    ) {
        self.requestHash = requestHash
        self.pollInterval = pollInterval
        self.fetchRequest = fetchRequest
    }

    func start() {
        guard pollingTask == nil, !didResolve else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if await self.poll() {
                    return
                }
                do {
                    try await Task.sleep(for: self.pollInterval)
                } catch {
                    return
                }
            }
        }
    }

    func cancel() {
        guard !didResolve else { return }
        didResolve = true
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func poll() async -> Bool {
        guard !didResolve else { return true }
        do {
            let request = try await fetchRequest(requestHash)
            guard request.isConfirmed else { return false }
            resolve(.confirmed(request))
            return true
        } catch {
            mfaConfirmationModelLog.error(
                "fetchMfaRequest failed while polling \(requestHash, .public): \(error, .public)"
            )
            guard shouldStopPolling(for: error) else { return false }
            resolve(.failed(error))
            return true
        }
    }

    private func resolve(_ event: MfaConfirmationModelEvent) {
        guard !didResolve else { return }
        didResolve = true
        pollingTask?.cancel()
        pollingTask = nil
        onEvent?(event)
    }

    private func shouldStopPolling(for error: any Error) -> Bool {
        guard let error = error as? SdkError else {
            return false
        }
        switch error {
        case .message(let message):
            return message != .serverError
        case .sdkNotReady, .decoding, .invalidResponse:
            return false
        case .apiReturnedError, .javaScriptException, .unexpected:
            return true
        }
    }
}
