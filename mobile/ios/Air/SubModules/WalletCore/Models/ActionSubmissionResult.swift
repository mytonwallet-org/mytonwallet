import Foundation
import WalletContext

public struct ActionSubmissionReceipt<Payload: Sendable>: Sendable {
    public let payload: Payload?
    public let activityIds: [String]
    public let externalMessageHashes: [String]

    public init(
        payload: Payload? = nil,
        activityIds: [String] = [],
        externalMessageHashes: [String] = []
    ) {
        self.payload = payload
        self.activityIds = activityIds.uniqued()
        self.externalMessageHashes = externalMessageHashes.uniqued()
    }

    public func replacingPayload<NewPayload: Sendable>(
        _ payload: NewPayload?
    ) -> ActionSubmissionReceipt<NewPayload> {
        ActionSubmissionReceipt<NewPayload>(
            payload: payload,
            activityIds: activityIds,
            externalMessageHashes: externalMessageHashes
        )
    }

    public func merging(
        _ newerReceipt: ActionSubmissionReceipt<Payload>
    ) -> ActionSubmissionReceipt<Payload> {
        ActionSubmissionReceipt(
            payload: newerReceipt.payload ?? payload,
            activityIds: activityIds + newerReceipt.activityIds,
            externalMessageHashes: externalMessageHashes + newerReceipt.externalMessageHashes
        )
    }

    public func correlates(with activity: ApiActivity) -> Bool {
        if activityIds.contains(activity.id)
            || externalMessageHashes.contains(activity.id) {
            return true
        }
        guard let externalMessageHash = activity.externalMsgHashNorm else {
            return false
        }
        return activityIds.contains(externalMessageHash)
            || externalMessageHashes.contains(externalMessageHash)
    }
}

public struct ActionRemainingWork: Sendable {
    public let completedUnitCount: Int
    public let totalUnitCount: Int
    public let error: any Error

    public init(
        completedUnitCount: Int,
        totalUnitCount: Int,
        error: any Error
    ) {
        precondition(totalUnitCount > 0)
        precondition(completedUnitCount > 0 && completedUnitCount < totalUnitCount)
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.error = error
    }

    public var remainingUnitCount: Int {
        totalUnitCount - completedUnitCount
    }
}

public enum ActionSubmissionResult<Payload: Sendable>: Sendable {
    case notCommitted(any Error)
    case committed(ActionSubmissionReceipt<Payload>)
    case partiallyCommitted(
        receipt: ActionSubmissionReceipt<Payload>,
        remainingWork: ActionRemainingWork
    )
    case indeterminate(
        error: any Error,
        receipt: ActionSubmissionReceipt<Payload>?
    )

    public var receipt: ActionSubmissionReceipt<Payload>? {
        switch self {
        case .notCommitted:
            nil
        case .committed(let receipt), .partiallyCommitted(let receipt, _):
            receipt
        case .indeterminate(_, let receipt):
            receipt
        }
    }

    public var preventsRetry: Bool {
        switch self {
        case .notCommitted:
            false
        case .committed, .partiallyCommitted, .indeterminate:
            true
        }
    }
}

public struct ActionSubmissionStateAccumulator<Payload: Sendable>: Sendable {
    private var partialCommit: (
        receipt: ActionSubmissionReceipt<Payload>,
        remainingWork: ActionRemainingWork
    )?

    public init() {}

    public mutating func record(
        _ result: ActionSubmissionResult<Payload>
    ) -> ActionSubmissionResult<Payload> {
        switch result {
        case .notCommitted(let error):
            guard let partialCommit else { return result }
            return .partiallyCommitted(
                receipt: partialCommit.receipt,
                remainingWork: ActionRemainingWork(
                    completedUnitCount: partialCommit.remainingWork.completedUnitCount,
                    totalUnitCount: partialCommit.remainingWork.totalUnitCount,
                    error: error
                )
            )

        case .committed(let receipt):
            guard let partialCommit else { return result }
            self.partialCommit = nil
            return .committed(partialCommit.receipt.merging(receipt))

        case .partiallyCommitted(let receipt, let remainingWork):
            guard let previous = partialCommit else {
                partialCommit = (receipt, remainingWork)
                return result
            }
            let mergedReceipt = previous.receipt.merging(receipt)
            guard remainingWork.totalUnitCount == previous.remainingWork.totalUnitCount,
                  remainingWork.completedUnitCount >= previous.remainingWork.completedUnitCount else {
                self.partialCommit = nil
                return .indeterminate(
                    error: ActionSubmissionAccumulationError.invalidPartialProgress(
                        previousCompletedUnitCount: previous.remainingWork.completedUnitCount,
                        previousTotalUnitCount: previous.remainingWork.totalUnitCount,
                        newCompletedUnitCount: remainingWork.completedUnitCount,
                        newTotalUnitCount: remainingWork.totalUnitCount
                    ),
                    receipt: mergedReceipt
                )
            }
            partialCommit = (mergedReceipt, remainingWork)
            return .partiallyCommitted(
                receipt: mergedReceipt,
                remainingWork: remainingWork
            )

        case .indeterminate(let error, let receipt):
            guard let partialCommit else { return result }
            self.partialCommit = nil
            return .indeterminate(
                error: error,
                receipt: receipt.map(partialCommit.receipt.merging) ?? partialCommit.receipt
            )
        }
    }
}

public enum ActionSubmissionAccumulationError: Error, LocalizedError, Sendable, Equatable {
    case invalidPartialProgress(
        previousCompletedUnitCount: Int,
        previousTotalUnitCount: Int,
        newCompletedUnitCount: Int,
        newTotalUnitCount: Int
    )

    public var errorDescription: String? {
        lang("Unexpected error")
    }
}

public enum ActionSubmissionErrorDisposition: Sendable, Equatable {
    case notCommitted
    case indeterminate
}

public func actionSubmissionErrorDisposition(
    for error: any Error
) -> ActionSubmissionErrorDisposition {
    if error is DisplayError {
        return .notCommitted
    }
    guard let sdkError = error as? SdkError else {
        return .indeterminate
    }
    switch sdkError {
    case .message, .apiReturnedError:
        return .notCommitted
    case .sdkNotReady, .javaScriptException, .decoding, .invalidResponse, .unexpected:
        return .indeterminate
    }
}

public func actionSubmissionFailure<Payload: Sendable>(
    for error: any Error,
    indeterminateReceipt: ActionSubmissionReceipt<Payload>? = nil
) -> ActionSubmissionResult<Payload> {
    switch actionSubmissionErrorDisposition(for: error) {
    case .notCommitted:
        .notCommitted(error)
    case .indeterminate:
        .indeterminate(error: error, receipt: indeterminateReceipt)
    }
}

private extension Sequence where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
