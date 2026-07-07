
import Foundation
import WalletCore
import WalletContext

/// Handles differences between send token and send nft flows
protocol SendFlow: Sendable {
    func validateDraft(context: SendDraftContext) async throws -> SendFlowDraftResult
    func submit(context: SendSubmitContext, password: String?, explainedFee: ExplainedTransferFee?) async throws -> SendFlowSubmitResult
    func ledgerPayload(context: SendSubmitContext, explainedFee: ExplainedTransferFee?) async throws -> SignData
}

public enum NftSendMode: Sendable {
    case send
    case burn
}

struct SendDraftContext: Sendable {
    let accountId: String
    let address: String
    let token: ApiToken
    let amount: BigInt?
    let payload: AnyTransferPayload?
    let stateInit: String?
    let nfts: [ApiNft]?
    let nftSendMode: NftSendMode?
}

struct SendSubmitContext: Sendable {
    let accountId: String
    let token: ApiToken
    let amount: BigInt?
    let payload: AnyTransferPayload?
    let stateInit: String?
    let nfts: [ApiNft]?
    let nftSendMode: NftSendMode?
    let transactionDraft: ApiCheckTransactionDraftResult?
    let diesel: ApiFetchEstimateDieselResult?
}

struct SendFlowDraftResult {
    let draftData: DraftData
    let explainedFee: ExplainedTransferFee?
    let requiresMemo: Bool
    
    static let noResult = SendFlowDraftResult(draftData: .init(status: .none), explainedFee: nil, requiresMemo: false)
}

struct SendFlowSubmitResult: Sendable {
    let mfaRequestHash: String?

    static let submitted = SendFlowSubmitResult(mfaRequestHash: nil)
}

extension SendFlowSubmitResult: MfaProtectedActionResult {}

private func isAddressDraftError(_ error: ApiAnyDisplayError?) -> Bool {
    guard let error else { return false }
    return [
        .domainNotResolved,
        .invalidAddress,
        .invalidAddressFormat,
        .invalidToAddress,
    ].contains(error)
}
// MARK: - Token

struct TokenSendFlow: SendFlow {
    
    private func makeTransferOptions(context: SendSubmitContext, password: String?, explainedFee: ExplainedTransferFee?) throws -> ApiSubmitTransferOptions {
        guard let resolved = context.transactionDraft?.resolvedAddress else {
            throw DisplayError(text: lang("Address not resolved"))
        }
        let diesel = context.transactionDraft?.diesel
        return ApiSubmitTransferOptions(
            accountId: context.accountId,
            toAddress: resolved,
            amount: context.amount ?? 0,
            payload: context.payload,
            stateInit: context.stateInit,
            tokenAddress: context.token.tokenAddress,
            realFee: explainedFee?.realFee?.nativeSum,
            isGasless: explainedFee?.isGasless,
            dieselAmount: diesel?.tokenAmount,
            isGaslessWithStars: diesel?.status == .starsFee,
            gaslessTransaction: diesel?.transaction,
            password: password,
            fee: explainedFee?.fullFee?.nativeSum,
            noFeeCheck: nil
        )
    }
    
    func validateDraft(context: SendDraftContext) async throws -> SendFlowDraftResult {
        let chain = context.token.chain
        
        let options = ApiCheckTransactionDraftOptions(
            accountId: context.accountId,
            toAddress: context.address,
            amount: context.amount ?? 0,
            payload: context.payload,
            stateInit: context.stateInit,
            tokenAddress: context.token.tokenAddress,
            allowGasless: true
        )
        
        let draft = try await Api.checkTransactionDraft(chain: chain, options: options)
        try handleDraftError(draft)
        
        if draft.error == .walletNotInitialized {
            throw SdkError.message(.walletNotInitialized)
        }

        if isAddressDraftError(draft.error) {
            return SendFlowDraftResult(
                draftData: DraftData(
                    status: .invalid,
                    transactionDraft: draft
                ),
                explainedFee: draft.explainedFee,
                requiresMemo: false
            )
        }
        
        let explainedFee = draft.explainedFee
        
        return SendFlowDraftResult(
            draftData: DraftData(
                status: .valid,
                transactionDraft: draft
            ),
            explainedFee: explainedFee,
            requiresMemo: draft.isMemoRequired ?? false
        )
    }
    
