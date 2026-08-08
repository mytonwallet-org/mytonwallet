import Foundation
import Testing
@testable import UIDapp
import WalletCore

@Suite("Dapp Send Submission")
struct DappSendSubmitResultTests {
    @Test
    func `MFA handoff waits for confirmation hook`() async throws {
        let spy = ConfirmationSpy()
        let result = try makeResult(confirmMfaHandoff: { promiseId, mfaRequestHash in
            await spy.record(promiseId: promiseId, mfaRequestHash: mfaRequestHash)
        })

        #expect(await spy.calls.isEmpty)

        try await result.handleMfaConfirmation(
            accountId: "account",
            request: try makeConfirmedRequest()
        )

        #expect(
            await spy.calls == [
                .init(promiseId: "promise", mfaRequestHash: "mfa-request"),
            ]
        )
    }

    @Test
    func `post-confirmation handoff failure does not become retryable`() async throws {
        let result = try makeResult { _, _ in
            throw TestError.failed
        }

        try await result.handleMfaConfirmation(
            accountId: "account",
            request: try makeConfirmedRequest()
        )
    }

    private func makeResult(
        confirmMfaHandoff: @escaping DappSendSubmitResult.ConfirmMfaHandoff
    ) throws -> DappSendSubmitResult {
        let sdkResult = try JSONDecoder().decode(
            ApiSignDappTransfersResult.self,
            from: Data(#"{"mfaRequestHash":"mfa-request"}"#.utf8)
        )
        return DappSendSubmitResult(
            promiseId: "promise",
            result: sdkResult,
            confirmMfaHandoff: confirmMfaHandoff
        )
    }

    private func makeConfirmedRequest() throws -> ApiMfaRequest {
        try JSONDecoder().decode(
            ApiMfaRequest.self,
            from: Data(
                #"{"payload":"payload","signature":"signature","isConfirmed":true,"txHash":"transaction"}"#.utf8
            )
        )
    }
}

private actor ConfirmationSpy {
    struct Call: Equatable {
        let promiseId: String
        let mfaRequestHash: String
    }

    private(set) var calls: [Call] = []

    func record(promiseId: String, mfaRequestHash: String) {
        calls.append(.init(promiseId: promiseId, mfaRequestHash: mfaRequestHash))
    }
}

private enum TestError: Error {
    case failed
}
