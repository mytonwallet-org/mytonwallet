import ProtectedAction
import Testing
@testable import UIAssets
import WalletCore

@Suite("Renew Domain Submission")
struct RenewDomainSubmissionTests {
    @Test
    func `empty response is indeterminate`() {
        let submission = resolveRenewDomainSubmission([])

        guard case .resolved(.indeterminate(let error, let receipt)) = submission else {
            Issue.record("Expected an indeterminate result")
            return
        }
        #expect(error is DomainSubmissionError)
        #expect(receipt == nil)
    }

    @Test
    func `activity response is committed`() {
        let submission = resolveRenewDomainSubmission([
            ApiMfaProtectedResult(activityIds: ["activity"]),
        ])

        guard case .resolved(.committed(let receipt)) = submission else {
            Issue.record("Expected a committed result")
            return
        }
        #expect(receipt.activityIds == ["activity"])
    }
}
