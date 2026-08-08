import Testing
import WalletContext
@testable import WalletCore

@Suite("Action Submission Result")
struct ActionSubmissionResultTests {
    @Test
    func `receipt removes empty and duplicate activity ids`() {
        let receipt = ActionSubmissionReceipt<Int>(
            payload: 42,
            activityIds: ["first", "", "first", "second"],
            externalMessageHashes: ["hash-1", "", "hash-1", "hash-2"]
        )

        #expect(receipt.payload == 42)
        #expect(receipt.activityIds == ["first", "second"])
        #expect(receipt.externalMessageHashes == ["hash-1", "hash-2"])
    }

    @Test
    func `receipt merge keeps newest payload and all activity ids`() {
        let first = ActionSubmissionReceipt(
            payload: 1,
            activityIds: ["first"],
            externalMessageHashes: ["hash-1"]
        )
        let second = ActionSubmissionReceipt(
            payload: 2,
            activityIds: ["second", "first"],
            externalMessageHashes: ["hash-2", "hash-1"]
        )

        let merged = first.merging(second)

        #expect(merged.payload == 2)
        #expect(merged.activityIds == ["first", "second"])
        #expect(merged.externalMessageHashes == ["hash-1", "hash-2"])
    }

    @Test
    func `only definitely not committed result permits retry`() {
        let receipt = ActionSubmissionReceipt<Int>(payload: 42)
        let remainingWork = ActionRemainingWork(
            completedUnitCount: 1,
            totalUnitCount: 2,
            error: TestError.failed
        )

        #expect(!ActionSubmissionResult<Int>.notCommitted(TestError.failed).preventsRetry)
        #expect(ActionSubmissionResult.committed(receipt).preventsRetry)
        #expect(
            ActionSubmissionResult<Int>.partiallyCommitted(
                receipt: receipt,
                remainingWork: remainingWork
            ).preventsRetry
        )
        #expect(
            ActionSubmissionResult<Int>.indeterminate(
                error: TestError.failed,
                receipt: nil
            ).preventsRetry
        )
    }

    @Test
    func `explicit API failures are known not committed`() {
        let error = SdkError.apiReturnedError(error: "Rejected", data: nil)

        #expect(actionSubmissionErrorDisposition(for: error) == .notCommitted)
        #expect(
            actionSubmissionErrorDisposition(
                for: DisplayError(text: "Rejected")
            ) == .notCommitted
        )
    }

    @Test
    func `transport and decoding failures are indeterminate`() {
        let decoding = SdkError.decoding(
            SdkDecodingError(
                methodName: "submit",
                responseType: "Result",
                underlyingError: TestError.failed,
                data: nil
            )
        )

        #expect(actionSubmissionErrorDisposition(for: decoding) == .indeterminate)
        #expect(actionSubmissionErrorDisposition(for: TestError.failed) == .indeterminate)
    }

    @Test
    func `retry failure cannot erase a partial commit`() {
        var accumulator = ActionSubmissionStateAccumulator<Int>()
        _ = accumulator.record(partialResult(completed: 1, activityIds: ["first"]))

        let result = accumulator.record(.notCommitted(TestError.retryFailed))

        guard case .partiallyCommitted(let receipt, let remainingWork) = result else {
            Issue.record("Expected the existing partial commit")
            return
        }
        #expect(receipt.activityIds == ["first"])
        #expect(remainingWork.completedUnitCount == 1)
        #expect(remainingWork.totalUnitCount == 3)
        #expect(remainingWork.error is TestError)
    }

    @Test
    func `commit after partial merges receipts`() {
        var accumulator = ActionSubmissionStateAccumulator<Int>()
        _ = accumulator.record(partialResult(completed: 1, activityIds: ["first"]))

        let result = accumulator.record(
            .committed(ActionSubmissionReceipt(payload: 42, activityIds: ["second"]))
        )

        guard case .committed(let receipt) = result else {
            Issue.record("Expected a committed result")
            return
        }
        #expect(receipt.payload == 42)
        #expect(receipt.activityIds == ["first", "second"])
    }

    @Test
    func `indeterminate retry retains partial receipt`() {
        var accumulator = ActionSubmissionStateAccumulator<Int>()
        _ = accumulator.record(partialResult(completed: 1, activityIds: ["first"]))

        let result = accumulator.record(
            .indeterminate(error: TestError.unknown, receipt: nil)
        )

        guard case .indeterminate(_, let receipt) = result else {
            Issue.record("Expected an indeterminate result")
            return
        }
        #expect(receipt?.activityIds == ["first"])
    }

    @Test
    func `partial progress cannot move backwards`() {
        var accumulator = ActionSubmissionStateAccumulator<Int>()
        _ = accumulator.record(partialResult(completed: 2, activityIds: ["first", "second"]))

        let result = accumulator.record(partialResult(completed: 1, activityIds: ["first"]))

        guard case .indeterminate(let error, let receipt) = result else {
            Issue.record("Expected an indeterminate result")
            return
        }
        #expect(error is ActionSubmissionAccumulationError)
        #expect(receipt?.activityIds == ["first", "second"])
    }

    private func partialResult(
        completed: Int,
        activityIds: [String]
    ) -> ActionSubmissionResult<Int> {
        .partiallyCommitted(
            receipt: ActionSubmissionReceipt(activityIds: activityIds),
            remainingWork: ActionRemainingWork(
                completedUnitCount: completed,
                totalUnitCount: 3,
                error: TestError.failed
            )
        )
    }
}

private enum TestError: Error {
    case failed
    case retryFailed
    case unknown
}
