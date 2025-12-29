
import Foundation
import WalletCore
import WalletContext

/// Handles differences between send token and send nft flows
protocol SendFlow: Sendable {
    func validateDraft(context: SendFlowContext) async throws -> SendFlowDraftResult
    func submit(context: SendFlowContext, password: String?, explainedFee: ExplainedTransferFee?) async throws
    func ledgerPayload(context: SendFlowContext, explainedFee: ExplainedTransferFee?) async throws -> SignData
}

struct SendFlowContext: Sendable {
    let accountId: String
    let address: String
    let resolvedAddress: String?
    let token: ApiToken
    let amount: BigInt?
    let comment: String?
    let binaryPayload: String?
    let payload: AnyTransferPayload?
    let stateInit: String?
    let nfts: [ApiNft]?
    let nftSendMode: NftSendMode?
    let diesel: ApiFetchEstimateDieselResult?
    let transactionDraft: ApiCheckTransactionDraftResult?
}

struct SendFlowDraftResult {
    let draftData: DraftData
    let explainedFee: ExplainedTransferFee?
    let requiresMemo: Bool
}

// MARK: - Token

struct TokenSendFlow: SendFlow {
    
    func validateDraft(context: SendFlowContext) async throws -> SendFlowDraftResult {
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
                    address: context.address,
                    tokenSlug: context.token.slug,
                    amount: context.amount,
                    comment: context.comment,
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
                address: context.address,
                tokenSlug: context.token.slug,
                amount: context.amount,
                comment: context.comment,
                transactionDraft: draft
            ),
            explainedFee: explainedFee,
            requiresMemo: draft.isMemoRequired ?? false
        )
    }
    
    func submit(context: SendFlowContext, password: String?, explainedFee: ExplainedTransferFee?) async throws {
        
        let transferOptions = ApiSubmitTransferOptions(
            accountId: context.accountId,
            toAddress: context.resolvedAddress ?? context.address,
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
        let result = try await Api.submitTransfer(chain: context.token.chainValue, options: transferOptions)
        if let error = result.error {
            throw BridgeCallError.customMessage(error, nil)
        }
    }
    
    func ledgerPayload(context: SendFlowContext, explainedFee: ExplainedTransferFee?) async throws -> SignData {
        
        let transferOptions = ApiSubmitTransferOptions(
            accountId: context.accountId,
            toAddress: context.resolvedAddress ?? context.address,
            amount: context.amount ?? 0,
            payload: context.payload,
            stateInit: context.stateInit,
            tokenAddress: context.token.tokenAddress,
            realFee: explainedFee?.realFee?.nativeSum,
            isGasless: explainedFee?.isGasless,
            dieselAmount: context.transactionDraft?.diesel?.tokenAmount,
            isGaslessWithStars: nil,
            password: nil,
            fee: explainedFee?.fullFee?.nativeSum,
            noFeeCheck: nil
        )
        return .signTransfer(transferOptions: transferOptions)
    }
}

// MARK: - NFT

struct NftSendFlow: SendFlow {
    
    func validateDraft(context: SendFlowContext) async throws -> SendFlowDraftResult {
        let nfts = context.nfts ?? []
        let toAddress = context.address
        let comment = context.comment
        
        let draft = try await Api.checkNftTransferDraft(options: .init(
            accountId: context.accountId,
            nfts: nfts,
            toAddress: toAddress,
            comment: comment
        ))
        try handleDraftError(draft)
        
        return SendFlowDraftResult(
            draftData: DraftData(
                status: .valid,
                address: toAddress,
                tokenSlug: context.token.slug,
                amount: context.amount,
                comment: context.comment,
                transactionDraft: draft
            ),
            explainedFee: nil,
            requiresMemo: draft.isMemoRequired ?? false
        )
    }
    
    func submit(context: SendFlowContext, password: String?, explainedFee: ExplainedTransferFee?) async throws {
        
        let result = try await Api.submitNftTransfers(
            accountId: context.accountId,
            password: password,
            nfts: context.nfts ?? [],
            toAddress: context.address,
            comment: context.comment,
            totalRealFee: context.transactionDraft?.realFee ?? 0
        )
        if let error = result.error {
            throw BridgeCallError(message: error, payload: nil)
        }
    }
    
    func ledgerPayload(context: SendFlowContext, explainedFee: ExplainedTransferFee?) async throws -> SignData {
        guard let nft = context.nfts?.first, context.nfts?.count == 1 else {
            throw DisplayError(text: lang("Sending more than one NFT isn't supported by Ledger"))
        }
        return .signNftTransfer(
            accountId: context.accountId,
            nft: nft,
            toAddress: context.address,
            comment: context.comment,
            realFee: context.transactionDraft?.realFee
        )
    }
}


