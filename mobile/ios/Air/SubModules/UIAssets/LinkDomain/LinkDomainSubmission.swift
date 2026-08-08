import Foundation
import ProtectedAction
import WalletContext
import WalletCore

private let linkDomainSubmissionLog = Log("LinkDomain")

func submitLinkDomain(
    snapshot: LinkDomainConfirmationSnapshot,
    enclaveToken: EnclaveToken?
) async throws -> ApiMfaProtectedResult {
    let result = try await Api.submitDnsChangeWallet(
        accountId: snapshot.account.id,
        enclaveToken: enclaveToken,
        nft: snapshot.nft,
        address: snapshot.destinationAddress,
        realFee: snapshot.realFee
    )
    if let error = result.error {
        throw SdkError.apiReturnedError(error: error, context: result)
    }
    if result.mfaRequestHash == nil, result.activityId == nil {
        linkDomainSubmissionLog.fault(
            "Domain linking succeeded without an activity ID"
        )
    }
    return ApiMfaProtectedResult(
        activityId: result.activityId,
        mfaRequestHash: result.mfaRequestHash
    )
}

@MainActor
func makeLinkDomainLedgerOperation(
    snapshot: LinkDomainConfirmationSnapshot
) -> HardwareOperation<ApiMfaProtectedResult> {
    .single {
        let result = try await Api.submitDnsChangeWallet(
            accountId: snapshot.account.id,
            enclaveToken: nil,
            nft: snapshot.nft,
            address: snapshot.destinationAddress,
            realFee: snapshot.realFee
        )
        if let error = result.error {
            throw SdkError.apiReturnedError(error: error, context: result)
        }
        if result.mfaRequestHash != nil {
            throw DisplayError(text: lang("Unexpected error"))
        }
        if result.activityId == nil {
            linkDomainSubmissionLog.fault(
                "Ledger domain linking succeeded without an activity ID"
            )
        }
        return ActionSubmissionReceipt(
            activityIds: [result.activityId].compactMap { $0 }
        )
    }
}
