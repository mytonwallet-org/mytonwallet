import WalletCore

struct TokenSendFeeQuote: Sendable {
    let request: TokenSendFeeQuoteRequest
    let fee: ExplainedTransferFee?
}
