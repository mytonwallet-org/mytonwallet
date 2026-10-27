import Foundation
import UIComponents
import WalletCore
import WalletContext

private let log = Log("SwapQuote")

/// Correlates native input, SDK stages, accepted results and the rendered button.
/// IDs are local to this screen; amounts, account IDs and wallet addresses are never logged.
@MainActor final class SwapQuoteDiagnostics {
    @TaskLocal static var attempt: Attempt?

    let session = String(UUID().uuidString.prefix(8))
    private var requests: [SwapEstimateRequest] = []
    private var requestNumber = 0
    private var attemptNumber = 0
    private var renderedConfiguration: DraftButtonConfiguration?

    func screen(_ name: String) {
        log.info("session=\(session, .public) screen=\(name, .public)")
    }

    private func identify(_ request: SwapEstimateRequest?) -> Int {
        guard let request else { return 0 }
        if let index = requests.firstIndex(of: request) {
            return index + 1
        }
        requests.append(request)
        return requests.count
    }

    func input(_ request: SwapEstimateRequest?, source: String) {
        let id = identify(request)
        requestNumber = id
        let mode = request.map { $0.side == .selling ? "exactIn" : "exactOut" } ?? "none"
        let isMax: Bool
        if case .max = request?.amount { isMax = true } else { isMax = false }
        log.info("session=\(session, .public) request=\(id) input=\(source, .public) present=\(request != nil) mode=\(mode, .public) max=\(isMax)")
    }

    func load(
        _ request: SwapEstimateRequest,
        operation: () async throws -> SwapEstimateUpdate,
        isCurrent: () -> Bool
    ) async throws -> SwapEstimateUpdate {
        let id = identify(request)
        if isCurrent() { requestNumber = id }
        attemptNumber += 1
        let attempt = Attempt(session: session, request: id, number: attemptNumber)
        let mode = request.side == .selling ? "exactIn" : "exactOut"
        let isMax: Bool
        if case .max = request.amount { isMax = true } else { isMax = false }
        attempt.record("start mode=\(mode) max=\(isMax) from=\(request.sellingSlug) to=\(request.buyingSlug)")
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            attempt.record("slow stage=\(attempt.stage)")
        }
        defer { watchdog.cancel() }
        return try await Self.$attempt.withValue(attempt) {
            do {
                let update = try await operation()
                attempt.record("returned current=\(isCurrent()) quote=\(update.hasQuote) issue=\(update.stateUpdate?.estimateIssue != nil)")
                return update
            } catch {
                attempt.record("threw current=\(isCurrent()) cancelled=\(error is CancellationError) type=\(String(reflecting: type(of: error)))")
                throw error
            }
        }
    }

    func state(_ request: SwapEstimateRequest?, event: String, state: SwapButtonState, loading: Bool) {
        let id = identify(request)
        requestNumber = id
        log.info("session=\(session, .public) request=\(id) event=\(event, .public) button=\(state.diagnosticName, .public) loading=\(loading)")
    }

    func rendered(_ configuration: DraftButtonConfiguration, button: WButton, renderedTitle: String? = nil) {
        let titleMatches: Bool
        switch configuration.title {
        case .text(let title): titleMatches = (renderedTitle ?? button.title(for: .normal)) == title
        case .attributed(let title, _): titleMatches = (renderedTitle ?? button.attributedTitle(for: .normal)?.string) == title.string
        }
        guard configuration != renderedConfiguration || button.showLoading != configuration.showLoading || !titleMatches else { return }
        renderedConfiguration = configuration
        log.info("session=\(session, .public) request=\(requestNumber) rendered requestedLoading=\(configuration.showLoading) actualLoading=\(button.showLoading) canContinue=\(configuration.isEnabled) interaction=\(button.isUserInteractionEnabled) titleMatches=\(titleMatches)")
    }

    static func step<T>(_ stage: String, operation: () async throws -> T) async rethrows -> T {
        guard let attempt else { return try await operation() }
        let previous = attempt.stage
        attempt.stage = stage
        attempt.record("begin stage=\(stage)")
        defer { attempt.stage = previous }
        do {
            let value = try await operation()
            attempt.record("end stage=\(stage)")
            return value
        } catch {
            attempt.record("failed stage=\(stage) type=\(String(reflecting: type(of: error)))")
            throw error
        }
    }

    static func received(_ response: ApiSwapEstimateResponse) {
        switch response {
        case .cex(let quote):
            attempt?.record("response route=cex belowMinimum=\(quote.fromAmount < quote.fromMin) zeroOutput=\(quote.toAmount == 0)")
        case .dex:
            attempt?.record("response route=dex")
        case .error:
            attempt?.record("response error")
        }
    }

    @MainActor final class Attempt {
        let session: String
        let request: Int
        let number: Int
        let started = ContinuousClock.now
        var stage = "load"

        init(session: String, request: Int, number: Int) {
            self.session = session
            self.request = request
            self.number = number
        }

        func record(_ event: String) {
            let elapsed = started.duration(to: .now).components
            let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
            log.info("session=\(session, .public) request=\(request) attempt=\(number) elapsedMs=\(milliseconds) \(event, .public)")
        }
    }
}

private extension SwapButtonState {
    var diagnosticName: String {
        switch self {
        case .submitting: "submitting"
        case .invalidPair: "invalidPair"
        case .emptyAmount: "emptyAmount"
        case .estimating: "estimating"
        case .waitingForEstimate: "waitingForEstimate"
        case .blocked(.minimumAmount): "minimum"
        case .blocked(.maximumAmount): "maximum"
        case .blocked: "blocked"
        case .authorizeDiesel: "authorizeDiesel"
        case .readyToContinue: "readyToContinue"
        case .readyToSwap: "readyToSwap"
        }
    }
}
