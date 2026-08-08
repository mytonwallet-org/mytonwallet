import Foundation
import ProtectedAction
import WalletContext
import WalletCore

private let renewDomainSubmissionLog = Log("RenewDomain")

func submitRenewDomains(
    snapshot: RenewDomainConfirmationSnapshot,
    enclaveToken: EnclaveToken?
) async -> SoftwareSubmission<ApiMfaProtectedResult> {
    guard !snapshot.nfts.isEmpty else {
        renewDomainSubmissionLog.fault(
            "Attempted to submit an empty domain-renewal snapshot"
        )
        return .resolved(.notCommitted(DomainSubmissionError.emptySnapshot))
    }
    do {
        let result = try await Api.submitDnsRenewal(
            accountId: snapshot.account.id,
            enclaveToken: enclaveToken,
            nfts: snapshot.nfts,
            realFee: snapshot.realFee
        )
        return resolveRenewDomainSubmission(result)
    } catch {
        return .resolved(actionSubmissionFailure(for: error))
    }
}

func resolveRenewDomainSubmission(
    _ result: [ApiMfaProtectedResult]
) -> SoftwareSubmission<ApiMfaProtectedResult> {
    guard !result.isEmpty else {
        renewDomainSubmissionLog.fault(
            "Domain renewal returned no per-transaction results for a nonempty snapshot"
        )
        return .resolved(
            .indeterminate(
                error: DomainSubmissionError.emptyResult,
                receipt: nil
            )
        )
    }
    var activityIds: [String] = []
    var failures: [any Error] = []
    for entry in result {
        if let error = entry.error {
            failures.append(SdkError.apiReturnedError(error: error, context: result))
        } else if let mfaRequestHash = entry.mfaRequestHash {
            if activityIds.isEmpty {
                return .requiresMfa(
                    ApiMfaProtectedResult(mfaRequestHash: mfaRequestHash)
                )
            }
            failures.append(DomainSubmissionError.mixedMfaAndCommit)
        } else {
            let submittedActivityIds = entry.activityIds ?? []
            if submittedActivityIds.isEmpty {
                renewDomainSubmissionLog.fault(
                    "Domain renewal transaction succeeded without activity IDs"
                )
            }
            activityIds.append(contentsOf: submittedActivityIds)
        }
    }
    guard let error = failures.first else {
        let payload = ApiMfaProtectedResult(activityIds: activityIds)
        return .resolved(
            .committed(
                ActionSubmissionReceipt(payload: payload, activityIds: activityIds)
            )
        )
    }
    let completedUnitCount = result.count - failures.count
    guard completedUnitCount > 0 else {
        return .resolved(.notCommitted(error))
    }
    return .resolved(
        .partiallyCommitted(
            receipt: ActionSubmissionReceipt(
                payload: ApiMfaProtectedResult(activityIds: activityIds),
                activityIds: activityIds
            ),
            remainingWork: ActionRemainingWork(
                completedUnitCount: completedUnitCount,
                totalUnitCount: result.count,
                error: error
            )
        )
    )
}

@MainActor
func makeRenewDomainsLedgerOperation(
    snapshot: RenewDomainConfirmationSnapshot
) -> HardwareOperation<ApiMfaProtectedResult> {
    let totalUnitCount = snapshot.nfts.count
    guard totalUnitCount > 0 else {
        renewDomainSubmissionLog.fault(
            "Attempted to create a Ledger operation for an empty domain-renewal snapshot"
        )
        return .custom { _ in
            .notCommitted(DomainSubmissionError.emptySnapshot)
        }
    }
    let realFeePerNft = snapshot.realFee / BigInt(totalUnitCount)
    var pendingNfts = snapshot.nfts
    var activityIds: [String] = []
    return .custom { context in
        while let nft = pendingNfts.first {
            let completedUnitCount = totalUnitCount - pendingNfts.count
            context.updateProgress(
                completedUnitCount: completedUnitCount,
                totalUnitCount: totalUnitCount
            )
            do {
                let result = try await Api.submitDnsRenewal(
                    accountId: snapshot.account.id,
                    enclaveToken: nil,
                    nfts: [nft],
                    realFee: realFeePerNft
                )
                guard !result.isEmpty else {
                    renewDomainSubmissionLog.fault(
                        "Ledger domain renewal returned no transaction result"
                    )
                    return .indeterminate(
                        error: DomainSubmissionError.emptyResult,
                        receipt: activityIds.isEmpty
                            ? nil
                            : ActionSubmissionReceipt(activityIds: activityIds)
                    )
                }
                guard result.count == 1, let entry = result.first else {
                    return .indeterminate(
                        error: DomainSubmissionError.resultCountMismatch,
                        receipt: activityIds.isEmpty
                            ? nil
                            : ActionSubmissionReceipt(activityIds: activityIds)
                    )
                }
                if let error = entry.error {
                    return domainPartialOrNotCommitted(
                        error: SdkError.apiReturnedError(error: error, context: result),
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        activityIds: activityIds
                    )
                }
                if entry.mfaRequestHash != nil {
                    return domainPartialOrNotCommitted(
                        error: DomainSubmissionError.unexpectedLedgerMfa,
                        completedUnitCount: completedUnitCount,
                        totalUnitCount: totalUnitCount,
                        activityIds: activityIds
                    )
                }
                let submittedActivityIds = entry.activityIds ?? []
                if submittedActivityIds.isEmpty {
                    renewDomainSubmissionLog.fault(
                        "Ledger domain renewal succeeded without activity IDs"
                    )
                }
                activityIds.append(contentsOf: submittedActivityIds)
                pendingNfts.removeFirst()
            } catch {
                return .indeterminate(
                    error: error,
                    receipt: activityIds.isEmpty
                        ? nil
                        : ActionSubmissionReceipt(activityIds: activityIds)
                )
            }
        }
        return .committed(ActionSubmissionReceipt(activityIds: activityIds))
    }
}

private func domainPartialOrNotCommitted<Result: Sendable>(
    error: any Error,
    completedUnitCount: Int,
    totalUnitCount: Int,
    activityIds: [String]
) -> ActionSubmissionResult<Result> {
    guard completedUnitCount > 0 else {
        return .notCommitted(error)
    }
    return .partiallyCommitted(
        receipt: ActionSubmissionReceipt(activityIds: activityIds),
        remainingWork: ActionRemainingWork(
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            error: error
        )
    )
}

enum DomainSubmissionError: Error, LocalizedError {
    case emptySnapshot
    case emptyResult
    case mixedMfaAndCommit
    case resultCountMismatch
    case unexpectedLedgerMfa

    var errorDescription: String? {
        lang("Unexpected error")
    }
}
