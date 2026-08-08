import Foundation
import ProtectedAction
import WalletCore

enum ActivityWaitResult {
    case activity(ApiActivity)
    case timedOut
    case cancelled
}

@MainActor
final class ActivityWaiter: WalletCoreData.EventsObserver, @unchecked Sendable {
    private struct Candidate {
        let activity: ApiActivity
        let observationSequence: Int
    }

    private let accountId: String
    private let sources: Set<ActivitySource>
    private let timeout: Duration
    private var candidates: [Candidate] = []
    private var nextObservationSequence = 0
    private var submissionWatermark: Int?
    private var matcher: ((Candidate) -> Bool)?
    private var continuation: CheckedContinuation<ActivityWaitResult, Never>?
    private var finishedResult: ActivityWaitResult?
    private var timeoutTask: Task<Void, Never>?

    init(
        accountId: String,
        sources: Set<ActivitySource>,
        timeout: Duration
    ) {
        self.accountId = accountId
        self.sources = sources
        self.timeout = timeout
        WalletCoreData.addImmediately(eventObserver: self)
    }

    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .newLocalActivity(let update) where sources.contains(.local):
            receive(accountId: update.accountId, activities: update.activities)
        case .newActivities(let update) where sources.contains(.pendingOrConfirmed):
            receive(
                accountId: update.accountId,
                activities: (update.pendingActivities ?? []) + update.activities
            )
        default:
            break
        }
    }

    func wait<Result: MfaProtectedActionResult>(
        receipt: ActionSubmissionReceipt<Result>,
        matches: @escaping (ApiActivity, ActionSubmissionReceipt<Result>) -> Bool,
        fallbackMatches: ((ApiActivity, ActionSubmissionReceipt<Result>) -> Bool)? = nil
    ) async -> ActivityWaitResult {
        if let finishedResult {
            return finishedResult
        }
        let submissionWatermark = submissionWatermark
        let matcher: (Candidate) -> Bool = { candidate in
            if matches(candidate.activity, receipt) {
                return true
            }
            guard let fallbackMatches,
                  let submissionWatermark,
                  candidate.observationSequence >= submissionWatermark else {
                return false
            }
            return fallbackMatches(candidate.activity, receipt)
        }
        self.matcher = matcher
        if let candidate = candidates.first(where: matcher) {
            finish(with: .activity(candidate.activity))
            return finishedResult ?? .activity(candidate.activity)
        }
        startTimeout()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let finishedResult {
                    continuation.resume(returning: finishedResult)
                } else {
                    self.continuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    func cancel() {
        finish(with: .cancelled)
    }

    func markSubmissionStarted() {
        // MFA and Ledger retries advance the watermark without discarding earlier exact matches.
        submissionWatermark = nextObservationSequence
    }

    func receive(accountId: String, activities: [ApiActivity]) {
        guard finishedResult == nil, accountId == self.accountId else { return }
        let newCandidates = activities.map { activity in
            let candidate = Candidate(
                activity: activity,
                observationSequence: nextObservationSequence
            )
            nextObservationSequence += 1
            return candidate
        }
        candidates.append(contentsOf: newCandidates)
        guard let matcher, let candidate = newCandidates.first(where: matcher) else { return }
        finish(with: .activity(candidate.activity))
    }

    private func startTimeout() {
        guard timeoutTask == nil else { return }
        timeoutTask = Task { [weak self, timeout] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            self?.finish(with: .timedOut)
        }
    }

    private func finish(with result: ActivityWaitResult) {
        guard finishedResult == nil else { return }
        finishedResult = result
        timeoutTask?.cancel()
        timeoutTask = nil
        WalletCoreData.remove(observer: self)
        continuation?.resume(returning: result)
        continuation = nil
        candidates.removeAll()
        matcher = nil
    }
}
