
import Foundation
import WalletCore
import WalletContext

/// Handles differences between send token and send nft flows
protocol SendFlow: Sendable {
    func validateDraft(context: SendDraftContext) async throws -> SendFlowDraftResult
    func submit(context: SendSubmitContext, password: String?, explainedFee: ExplainedTransferFee?) async throws
    func ledgerPayload(context: SendSubmitContext, explainedFee: ExplainedTransferFee?) async throws -> SignData
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
    let transactionDraft: ApiCheckTransactionDraftResult?
    let diesel: ApiFetchEstimateDieselResult?
}

struct SendFlowDraftResult {
    let draftData: DraftData
    let explainedFee: ExplainedTransferFee?
    let requiresMemo: Bool
}

// MARK: - Token

struct TokenSendFlow: SendFlow {
    
    private func makeTransferOptions(context: SendSubmitContext, password: String?, explainedFee: ExplainedTransferFee?) throws -> ApiSubmitTransferOptions {
        guard let resolved = context.transactionDraft?.resolvedAddress else {
            throw BridgeCallError.customMessage(lang("Address not resolved"), nil)
        }
        return ApiSubmitTransferOptions(
            accountId: context.accountId,
            toAddress: resolved,
            amount: context.amount ?? 0,
            payload: context.payload,
            stateInit: context.stateInit,
            tokenAddress: context.token.tokenAddress,
            realFee: explainedFee?.realFee?.nativeSum,
            isGasless: explainedFee?.isGasless,
            dieselAmount: context.transactionDraft?.diesel?.tokenAmount,
            isGaslessWithStars: nil,
            password: password,
            fee: explainedFee?.fullFee?.nativeSum,
            noFeeCheck: nil
        )
    }
    
    func validateDraft(context: SendDraftContext) async throws -> SendFlowDraftResult {
        let chain = context.token.chainValue
        
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
        
        if draft.error == .domainNotResolved {
            return SendFlowDraftResult(
                draftData: DraftData(
                    status: .invalid,
                    transactionDraft: nil
                ),
                explainedFee: nil,
                requiresMemo: false
            )
        }
        
        if draft.error == .walletNotInitialized {
            throw BridgeCallError.message(.walletNotInitialized, nil)
        }
        
        let explainedFee = explainApiTransferFee(input: draft, tokenSlug: context.token.slug)
        
        return SendFlowDraftResult(
            draftData: DraftData(
                status: .valid,
                transactionDraft: draft
            ),
            explainedFee: explainedFee,
            requiresMemo: draft.isMemoRequired ?? false
        )
    }
    
    func submit(context: SendSubmitContext, password: String?, explainedFee: ExplainedTransferFee?) async throws {
        let transferOptions = try makeTransferOptions(context: context, password: password, explainedFee: explainedFee)
        let result = try await Api.submitTransfer(chain: context.token.chainValue, options: transferOptions)
        if let error = result.error {
            throw BridgeCallError.customMessage(error, nil)
        }
    }
    
    func ledgerPayload(context: SendSubmitContext, explainedFee: ExplainedTransferFee?) async throws -> SignData {
        let transferOptions = try makeTransferOptions(context: context, password: nil, explainedFee: explainedFee)
        return .signTransfer(transferOptions: transferOptions)
    }
}

// MARK: - NFT

struct NftSendFlow: SendFlow {
    
    func validateDraft(context: SendDraftContext) async throws -> SendFlowDraftResult {
        let draft = try await Api.checkNftTransferDraft(options: .init(
            accountId: context.accountId,
            nfts: context.nfts ?? [],
            toAddress: context.address,
            comment: context.payload?.comment
        ))
        try handleDraftError(draft)
        
        return SendFlowDraftResult(
            draftData: DraftData(
                status: .valid,
                transactionDraft: draft
            ),
            explainedFee: nil,
            requiresMemo: draft.isMemoRequired ?? false
        )
    }
    
    func submit(context: SendSubmitContext, password: String?, explainedFee: ExplainedTransferFee?) async throws {
        guard let resolved = context.transactionDraft?.resolvedAddress else {
            throw BridgeCallError.customMessage(lang("Address not resolved"), nil)
        }
        let result = try await Api.submitNftTransfers(
            accountId: context.accountId,
            password: password,
            nfts: context.nfts ?? [],
            toAddress: resolved,
            comment: context.payload?.comment,
            totalRealFee: context.transactionDraft?.realFee ?? 0
        )
        if let error = result.error {
            throw BridgeCallError(message: error, payload: nil)
        }
    }
    
    func ledgerPayload(context: SendSubmitContext, explainedFee: ExplainedTransferFee?) async throws -> SignData {
        guard let nft = context.nfts?.first, context.nfts?.count == 1 else {
            throw DisplayError(text: lang("Sending more than one NFT isn't supported by Ledger"))
        }
        guard let resolved = context.transactionDraft?.resolvedAddress else {
            throw BridgeCallError.customMessage(lang("Address not resolved"), nil)
        }
        return .signNftTransfer(
            accountId: context.accountId,
            nft: nft,
            toAddress: resolved,
            comment: context.payload?.comment,
            realFee: context.transactionDraft?.realFee
        )
    }
}


