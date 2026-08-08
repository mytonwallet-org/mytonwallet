import Foundation
import Testing
@testable import UIProtectedAction
import WalletCore

@Suite("MFA Confirmation Model")
@MainActor
struct MfaConfirmationModelTests {
    @Test
    func `confirmed request is emitted`() async throws {
        let request = try makeRequest(isConfirmed: true)
        let model = MfaConfirmationModel(
            requestHash: "request",
            pollInterval: .milliseconds(1),
            fetchRequest: { hash in
                #expect(hash == "request")
                return request
            }
        )

        let event = await nextEvent(from: model)

        guard case .confirmed(let confirmedRequest) = event else {
            Issue.record("Expected a confirmed request")
            return
        }
        #expect(confirmedRequest.txHash == request.txHash)
    }

    @Test
    func `transient polling failure is retried`() async throws {
        let request = try makeRequest(isConfirmed: true)
        var attemptCount = 0
        let model = MfaConfirmationModel(
            requestHash: "request",
            pollInterval: .milliseconds(1),
            fetchRequest: { _ in
                attemptCount += 1
                if attemptCount == 1 {
                    throw TestError.transient
                }
                return request
            }
        )

        let event = await nextEvent(from: model)

        guard case .confirmed = event else {
            Issue.record("Expected a confirmed request after retry")
            return
        }
        #expect(attemptCount == 2)
    }

    @Test
    func `terminal SDK failure is emitted`() async {
        let model = MfaConfirmationModel(
            requestHash: "request",
            pollInterval: .milliseconds(1),
            fetchRequest: { _ in
                throw SdkError.apiReturnedError(error: "Rejected", data: nil)
            }
        )

        let event = await nextEvent(from: model)

        guard case .failed(let error) = event else {
            Issue.record("Expected a terminal failure")
            return
        }
        #expect((error as? SdkError)?.backendMessage == "Rejected")
    }

    private func nextEvent(
        from model: MfaConfirmationModel
    ) async -> MfaConfirmationModelEvent {
        await withCheckedContinuation { continuation in
            model.onEvent = { event in
                continuation.resume(returning: event)
            }
            model.start()
        }
    }

    private func makeRequest(isConfirmed: Bool) throws -> ApiMfaRequest {
        let json = """
        {
          "payload": "payload",
          "signature": "signature",
          "isConfirmed": \(isConfirmed),
          "txHash": "transaction"
        }
        """
        return try JSONDecoder().decode(ApiMfaRequest.self, from: Data(json.utf8))
    }
}

private enum TestError: Error {
    case transient
}