    func submit(context: SendSubmitContext, password: String?, explainedFee: ExplainedTransferFee?) async throws -> SendFlowSubmitResult {
        let transferOptions = try makeTransferOptions(context: context, password: password, explainedFee: explainedFee)
        let result = try await Api.submitTransfer(chain: context.token.chain, options: transferOptions)
        if let error = result.error {
            throw SdkError.apiReturnedError(error: error, context: result)
        }
        return SendFlowSubmitResult(mfaRequestHash: result.mfaRequestHash)
    }
    
    func ledgerPayload(context: SendSubmitContext, explainedFee: ExplainedTransferFee?) async throws -> SignData {
        let transferOptions = try makeTransferOptions(context: context, password: nil, explainedFee: explainedFee)
        return .signTransfer(transferOptions: transferOptions)
    }
}

// MARK: - NFT

struct NftSendFlow: SendFlow {
    
    func validateDraft(context: SendDraftContext) async throws -> SendFlowDraftResult {
        guard let nfts = context.nfts, let chain = nfts.first?.chain else {
            return SendFlowDraftResult.noResult
        }
        let toAddress = context.address
        let isNftBurn = context.nftSendMode == .burn
        if toAddress.isEmpty && !isNftBurn {
            return SendFlowDraftResult.noResult
        }
        let draft = try await Api.checkNftTransferDraft(chain: chain, options: .init(
            accountId: context.accountId,
            nfts: nfts,
            toAddress: toAddress,
            comment: context.payload?.comment,
            isNftBurn: isNftBurn
        ))
        try handleDraftError(draft)

        if isAddressDraftError(draft.error) {
            return SendFlowDraftResult(
                draftData: DraftData(
                    status: .invalid,
                    transactionDraft: draft
                ),
                explainedFee: draft.explainedFee,
                requiresMemo: false
            )
        }
                
        return SendFlowDraftResult(
            draftData: DraftData(
                status: .valid,
                transactionDraft: draft
            ),
            explainedFee: draft.explainedFee,
            requiresMemo: draft.isMemoRequired ?? false
        )
    }
    
    func submit(context: SendSubmitContext, password: String?, explainedFee: ExplainedTransferFee?) async throws -> SendFlowSubmitResult {
        guard let resolved = context.transactionDraft?.resolvedAddress else {
            throw DisplayError(text: lang("Address not resolved"))
        }
        let chain = context.nfts?.first?.chain ?? context.token.chain
        let result = try await Api.submitNftTransfers(
            chain: chain,
            accountId: context.accountId,
            password: password,
            nfts: context.nfts ?? [],
            toAddress: resolved,
            comment: context.payload?.comment,
            totalRealFee: context.transactionDraft?.realNativeFee ?? 0,
            isNftBurn: context.nftSendMode == .burn
        )
        if let error = result.error {
            throw SdkError.apiReturnedError(error: error, context: nil)
        }
        return SendFlowSubmitResult(mfaRequestHash: result.mfaRequestHash)
    }
    
    func ledgerPayload(context: SendSubmitContext, explainedFee: ExplainedTransferFee?) async throws -> SignData {
        guard let nfts = context.nfts, !nfts.isEmpty else {
            throw DisplayError(text: lang("No NFT selected"))
        }
        guard let resolved = context.transactionDraft?.resolvedAddress else {
            throw DisplayError(text: lang("Address not resolved"))
        }
        let chain = nfts.first?.chain ?? context.token.chain
        if nfts.count == 1, let nft = nfts.first {
            return .signNftTransfer(
                chain: chain,
                accountId: context.accountId,
                nft: nft,
                toAddress: resolved,
                comment: context.payload?.comment,
                realFee: context.transactionDraft?.realNativeFee,
                isNftBurn: context.nftSendMode == .burn
            )
        }
        return .signNftTransfers(
            chain: chain,
            accountId: context.accountId,
            nfts: nfts,
            toAddress: resolved,
            comment: context.payload?.comment,
            realFee: context.transactionDraft?.realNativeFee,
            isNftBurn: context.nftSendMode == .burn
        )
    }
}
