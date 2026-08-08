import WalletCore

public enum SoftwareSubmission<Result: MfaProtectedActionResult>: Sendable {
    case requiresMfa(Result)
    case resolved(ActionSubmissionResult<Result>)
}

@MainActor
public struct SoftwareOperation<Result: MfaProtectedActionResult> {
    public let submit: (EnclaveToken) async -> SoftwareSubmission<Result>

    public static func single(
        _ submit: @escaping (EnclaveToken) async throws -> Result
    ) -> Self {
        Self { enclaveToken in
            do {
                let result = try await submit(enclaveToken)
                if let error = result.protectedActionError {
                    return .resolved(
                        .notCommitted(SdkError.apiReturnedError(error: error, context: result))
                    )
                }
                if result.mfaRequestHash != nil {
                    return .requiresMfa(result)
                }
                return .resolved(
                    .committed(
                        ActionSubmissionReceipt(
                            payload: result,
                            activityIds: result.protectedActionActivityIds
                        )
                    )
                )
            } catch {
                return .resolved(actionSubmissionFailure(for: error))
            }
        }
    }

    public static func custom(
        _ submit: @escaping (EnclaveToken) async -> SoftwareSubmission<Result>
    ) -> Self {
        Self(submit: submit)
    }

    private init(
        submit: @escaping (EnclaveToken) async -> SoftwareSubmission<Result>
    ) {
        self.submit = submit
    }

    public func confirmMfa(
        result: Result,
        accountId: String,
        request: ApiMfaRequest
    ) async -> ActionSubmissionResult<Result> {
        do {
            try await result.handleMfaConfirmation(accountId: accountId, request: request)
            return .committed(
                ActionSubmissionReceipt(
                    payload: result,
                    activityIds: result.protectedActionActivityIds,
                    externalMessageHashes: [request.txHash]
                )
            )
        } catch {
            return actionSubmissionFailure(for: error)
        }
    }
}
