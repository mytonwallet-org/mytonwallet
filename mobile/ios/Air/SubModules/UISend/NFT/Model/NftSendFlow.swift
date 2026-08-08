import Foundation
import ProtectedAction
import WalletContext
import WalletCore

private let nftSendFlowLog = Log("NftSendFlow")

public enum NftSendMode: Equatable, Hashable, Sendable {
    case send
    case burn
}

struct NftSendDraftRequest: Equatable, Hashable, Sendable {
    let accountId: String
    let address: String
    let chain: ApiChain
    let nfts: [ApiNft]
    let comment: String?
    let mode: NftSendMode
}

struct NftSendSubmission: Sendable {
    let accountId: String
    let chain: ApiChain
    let nfts: [ApiNft]
    let comment: String?
    let mode: NftSendMode
    let resolvedAddress: String
    let totalRealFee: BigInt?
}

struct NftSendFlow: Sendable {
    private let api: NftSendApiClient

    init(api: NftSendApiClient = .live) {
        self.api = api
    }

    func validateDraft(
        _ request: NftSendDraftRequest
    ) async throws -> NftSendValidatedDraft {
        guard !request.nfts.isEmpty else {
            throw DisplayError(text: lang("No NFT selected"))
        }
        let isBurn = request.mode == .burn
        if request.address.isEmpty && !isBurn {
            throw DisplayError(text: lang("Address not resolved"))
        }
        let draft = try await api.checkDraft(
            request.chain,
            .init(
                accountId: request.accountId,
                nfts: request.nfts,
                toAddress: request.address,
                comment: request.comment,
                isNftBurn: isBurn
            )
        )
        let validatedDraft = NftSendValidatedDraft(apiDraft: draft)
        try validateSendDraftError(draft.error)
        return validatedDraft
    }

    func submit(
        _ submission: NftSendSubmission,
        enclaveToken: EnclaveToken?
    ) async throws -> SendSubmissionResult {
        let result = try await api.submit(.init(
            chain: submission.chain,
            accountId: submission.accountId,
            enclaveToken: enclaveToken,
            nfts: submission.nfts,
            toAddress: submission.resolvedAddress,
            comment: submission.comment,
            totalRealFee: submission.totalRealFee ?? 0,
            isNftBurn: submission.mode == .burn
        ))
        if let error = result.error {
            throw SdkError.apiReturnedError(
                error: error,
                context: nil
            )
        }
        return SendSubmissionResult(
            activityIds: result.activityIds ?? [],
            mfaRequestHash: result.mfaRequestHash
        )
    }

    @MainActor
    func ledgerOperation(
        _ submission: NftSendSubmission
    ) async throws -> HardwareOperation<SendSubmissionResult> {
        guard !submission.nfts.isEmpty else {
            throw DisplayError(text: lang("No NFT selected"))
        }
        let totalUnitCount = submission.nfts.count
        let realFeePerNft =
            (submission.totalRealFee ?? 0) / BigInt(totalUnitCount)
        var pendingNfts = submission.nfts
        var activityIds: [String] = []
        return .custom { operationContext in
            while let nft = pendingNfts.first {
                let completedUnitCount =
                    totalUnitCount - pendingNfts.count
                operationContext.updateProgress(
                    completedUnitCount: completedUnitCount,
                    totalUnitCount: totalUnitCount
                )
                do {
                    let result = try await api.submit(.init(
                        chain: submission.chain,
                        accountId: submission.accountId,
                        enclaveToken: nil,
                        nfts: [nft],
                        toAddress: submission.resolvedAddress,
                        comment: submission.comment,
                        totalRealFee: realFeePerNft,
                        isNftBurn: submission.mode == .burn
                    ))
                    if let error = result.error {
                        return partialOrNotCommitted(
                            error: SdkError.apiReturnedError(
                                error: error,
                                context: result
                            ),
                            completedUnitCount: completedUnitCount,
                            totalUnitCount: totalUnitCount,
                            activityIds: activityIds
                        )
                    }
                    if result.mfaRequestHash != nil {
                        return partialOrNotCommitted(
                            error: NftSendLedgerError.unexpectedMfa,
                            completedUnitCount: completedUnitCount,
                            totalUnitCount: totalUnitCount,
                            activityIds: activityIds
                        )
                    }
                    let submittedIds = result.activityIds ?? []
                    if submittedIds.isEmpty {
                        nftSendFlowLog.fault(
                            "Ledger NFT submission succeeded without activity IDs"
                        )
                        return .indeterminate(
                            error: NftSendLedgerError.missingActivityIds,
                            receipt: activityIds.isEmpty
                                ? nil
                                : ActionSubmissionReceipt(
                                    activityIds: activityIds
                                )
                        )
                    }
                    activityIds.append(contentsOf: submittedIds)
                    pendingNfts.removeFirst()
                } catch {
                    return .indeterminate(
                        error: error,
                        receipt: activityIds.isEmpty
                            ? nil
                            : ActionSubmissionReceipt(
                                activityIds: activityIds
                            )
                    )
                }
            }
            return .committed(ActionSubmissionReceipt(
                activityIds: activityIds
            ))
        }
    }
}

private enum NftSendLedgerError: Error, LocalizedError {
    case missingActivityIds
    case unexpectedMfa

    var errorDescription: String? {
        lang("Unexpected error")
    }
}

private func partialOrNotCommitted<Result: Sendable>(
    error: any Error,
    completedUnitCount: Int,
    totalUnitCount: Int,
    activityIds: [String]
) -> ActionSubmissionResult<Result> {
    guard completedUnitCount > 0 else {
        return .notCommitted(error)
    }
    return .partiallyCommitted(
        receipt: ActionSubmissionReceipt(
            activityIds: activityIds
        ),
        remainingWork: ActionRemainingWork(
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            error: error
        )
    )
}
